# Durable session QoS2 memory growth: EMQX 6.3.3

This patch reduces the memory that durable sessions publishing QoS2 messages add to the
durable-storage shard processes, and the number of storage operations such sessions perform.
It is the hot-patch packaging of [emqx#19997](https://github.com/emqx/emqx/pull/19997)
([`source.patch`](source.patch)) and changes eight modules:

```
emqx_ds.beam                              emqx_persistent_session_ds_state.beam
emqx_ds_optimistic_tx.beam                emqx_persistent_session_ds_state_v2.beam
emqx_ds_pmap.beam                         emqx_ds_tx_conflict_trie.beam
emqx_ds_shared_sub_dl.beam                emqx_mq_state_storage.beam
```

## What grows

A durable session tracks every QoS2 message it receives in the `awaiting_rel` map: one key
added on PUBREC, the same key deleted on PUBCOMP. Until this patch, both updates reached the
optimistic transaction manager of the session's shard as **per-key** entries in its conflict
index, and the deletion of an absent key still produced a storage operation. The entries are
kept for the conflict window, so the index grows with the message rate and does not settle.
In the validation below the shard managers grew by roughly 40 MB per 1,000 msg/s of sustained
QoS2 traffic until the node ran out of memory; see
[Source and validation](#source-and-validation).

The patch marks the topic filter of each pmap collection as a single conflict unit
(`emqx_ds:tx_mark_dirty/4`), so per-key entries collapse into one wildcard entry per
collection and shard, and the pmap layer skips storage operations that cannot change
anything, such as deleting a key known to be absent.

## Compatibility and checksum

The beams were built for the 6.3 line (Erlang/OTP 28) and verified against 6.3.3. Check the
downloaded files from this patch directory:

```sh
(cd 6.3 && sha256sum -c *.sha256)
```

On a running node, check the version and the loaded modules before applying:

```sh
emqx eval '{emqx_release:version(), erlang:system_info(otp_release)}.'
```

Expect `6.3.3` and `28`. Then verify that every module below has its original code MD5.
**Stop if any fingerprint differs.** Code MD5 is a module fingerprint, not the file checksum.

```sh
for M in emqx_ds emqx_ds_optimistic_tx emqx_ds_pmap emqx_ds_shared_sub_dl \
         emqx_ds_tx_conflict_trie emqx_mq_state_storage \
         emqx_persistent_session_ds_state emqx_persistent_session_ds_state_v2; do
  emqx eval "io:format(\"~s: ~s~n\", [code:which($M), binary:encode_hex($M:module_info(md5))])."
done
```

| Module | Original code MD5 (6.3.3) | Patched code MD5 |
| --- | --- | --- |
| `emqx_ds` | `09BE1667A33C2690FBC111C8F319D010` | `75A3BDE07E6EA0F35C57759715D4C09B` |
| `emqx_ds_optimistic_tx` | `A6E0C08F1773229DAFC0FF86F325E52A` | `12E6675CF3D268469A1C5EBCB847DB33` |
| `emqx_ds_pmap` | `F32949E8C95E24726091996AD7F9D76E` | `2E0B53121FF0B47AABB86187DE5D40A7` |
| `emqx_ds_shared_sub_dl` | `798910548EF7ABF4738626F7D5B32820` | `824E0BB9BF9F83B2317C06E1FE258C49` |
| `emqx_ds_tx_conflict_trie` | `3486B6B8DC1C0643809439BF8CA5B7C4` | `98BAA48E330B6B9B71AB7F72C93E6AD9` |
| `emqx_mq_state_storage` | `5345D157B0CE272A22BD2F33CC44FE9B` | `D63F298A2D05009375C304F1794081E9` |
| `emqx_persistent_session_ds_state` | `AE7F2B24D002DA8ECB9658B096E34D24` | `01DCCBE2D879C47DDB1879327217E172` |
| `emqx_persistent_session_ds_state_v2` | `AC27A59FBADC8222ABF6B372BB00CEE0` | `B570CFDB8127EA017C8BF8474585C496` |

## A. Install before node startup

Copy the verified beams into the patches directory (see the
[repository README](../README.md)) before starting the node. For the official container:

```sh
mkdir -p /opt/emqx/data/patches
cp 6.3/*.beam /opt/emqx/data/patches/
```

Start the node normally, then [verify the loaded modules](#verify-the-loaded-modules).

## B. Install on a running node, then restart

Copy the verified beams into the patches directory of the running node and restart it. The
patches directory is ahead of the release on the code path, so the restarted node loads the
patched modules at boot:

```sh
cp 6.3/*.beam /opt/emqx/data/patches/
# then restart the node
```

Both procedures were verified. A live reload (`c:l/1`) without a restart was not covered by
the validation below; use a restart.

## Verify the loaded modules

After either procedure, on every node:

```sh
for M in emqx_ds emqx_ds_optimistic_tx emqx_ds_pmap emqx_ds_shared_sub_dl \
         emqx_ds_tx_conflict_trie emqx_mq_state_storage \
         emqx_persistent_session_ds_state emqx_persistent_session_ds_state_v2; do
  emqx eval "io:format(\"~s -> ~s~n\", [code:which($M), binary:encode_hex($M:module_info(md5))])."
done
```

Expect a path ending in `patches/<module>.beam` and the patched code MD5 of every module.
Pod readiness alone does not prove the patched beams were loaded.

The patched `emqx_ds` also answers a check for the new API:

```sh
emqx eval 'erlang:function_exported(emqx_ds, tx_mark_dirty, 4).'
```

Expect `true`.

## Remove before upgrading

Remove the eight beams from the patches directory, and any deployment step that copies them
there, before starting an upgraded node. The fix ships in the releases that follow 6.3.3
([emqx#19997](https://github.com/emqx/emqx/pull/19997)); a file left behind overrides the
modules of the new release.

## Source and validation

The beams were built from the dev-63 sources that carry
[`source.patch`](source.patch), the dev-63 form of
[emqx#19997](https://github.com/emqx/emqx/pull/19997), compiled for the 6.3
line with the compiler of the release image (Erlang/OTP 28, `compiler-9.0.5`).

Besides the patch, `emqx_ds_optimistic_tx.beam` includes the post-6.3.3 changes to
that module on dev-63: the receive loop split into `handle_call`/`handle_cast`, and
exit-reason unwrapping ([7470a9ed99](https://github.com/emqx/emqx/commit/7470a9ed99),
[79ede07ac7](https://github.com/emqx/emqx/commit/79ede07ac7) and related fixes). The other
seven modules are `6.3.3 + source.patch` exactly. Accordingly, `source.patch` is diffed
against dev-63 and does not apply to the 6.3.3 sources as-is.

The validation below used the beams as shipped; they were not rebuilt. Their compile
metadata (Erlang/OTP 28, `compiler-9.0.5`) and their exported functions match the sources
described above, but reproducing the build was not part of the validation.

Validated on a single node, official image `emqx/emqx:6.3.3`
(`sha256:54778dba62a5cbcb03ca381c9bceb3d8a87cab9e3da155ed3607d994454df900`), durable sessions
enabled with `EMQX_DURABLE_SESSIONS__ENABLE=true`, on an 8-core, 3.8 GiB host. Load: `emqttb`
commit [27136b3](https://github.com/emqx/emqttb/commit/27136b3) (2026-11-16, includes the pub
scenario session-expiry fix; published as 1.0.9), MQTT v5 durable sessions (`clean_start =
false`, session expiry 3600 s), QoS 2, 256-byte payloads, publishers on the same host.

With the patch installed at boot, the node started without errors: no log errors or crashes,
all eight modules loaded from `patches`, `tx_mark_dirty/4` present, and durable sessions
worked (`session.resumed` on reconnect). The same node then sustained the full load without a
restart. Results, one run each, memory sampled every 5 s (`otx` = the 64 optimistic
transaction manager processes that keep the conflict index):

| Stage (durable publishers, QoS 2) | Unpatched sustained | Patched sustained | Unpatched otx memory | Patched otx memory |
| --- | --- | --- | --- | --- |
| 50 clients × 100 msg/s, 90 s | 4,508 msg/s | 4,512 msg/s | 172 MB | 2.4 MB |
| 200 clients × 100 msg/s, 120 s | 17,838 msg/s | 18,748 msg/s | 732 MB | 5.8 MB |
| 500 clients × 200 msg/s, 180 s | node killed by OOM after ~80 s at ~52,000 msg/s | 73,895 msg/s for the full 180 s | 4,530 MB at death (8.6 GB total) | 14.4 MB (314 MB total) |

The unpatched result was reproduced twice (4,508 / 4,549, 17,838 / 17,738 msg/s; OOM kill in
the third stage both times). The patched node finished all three stages with
`RestartCount = 0` and `OOMKilled = false`, with peak total memory of 314 MB.
