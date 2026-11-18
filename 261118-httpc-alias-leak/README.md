# httpc alias leak: EMQX Enterprise 5.8 to 6.3

This patch stops a memory leak in the Erlang/OTP HTTP client, `httpc`. It changes only
`httpc.beam`.

## What leaks

Since EMQX 5.8.8, the bundled `httpc` creates a process alias for every request, but releases it
only when a synchronous request receives its answer. Every asynchronous request, and every
synchronous request that fails before it is sent (for example an unsupported URL scheme), leaves
an active alias of about 100 bytes in the process that made the request. The memory is counted in
`process_info(Pid, memory)` but not in the heap size, and garbage collection does not free it. It is
released only when that process exits.

In EMQX the steady source is JWT authentication with a JWKS endpoint: the JWKS client refreshes the
key set with asynchronous requests from one long-lived process, so that process grows with every
refresh. Other `httpc` callers (CRL and OCSP caches, the Prometheus push gateway, telemetry) leak
only when a request fails early.

The patch stops new leaks. **It does not free memory already leaked**; that memory stays with the
process that holds it until the process exits. A node restart releases it.

## Compatibility and checksum

Take the file for your own release line.

| Release line | Releases | Erlang/OTP | Original code MD5 | Patched code MD5 | File |
| --- | --- | --- | --- | --- | --- |
| 5.8 | 5.8.8 to 5.8.11 | 26 | `829A13AAAE1EA1A2E2B21562D6074F79` | `A91D95037F9968B0319866166FA3EB4B` | [`5.8/httpc.beam`](5.8/httpc.beam) |
| 5.9 | 5.9.2, 5.9.3 | 27 | `3B0278E208463905458CC555E9F7883C` | `98BFBA47083673B07C4D861C366F80E6` | [`5.9/httpc.beam`](5.9/httpc.beam) |
| 5.10 | 5.10.1 to 5.10.5 | 27 | `3B0278E208463905458CC555E9F7883C` | `98BFBA47083673B07C4D861C366F80E6` | [`5.10/httpc.beam`](5.10/httpc.beam) |
| 6.0 | 6.0.0 to 6.0.4 | 27 | `3B0278E208463905458CC555E9F7883C` | `98BFBA47083673B07C4D861C366F80E6` | [`6.0/httpc.beam`](6.0/httpc.beam) |
| 6.1 | 6.1.2 to 6.1.5 | 28 | `515AAF4D9B7FDE1C98954C4C4DEFF32C` | `B464413F373656C53C07108EF3A1A1EA` | [`6.1/httpc.beam`](6.1/httpc.beam) |
| 6.2 | 6.2.0 to 6.2.3 | 28 | `515AAF4D9B7FDE1C98954C4C4DEFF32C` | `B464413F373656C53C07108EF3A1A1EA` | [`6.2/httpc.beam`](6.2/httpc.beam) |
| 6.3 | 6.3.0 to 6.3.3 | 28 | `515AAF4D9B7FDE1C98954C4C4DEFF32C` | `B464413F373656C53C07108EF3A1A1EA` | [`6.3/httpc.beam`](6.3/httpc.beam) |

Lines on the same Erlang/OTP build share an identical file. Code MD5 is a module fingerprint, not
the file checksum.

Not covered: 5.9.0, 5.9.1 and 5.10.0 (Erlang/OTP 27.2), and 6.1.0 and 6.1.1 (Erlang/OTP 28.2) ship a
different `httpc`. Upgrade those to the latest release of the line. Releases before 5.8.8 do not
have this leak.

Check the downloaded file, from this patch directory:

```sh
(cd 6.3 && sha256sum -c httpc.beam.sha256)
```

On the running node, check the version and the loaded module before applying:

```sh
emqx eval '{emqx_release:version(), erlang:system_info(otp_release),
  binary:encode_hex(httpc:module_info(md5))}.'
```

