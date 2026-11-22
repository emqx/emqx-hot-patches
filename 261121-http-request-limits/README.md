# HTTP request limits: EMQX Enterprise 5.8 to 6.3

This patch makes HTTP request parsing stricter on every HTTP listener of EMQX: the Dashboard and
REST API, MQTT over WebSocket, the gateway WebSocket listeners and the gRPC listeners.

It replaces 5 to 10 modules of the HTTP libraries that EMQX bundles (cowlib, cowboy and, on 6.3.3,
gun). The modules depend on each other, so the patch comes with a loader module,
`emqx_hp_http_limits`, that checks the node and loads them in one step.

## What changes

| Change | Directories |
| --- | --- |
| An HTTP/2 request is limited to 32 KB of decoded headers. For larger headers EMQX resets the HTTP/2 stream with the error code `ENHANCE_YOUR_CALM`. Other requests on the same connection are not affected. | all |
| An HTTP/1.1 request with more than 100 header lines is rejected with status 431, also when header names repeat. | all |
| A multipart request body with a part header block larger than 2048 bytes is rejected. | all |
| An HTTP/1.1 request body with a chunk size of more than 16 hex digits is rejected. | `5.8` to `6.3.0-6.3.2` |
| An HTTP/2 header block that encodes an integer of more than 38 bits is rejected with a connection error. | `5.8` to `6.3.0-6.3.2` |
| An HTTP/2 header block sent in several frames is limited to 32 KB. | `5.8` |
| An HTTP/1.1 response with a CR or LF character in a header value is not sent. EMQX sends an empty response with status 500 and closes the connection. | `6.3.3` |
| The other changes of cowlib 2.22.0 since 2.21.0, for example: an HTTP/1.1 chunk size must start with a hex digit, and the padding of HTTP/2 DATA frames counts in flow control. | `6.3.3` |

EMQX 6.3.3 already has the chunk size and integer limits, and 5.9 and later already have the limit
for header blocks sent in several frames.

EMQX also applies the 32 KB limit to the headers and trailers of HTTP/2 responses that it receives,
for example from ExHook and ExProto gRPC servers. A gRPC call fails when the server returns larger
metadata.

