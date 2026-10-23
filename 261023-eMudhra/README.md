# 261023-eMudhra — remove the compromised eMudhra root certificates from the bundled CA trust store

## What this patch changes

EMQX bundles the `certifi` library, which carries a copy of the Mozilla CA trust store. `hackney`
uses `certifi:cacerts/0` as its default trust store, so that bundle is what an EMQX component
trusts when it opens an outgoing HTTPS connection with no `cacertfile` configured.

The two major lines bundle different `certifi` versions, and the two versions contain different
compromised roots:

| Lines | certifi shipped | Compromised roots it contains | Certificates before → after patch |
| --- | --- | --- | --- |
| 5.8, 5.9, 5.10 | 2.10.0 | `emSign ECC Root CA - G3` and `AAA Certificate Services` | 142 → **140** |
| 6.0, 6.1, 6.2, 6.3 | 2.15.0 | `emSign ECC Root CA - G3` | 143 → **142** |

SHA-256 of the two roots: `emSign ECC Root CA - G3` is
`86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B`; `AAA Certificate Services` is
`D7A7A0FB5D7E2731D771E9484EBCDEF71D5F0C3E0A2948782BC83EE0EA699EF4`. Both were withdrawn after
private keys in the eMudhra hierarchy were exposed.

Each file here is the `certifi` version its line ships, with the compromised roots that version
contains removed. Nothing else changes.

Editing `priv/cacerts.pem` inside the release does not work, which is why compiled modules are
published here. `certifi` embeds its certificates into `certifi.beam` through the `certifi_pt`
parse transform at build time, and `hackney` reads that compiled list. The PEM file beside it is
not read for this purpose.

## Which file to take

| Release line | Latest version at publication | Erlang/OTP | certifi | Expect after patch | File |
| --- | --- | --- | --- | --- | --- |
| 5.8 | 5.8.11 | 26 | 2.10.0 | 140 | [`5.8/certifi.beam`](5.8/certifi.beam) |
| 5.9 | 5.9.3 | 27 | 2.10.0 | 140 | [`5.9/certifi.beam`](5.9/certifi.beam) |
| 5.10 | 5.10.5 | 27 | 2.10.0 | 140 | [`5.10/certifi.beam`](5.10/certifi.beam) |
| 6.0 | 6.0.4 | 27 | 2.15.0 | 142 | [`6.0/certifi.beam`](6.0/certifi.beam) |
| 6.1 | 6.1.5 | 28 | 2.15.0 | 142 | [`6.1/certifi.beam`](6.1/certifi.beam) |
| 6.2 | 6.2.3 | 28 | 2.15.0 | 142 | [`6.2/certifi.beam`](6.2/certifi.beam) |
| 6.3 | 6.3.2 | 28 | 2.15.0 | 142 | [`6.3/certifi.beam`](6.3/certifi.beam) |

Lines that share both an Erlang/OTP major and a `certifi` version share an identical file, so some
checksums repeat. 5.9 and 5.10 share one; 6.1, 6.2 and 6.3 share another.

**Take the file for your own line, even when another line uses the same Erlang/OTP.** A 6.0 file
loads on a 5.9 or 5.10 node, because both run Erlang/OTP 27, but it is built from a different
`certifi` and replaces the node's trust store with a different set of roots.

**Do not take a 6.1, 6.2 or 6.3 file for a 5.8 node.** Those are compiled with Erlang/OTP 28 and
5.8 runs Erlang/OTP 26. The node rejects the module and keeps the original one without reporting a
failure.

Confirm that your node bundles the `certifi` version listed for your line before you start. If it
reports another version, stop and contact EMQ at <security@emqx.io>; do not install a module built
against a different `certifi` version.

```sh
# Docker
docker exec <container> ls -d /opt/emqx/lib/certifi-*
# package or tar.gz
ls -d <install-dir>/lib/certifi-*
```

## Installing it

The patches directory is given in the repository README. For Docker:

```sh
sha256sum -c certifi.beam.sha256
docker cp certifi.beam <container>:/opt/emqx/data/patches/certifi.beam
docker exec -u 0 <container> chown emqx:emqx /opt/emqx/data/patches/certifi.beam
docker exec <container> /opt/emqx/bin/emqx eval 'c:l(certifi).'
```

Expect `{module,certifi}`.

## Verifying that it took effect

```sh
docker exec <container> /opt/emqx/bin/emqx eval 'length(certifi:cacerts()).'
```

Expect **140** on 5.8, 5.9 and 5.10, and **142** on 6.x. The unpatched counts are 142 and 143
respectively; seeing one of those means the patch is not in effect.

Repeat the installation and this check on every node of the cluster. Then disable and re-enable the
affected connectors, or restart the node: a reload changes what new TLS connections trust, but a
connection already open in a `hackney` pool is not revalidated.

## Which components this affects

These components send outgoing HTTPS through `hackney` and therefore use the bundled trust store
when no `cacertfile` is configured:

- AI Completion. It passes no TLS options to `hackney`, so it always uses the bundled store and
  cannot be mitigated by configuration.
- ClickHouse, OpenTSDB and TDengine actions. Their connectors expose no TLS settings and their
  client libraries pass no TLS options to `hackney`.
- Alibaba Cloud Tablestore action. Its connector schema exposes `cacertfile`, but the value is never
  passed to the client library, so it is accepted and ignored.
- HTTP authentication and authorization, and the S3, S3 Tables and S3 file-transfer components. These
  pass a configured `cacertfile` through, so setting one takes the bundled store out of the path.

MQTT listeners, the Dashboard listener, Kafka, PostgreSQL, MySQL, MongoDB and the other database
connectors do not use this store. They assemble their TLS options through `emqx_tls_lib`. The
DynamoDB and Kinesis actions use `lhttpc` through `erlcloud`, not `hackney`, and are not affected
by this patch.

## Docker images also carry an operating system trust store

A Docker image has a second trust store at `/etc/ssl/certs/ca-certificates.crt`, read by the `curl`
and `openssl` binaries in the image rather than by EMQX. This patch does not change it. Images
other than the 6.3.2 re-published on 2026-10-22 carry both roots there. The accompanying security
advisory covers that store.

Package and `tar.gz` deployments have no bundled operating system store. They use the host trust
store, which you update through your operating system vendor.

## How these files were built

For each line, the `certifi` tag that line ships was checked out and its `priv/cacerts.pem`
confirmed byte-identical to the bundle inside the EMQX release:

| certifi tag | Source `priv/cacerts.pem` SHA-256 | After removal | Certificates |
| --- | --- | --- | --- |
| 2.10.0 | `2dd8cb2133364f8136db24e6e174f0053463d81039b31b0b8fdd11ca7417dabb` | `1a7793b685b12bb42c4ef800802bef817221a86463a0228041b0b3dc82f0ab13` | 140 |
| 2.15.0 | `728e6c9406cdcbb47d535e206d6e4c2266fb2cdb6b1c916bae3b8687bb450342` | `218d91328b2ac7fd3a87681876573f4956c56c952204d6a01c16e82dfaf5b269` | 142 |

Then, in a work directory laid out as `ebin/` and `priv/cacerts.pem` (because `certifi_pt` resolves
the PEM relative to its own compiled location), with the flags from `certifi`'s own `rebar.config`:

```sh
erlc -o ebin src/certifi_pt.erl
erlc -o ebin -pa ebin +deterministic -DOTP_20_AND_ABOVE src/certifi.erl
```

The Erlang/OTP version used for each line is the one recorded in `.tool-versions` at that line's
latest release tag. Every file was then loaded on its target Erlang/OTP release and checked for the
expected count and for the absence of both compromised roots.
