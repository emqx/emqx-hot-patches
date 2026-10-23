# 261023-eMudhra — remove a withdrawn eMudhra root certificate from the bundled CA trust store

## What this patch changes

EMQX bundles the `certifi` library, which carries a copy of the Mozilla CA trust store. `hackney`
uses `certifi:cacerts/0` as its default trust store, so that bundle is what an EMQX component
trusts when it opens an outgoing HTTPS connection with no `cacertfile` configured.

Every EMQX release line in the table below bundles `certifi` 2.15.0, whose trust store contains
`emSign ECC Root CA - G3`
(SHA-256 `86A1ECBA089C4A8D3BBE2734C612BA341D813E043CF9E8A862CD5C57A36BBE6B`). That root was withdrawn
after private keys in the eMudhra hierarchy were exposed.

This patch is `certifi` 2.15.0 with that one certificate removed. A patched node returns **142**
certificates from `certifi:cacerts/0` instead of 143. Nothing else changes.

Editing `priv/cacerts.pem` inside the release does not work, which is why a compiled module is
published here. `certifi` embeds its certificates into `certifi.beam` through the `certifi_pt`
parse transform at build time, and `hackney` reads that compiled list. The PEM file beside it is
not read for this purpose.

## Which file to take

| Release line | Latest version at publication | Erlang/OTP | File |
| --- | --- | --- | --- |
| 5.8 | 5.8.11 | 26 | [`5.8/certifi.beam`](5.8/certifi.beam) |
| 5.9 | 5.9.3 | 27 | [`5.9/certifi.beam`](5.9/certifi.beam) |
| 5.10 | 5.10.5 | 27 | [`5.10/certifi.beam`](5.10/certifi.beam) |
| 6.0 | 6.0.4 | 27 | [`6.0/certifi.beam`](6.0/certifi.beam) |
| 6.1 | 6.1.5 | 28 | [`6.1/certifi.beam`](6.1/certifi.beam) |
| 6.2 | 6.2.3 | 28 | [`6.2/certifi.beam`](6.2/certifi.beam) |
| 6.3 | 6.3.2 | 28 | [`6.3/certifi.beam`](6.3/certifi.beam) |

Lines that share an Erlang/OTP major share an identical file, so some checksums repeat.

**Do not take a 6.1, 6.2 or 6.3 file for a 5.8 node.** Those are compiled with Erlang/OTP 28 and
5.8 runs Erlang/OTP 26. The node rejects the module and keeps the original one without reporting a
failure.

Confirm that your node bundles `certifi` 2.15.0 before you start. If it reports another version,
stop and contact EMQ at <security@emqx.io>; do not install a module built against a different
`certifi` version.

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

Expect `142`. A result of `143` means the patch is not in effect.

Repeat the installation and this check on every node of the cluster. Then disable and re-enable the
affected connectors, or restart the node: a reload changes what new TLS connections trust, but a
connection already open in a `hackney` pool is not revalidated.

## Which components this affects

These components send outgoing HTTPS through `hackney` and therefore use the bundled trust store
when no `cacertfile` is configured:

- AI Completion. It passes no TLS options to `hackney`, so it always uses the bundled store and
  cannot be mitigated by configuration.
- HTTP authentication and authorization.
- S3 and S3 Tables actions, and the S3 file-transfer exporter.
- ClickHouse, OpenTSDB, TDengine and Alibaba Cloud Tablestore actions, and the DynamoDB and
  Kinesis actions, are not confirmed either way.

MQTT listeners, the Dashboard listener, Kafka, PostgreSQL, MySQL, MongoDB and the other database
connectors do not use this store. They assemble their TLS options through `emqx_tls_lib`.

Setting `cacertfile` explicitly on an outgoing connection takes the bundled store out of the path
for that connection. That is good practice independently of this patch.

## Docker images also carry an operating system trust store

A Docker image has a second trust store at `/etc/ssl/certs/ca-certificates.crt`, read by the `curl`
and `openssl` binaries in the image rather than by EMQX. This patch does not change it. Images
older than 6.3.2 carry two withdrawn roots there, `emSign ECC Root CA - G3` and
`AAA Certificate Services`. The accompanying security advisory covers that store.

Package and `tar.gz` deployments have no bundled operating system store. They use the host trust
store, which you update through your operating system vendor.

## How these files were built

1. Check out `certifi` at tag `2.15.0`. Its `priv/cacerts.pem` is byte-identical to the bundle
   shipped in the EMQX releases above, SHA-256
   `728e6c9406cdcbb47d535e206d6e4c2266fb2cdb6b1c916bae3b8687bb450342`.
2. Remove `emSign ECC Root CA - G3`. The resulting PEM is SHA-256
   `218d91328b2ac7fd3a87681876573f4956c56c952204d6a01c16e82dfaf5b269` and holds 142 certificates.
3. Lay out a work directory as `ebin/` and `priv/cacerts.pem`, because `certifi_pt` resolves the
   PEM relative to its own compiled location.
4. Compile `certifi_pt.erl`, then compile `certifi.erl` against it, with the flags from `certifi`'s
   own `rebar.config`:

   ```sh
   erlc -o ebin src/certifi_pt.erl
   erlc -o ebin -pa ebin +deterministic -DOTP_20_AND_ABOVE src/certifi.erl
   ```

The Erlang/OTP version used for each line is the one recorded in `.tool-versions` at that line's
latest release tag.

Every file was then loaded on its target Erlang/OTP release and checked: 142 certificates, none
matching `emSign ECC Root CA - G3`, and the three unrelated `emSign` roots (`G1`, `C1`, `ECC C3`)
still present. Those three are different certificates and are not part of this incident.