The same changes ship in normal releases through
[emqx/emqx#20154](https://github.com/emqx/emqx/pull/20154) (5.8),
[emqx/emqx#20155](https://github.com/emqx/emqx/pull/20155) (5.9),
[emqx/emqx#20156](https://github.com/emqx/emqx/pull/20156) (5.10) and
[emqx/emqx#20146](https://github.com/emqx/emqx/pull/20146) (6.x).

## Which files to take

| Directory | EMQX Enterprise | Erlang/OTP | Modules replaced |
| --- | --- | --- | --- |
| [`5.8/`](5.8) | 5.8.0 to 5.8.11 | 26 | 5 |
| [`5.9/`](5.9) | 5.9.0 to 5.9.3 | 27 | 5 |
| [`5.10/`](5.10) | 5.10.0 to 5.10.5 | 27 | 6 |
| [`6.0/`](6.0) | 6.0.0 to 6.0.4 | 27 | 6 |
| [`6.1/`](6.1) | 6.1.2 to 6.1.5 | 28 | 6 |
| [`6.2/`](6.2) | 6.2.0 to 6.2.3 | 28 | 6 |
| [`6.3.0-6.3.2/`](6.3.0-6.3.2) | 6.3.0, 6.3.1, 6.3.2 | 28 | 6 |
| [`6.3.3/`](6.3.3) | 6.3.3 | 28 | 10 |

Each directory also holds the loader, `emqx_hp_http_limits.beam`.

Not covered: 6.1.0 and 6.1.1 (Erlang/OTP 28.2) ship a different build of one of the modules, and
the loader reports them as `unsupported`. Upgrade those to the latest release of the line.

**Take the directory of the exact version of the node, and take every `.beam` file in it.** The
directories are not interchangeable:

- 6.3.3 bundles newer HTTP libraries than 6.3.0 to 6.3.2. The files of one do not work on the
  other.
- A file compiled for a newer Erlang/OTP does not load on an older one.

Do not copy files of two directories into the same patches directory.

Run the commands below from this patch directory, with `PATCH` set to the directory of your
version, for example `PATCH=6.0`. Check the download first:

```sh
(cd "$PATCH" && sha256sum -c *.beam.sha256)
```

## 1. Copy the files and check the node

Copy all `.beam` files into the patches directory of the node (see the
[repository README](../README.md) for its location). For Docker:

```sh
for f in "$PATCH"/*.beam; do docker cp "$f" <container>:/opt/emqx/data/patches/; done
docker exec -u 0 <container> sh -c 'chown emqx:emqx /opt/emqx/data/patches/*.beam'
```

Copying the files changes nothing yet. Now ask the loader whether the files fit the node:

```sh
emqx eval 'c:l(emqx_hp_http_limits), emqx_hp_http_limits:status().'
```

Expect a result like this one, from a 6.0.4 node:

```erlang
#{release => "6.0.4", otp_release => "27", files => "5.10 or 6.0",
  patch => not_applied,
  modules => [{cow_hpack,original,file_ok}, {cow_http2_machine,original,file_ok},
              {cow_http_te,original,file_ok}, {cow_qpack,original,file_ok},
              {cowboy_http,original,file_ok}, {cowboy_req,original,file_ok}],
  other_files => [], http2_connections => 0}
```

Continue only when every module shows `original` and `file_ok`, and `other_files` is empty.
`http2_connections` is the number of HTTP/2 connections that clients have open to the node now.

**Stop and remove the files from the patches directory** when you see one of these, because the
next restart of the node would load files that do not fit it:

| Result | Meaning |
| --- | --- |
| `error: undef`, or `c:l` returns `error` | The files are compiled for a newer Erlang/OTP: wrong directory. |
| `patch => unsupported` | The node does not run the modules of a release listed above. |
| `file_wrong`, `file_missing`, or a non-empty `other_files` | Files of another directory, or not all files, were copied. |

Then use A or B. Do it on every node of the cluster, one node at a time.

## 2A. Restart the node

Restart the node. It loads the patched modules at boot, and the restart closes every connection
that was opened before the patch. Nothing else is needed.

## 2B. Hot apply

```sh
emqx eval 'c:l(emqx_hp_http_limits), emqx_hp_http_limits:apply().'
```

Expect `{ok, #{loaded => [...], http2_connections_closed => N, ...}}`. Running it again returns
`{ok, already_applied}`.

If `http2_connections_closed` shows `{failed, _}` in place of a number, the modules are loaded but
the connections were not closed. Close them with
`emqx eval 'emqx_hp_http_limits:close_http2_connections().'`.

The loader checks the node and the files again, loads all modules in one step, and then closes
the HTTP/2 connections that clients opened before the load. A connection keeps the limits it was
opened with, so these connections must be replaced. Each one receives `GOAWAY`, and the client
reconnects. This includes the gRPC connections of ExProto services to the node. The command
returns when the connections are closed, after a few seconds at most.

What happens to a request in progress on such a connection depends on the release line:

| Release line | Request in progress on a closed HTTP/2 connection |
| --- | --- |
| 5.8, 5.9 | Aborted. The client must send it again. |
| 5.10 and later | Finishes, if it completes within about 4 seconds with the default listener options. |

Not interrupted:

- MQTT connections, including MQTT over WebSocket.
- HTTP/1.1 requests in progress. They finish under the old rules.
- HTTP/2 connections that the node itself opened to other servers (ExHook and ExProto gRPC
  servers, the GCP Pub/Sub consumer, etcd). They stay open and usable. The limit for response
  headers applies to connections opened after the load.

If the command returns an error, nothing was loaded:

| Error | What to do |
| --- | --- |
| `{unsupported, _}`, `{bad_files, _, _}`, `{files_of_another_release, _, _}` | Same as in step 1: remove the files. |
| `{old_code_in_use, Modules}` | A process still runs code from an earlier load of these modules. Wait and run the command again. Do not use `code:purge/1`: it kills that process. |
| `{load_failed, _}` | Report the full result to EMQX support. |

A file copied into a running container or pod is lost when the container is recreated. Add the
copy to the deployment as well, so that replacement nodes start patched. For Kubernetes, copy the
files from a ConfigMap into the data volume with an init container, as described for the
[Kafka no-ack patch](../261117-kafka-noack-alias/README.md#kubernetes), with all `.beam` files of
the directory in place of `wolff_producer.beam`.

## Verify

After either procedure, on every node:

```sh
emqx eval 'c:l(emqx_hp_http_limits), emqx_hp_http_limits:status().'
```

Expect `patch => applied`, and `patched` and `file_ok` for every module.

To see the limits from outside, send a request with 101 header lines, and an HTTP/2 request with
36 KB of headers (nine copies of a 4000-byte header), to the Dashboard listener:

```sh
curl -s -o /dev/null -w '%{http_code}\n' \
  $(for i in $(seq 101); do printf -- '-H x-a:1 '; done) http://<node>:18083/status

curl -sS --http2-prior-knowledge -o /dev/null \
  $(for i in $(seq 9); do printf -- '-H x-fill:%s ' "$(head -c 4000 /dev/zero | tr '\0' a)"; done) \
  http://<node>:18083/status
```

Expect `431` from the first command and
`HTTP/2 stream 1 was not closed cleanly: ENHANCE_YOUR_CALM (err 11)` from the second. An
unpatched node answers both with 200.

## Remove before upgrading

Remove the files from the patches directory, and any deployment step that copies them there,
before you start an upgraded node. Otherwise they override the libraries of the new release, and a
file built for an older Erlang/OTP can fail to load.

```sh
cd <patches-dir> && rm -f emqx_hp_http_limits.beam cow_hpack.beam cow_http.beam cow_http2.beam \
  cow_http2_machine.beam cow_http_hd.beam cow_http_struct_hd.beam cow_http_te.beam cow_qpack.beam \
  cowboy_http.beam cowboy_http2.beam cowboy_req.beam gun_http2.beam
```

To roll the patch back, remove the same files and restart the node.

## Source and validation

| Directory | cowlib | cowboy | gun | Compiled with |
| --- | --- | --- | --- | --- |
| `5.8` | 2.8.0 → [emqx/cowlib](https://github.com/emqx/cowlib) `2.8.0-emqx-3` | 2.9.2 → [emqx/cowboy](https://github.com/emqx/cowboy) `2.9.2-emqx-1` | not changed | Erlang/OTP 26.2.5.14-1 |
| `5.9` | 2.13.0 → `2.13.0-emqx-3` | 2.9.2 → `2.9.2-emqx-1` | not changed | Erlang/OTP 27.3.4.2-8 |
| `5.10`, `6.0` | 2.14.0 → `2.14.0-emqx-3` | `2.13.0-emqx-2` → `2.13.0-emqx-2.1` | not changed | Erlang/OTP 27.3.4.2-8 |
| `6.1`, `6.2`, `6.3.0-6.3.2` | 2.14.0 → `2.14.0-emqx-3` | `2.13.0-emqx-2` → `2.13.0-emqx-2.1` | not changed | Erlang/OTP 28.4.1-10 |
| `6.3.3` | 2.21.0 → 2.22.0 | `2.13.0-emqx-5` → `2.13.0-emqx-6` | 2.7.0 → 2.8.0 | Erlang/OTP 28.4.1-10 |

- Directories on the same row hold identical files.
- Each directory holds the modules whose compiled code differs between the two versions, and
  [`source.patch`](6.3.3/source.patch), the source difference they were compiled from. A source
  file that changes only type declarations (`cow_http2` on 5.10 to 6.3.2, `gun` on 6.3.3) compiles
  to identical code and is not shipped.
- The cowboy modules of `2.13.0-emqx-2` that this patch replaces are identical in the cowboy
  versions of 6.1 to 6.3.2.
- On 6.3.3, `cow_http2_machine` has one addition to cowlib 2.22.0: it also accepts the form in
  which cowlib 2.21.0 keeps the recently reset streams of a connection, so that connections opened
  before a hot apply keep working. The WebSocket modules of cowboy, which also differ between the
  two cowboy versions, are not part of the patch: MQTT over WebSocket connections run them.
- The files were compiled with `+debug_info +deterministic`. Building the unpatched sources the
  same way reproduces the code MD5 of every cowlib and cowboy module (and every gun module on
  6.3.3) of the official `emqx/emqx-enterprise` images of 5.8.11, 5.9.3, 5.10.5, 6.0.4, 6.2.3 and
  6.3.3, except the WebSocket modules of cowboy on 6.2.3, which the patch does not touch.
- The original modules that the patch replaces were read from the official image of every release
  listed under [Which files to take](#which-files-to-take). Their code MD5 is the one the loader
  expects.
- The loader source is [`emqx_hp_http_limits.erl`](emqx_hp_http_limits.erl). Its `sets/0` lists
  the code MD5 of every original and patched module.

Each directory was tested on an official image with the commands in this README, with
connections open during the hot apply:

| Image | Directory | HTTP/2 connections open before the hot apply | HTTP/2 connections closed by the hot apply | Status of a request with 101 header lines, before → after | Result of an HTTP/2 request with 36 KB of headers, before → after |
| --- | --- | --- | --- | --- | --- |
| `emqx/emqx-enterprise:5.8.11` | `5.8` | 3 | 3 | 200 → 431 | 200 → stream reset, `ENHANCE_YOUR_CALM` |
| `emqx/emqx-enterprise:5.9.3` | `5.9` | 3 | 3 | 200 → 431 | 200 → stream reset, `ENHANCE_YOUR_CALM` |
| `emqx/emqx-enterprise:5.10.5` | `5.10` | 3 | 3 | 200 → 431 | 200 → stream reset, `ENHANCE_YOUR_CALM` |
| `emqx/emqx-enterprise:6.0.4` | `6.0` | 3 | 3 | 200 → 431 | 200 → stream reset, `ENHANCE_YOUR_CALM` |
| `emqx/emqx-enterprise:6.1.5` | `6.1` | 3 | 3 | 200 → 431 | 200 → stream reset, `ENHANCE_YOUR_CALM` |
| `emqx/emqx-enterprise:6.2.3` | `6.2` | 3 | 3 | 200 → 431 | 200 → stream reset, `ENHANCE_YOUR_CALM` |
| `emqx/emqx-enterprise:6.3.2` | `6.3.0-6.3.2` | 3 | 3 | 200 → 431 | 200 → stream reset, `ENHANCE_YOUR_CALM` |
| `emqx/emqx-enterprise:6.3.3` | `6.3.3` | 3 | 3 | 200 → 431 | 200 → stream reset, `ENHANCE_YOUR_CALM` |

One run per image. On every image, in the same run:

- An MQTT over WebSocket subscriber connected before the hot apply received messages after it.
- An HTTP/2 connection opened by the node to another server before the hot apply answered a
  request after it.
- The same requests on a TLS listener (HTTP/2 selected through ALPN) gave the same results.
- A multipart request with a 100 KB part header block was accepted before the hot apply and
  rejected after it.
- After a restart with the files in place, `status/0` returned `patch => applied`, and the two
  requests of the table were rejected again.

In separate runs:

- On 5.8.11, 5.9.3, 5.10.5 and 6.2.3, a request body with an 18-digit chunk size was accepted
  before the hot apply and rejected after it.
- A request in progress on an HTTP/2 connection, completed 1.5 seconds after the close started,
  was answered on 5.10.5 and 6.3.3, and aborted on 5.8.11.
- An HTTP/1.1 request with a chunked body, started before the hot apply and completed after it,
  was answered with 200 on 5.8.11 and 6.3.3.
- The files of another directory were refused: 6.3.3 files on 6.3.2, 6.3.0 to 6.3.2 files on
  6.3.3, and Erlang/OTP 28 files on 6.0.4.