Expect a release and Erlang/OTP major from the table, and the original code MD5 of that line.
**Stop if the fingerprint differs.**

## A. Install before node startup

Copy the verified file into the patches directory (see the [repository README](../README.md)), then
start or restart the node:

```sh
cp 6.3/httpc.beam /opt/emqx/data/patches/
```

The node loads the patched module at boot. A restart also frees the memory already leaked.

For Kubernetes, copy the file from a ConfigMap into the data volume with an init container, as
described for the [Kafka no-ack patch](../261117-kafka-noack-alias/README.md#kubernetes). Use
`httpc.beam` in place of `wolff_producer.beam`.

## B. Hot apply to stop further growth

Copy the verified file into the running node's patches directory, then load it:

```sh
cp 6.3/httpc.beam /opt/emqx/data/patches/
emqx eval 'case code:soft_purge(httpc) of true -> c:l(httpc); false -> old_code_in_use end.'
```

Expect `{module,httpc}`. No restart of the node, a listener or an authenticator is needed. HTTP
requests already in progress complete normally.

`old_code_in_use` means a process still runs code from an earlier load of `httpc`. Nothing was
changed; wait for that request to finish and run the command again. Do not use `code:purge/1`
for this: it kills that process.

A file copied into a running container or pod is lost when the container is recreated. Use A in
the deployment configuration as well, so that replacement nodes stay patched.

## Verify the loaded module

After either procedure, on every node:

```sh
emqx eval '{binary:encode_hex(httpc:module_info(md5)), code:which(httpc)}.'
```

Expect the patched code MD5 of your line and a path ending in `patches/httpc.beam`.

## Remove before upgrading

Remove `httpc.beam` from the patches directory, and any deployment step that copies it there,
before starting an upgraded node. Otherwise it overrides the Erlang/OTP library of the new
release, and a file built for an older Erlang/OTP can fail to load.

## Source and validation

Each file was compiled from the `httpc.erl` of the emqx/otp tag the line ships
(`OTP-26.2.5.14-1`, `OTP-27.3.4.2-8`, `OTP-28.4.1-10`) with [`source.patch`](6.3/source.patch), with
the compile options of the release (`debug_info`, the `app_vsn` attribute) and `+deterministic`.
Building the unpatched source the same way reproduces the original code MD5 of each official image.
The `httpc.erl` source and the compiler are identical across every emqx/otp build of these
Erlang/OTP lines, so all releases listed above ship the same original module.

Each file was tested on the latest official image of its line, with the hot apply command in this
README. Growth is how much a fresh process grows after 10,000 asynchronous requests to a closed
local port:

| Image | Original MD5 matched | Growth before (bytes per 10,000 async requests) | Growth after hot apply (bytes per 10,000 async requests) | After restart, loaded from `patches` |
| --- | --- | --- | --- | --- |
| `emqx/emqx-enterprise:5.8.11` | yes | 960,016 | 16 | yes |
| `emqx/emqx-enterprise:5.9.3` | yes | 1,120,016 | 16 | yes |
| `emqx/emqx-enterprise:5.10.5` | yes | 1,120,016 | 16 | yes |
| `emqx/emqx-enterprise:6.0.4` | yes | 1,120,016 | 16 | yes |
| `emqx/emqx-enterprise:6.1.5` | yes | 1,120,016 | 16 | yes |
| `emqx/emqx-enterprise:6.2.3` | yes | 1,120,016 | 16 | yes |
| `emqx/emqx-enterprise:6.3.3` | yes | 1,120,016 | 16 | yes |

One run per image, measured after garbage collection. A synchronous
request returned normally after the load on every image. On standalone Erlang/OTP nodes, a
synchronous request that was waiting during the load completed normally.

The permanent fix for Erlang/OTP 26 is [emqx/otp#133](https://github.com/emqx/otp/pull/133); the
same change follows for the Erlang/OTP 27 and 28 lines.
