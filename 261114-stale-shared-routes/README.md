# 261114-stale-shared-routes — remove shared subscription members of departed nodes

## What this patch fixes

With the default routing schema (`broker.routing.storage_schema = v3`), when a node leaves the
cluster or stays down, and the node could not remove its own shared subscription members before it
went away, these members stay in the cluster. Messages to the shared subscription group can still
be dispatched to these members, and these messages are lost, at every QoS level.

The cleanup of these members was done by the router helper process. Since the versions below, that
process is not started with routing schema v3, so nothing removes them.

The patch replaces three modules:

| Module | Change |
| --- | --- |
| `emqx_shared_sub` | Dispatch skips a member whose node is not a running cluster member. This takes effect as soon as the module is loaded. |
| `emqx_router_helper` | Core nodes also look for nodes that are not running but still own shared subscription members, and purge them. |
| `emqx_router_sup` | Starts the router helper with both routing schemas, and adds `ensure_helper/0`, which starts it on a running node. |

The same change ships in a normal release through
[emqx/emqx#20056](https://github.com/emqx/emqx/pull/20056) (6.x) and
[emqx/emqx#20065](https://github.com/emqx/emqx/pull/20065) (5.10).

## Which files to take

| Release line | Affected versions | Erlang/OTP | Files |
| --- | --- | --- | --- |
| 5.10 | 5.10.4, 5.10.5 | 27 | [`5.10/`](5.10) |
| 6.0 | 6.0.3, 6.0.4 | 27 | [`6.0/`](6.0) |
| 6.1 | 6.1.2 to 6.1.5 | 28 | [`6.1/`](6.1) |
| 6.2 | 6.2.1 to 6.2.3 | 28 | [`6.2/`](6.2) |
| 6.3 | 6.3.0 to 6.3.3 | 28 | [`6.3/`](6.3) |

Earlier versions start the router helper with routing schema v3 and do not need this patch. 5.8
and 5.9 have no routing schema v3.

Take all three modules from the directory of your line. **Do not take a 6.1, 6.2 or 6.3 file for a
5.10 or 6.0 node.** Those are compiled with Erlang/OTP 28, and 5.10 and 6.0 run Erlang/OTP 27. The
node rejects the module and keeps the original one without reporting a failure.

## Installing it

Patch every node of the cluster, core and replicant. The dispatch check runs on the node that
dispatches the message, and the purge runs on core nodes.

The patches directory is given in the repository README. For Docker:

```sh
sha256sum -c *.beam.sha256
for m in emqx_shared_sub emqx_router_helper emqx_router_sup; do
    docker cp $m.beam <container>:/opt/emqx/data/patches/$m.beam
done
docker exec -u 0 <container> sh -c 'chown emqx:emqx /opt/emqx/data/patches/*.beam'
```

**Make the files part of your deployment, not only of the running container.** A container
recreated from the image loses them. Bake them into your image, mount them in the patches
directory, or add the copy to your deployment scripts.

Then activate the patch with one of the two ways below, one node at a time.

### Restart the node

A restarted node loads the patched modules at boot. The patched `emqx_router_sup` starts the router
helper by itself. Nothing else is needed.

### Load the modules into the running node

This avoids a restart, and the clients of the node keep their connections:

```sh
docker exec <container> /opt/emqx/bin/emqx eval '[c:l(M) || M <- [emqx_shared_sub, emqx_router_helper, emqx_router_sup]], emqx_router_sup:ensure_helper().'
```

Expect `ok`. The command loads the three modules and starts the router helper when it is not
running. It is safe to run again. An `undef` error for `emqx_router_sup:ensure_helper/0` means that
the patched `emqx_router_sup` was not loaded; check the copy step.

## Verifying that it took effect

```sh
docker exec <container> /opt/emqx/bin/emqx eval '{[binary:encode_hex(M:module_info(md5)) || M <- [emqx_shared_sub, emqx_router_helper, emqx_router_sup]], whereis(emqx_router_helper)}.'
```

Expect a pid for the router helper, and these values, in this order:

| Lines | `emqx_shared_sub` | `emqx_router_helper` | `emqx_router_sup` |
| --- | --- | --- | --- |
| 5.10, 6.0 | `7F348CE26C13A6774D9F15C9C8E2D4DB` | `CBECA42A9061B8BC02F48EE0D958A374` | `321522781030C3FC1841847C0658AC32` |
| 6.1, 6.2, 6.3 | `689ADCE5CCBB22DD4C9944913B2256C0` | `3E839C20892841184D9BA99D9F7B609D` | `939198EA75044AC0E05A4AA79BCF14E2` |

These are the checksums of the compiled code, which `module_info(md5)` reports. They are not the
SHA-256 checksums of the files.

## What to expect after patching

- Dispatch skips the members of a node that is not running as soon as `emqx_shared_sub` is loaded.
- A core node purges the members of a replicant that has been down for 15 minutes. Members found
  by the periodic scan (about every 2 minutes) are purged 15 minutes after they are found.
- The members of a node that left the cluster are purged within about 15 seconds.
- The members of a core node that is down are not purged until the node is removed from the cluster
  with `emqx ctl cluster force-leave <node>`.

To remove the members at once, run this on a core node. It lists the nodes that own shared
subscription members but are not running:

```sh
emqx eval "lists:usort(lists:map(fun({_, _, _, P}) -> node(P) end, ets:tab2list(emqx_shared_subscription))) -- mria:running_nodes()."
```

Then, for each node in the list, remove its members:

```sh
emqx eval "emqx_shared_sub:purge_node('emqx@departed-node')."
```

## Remove the patch before upgrading

Delete the three modules from the patches directory before you upgrade, as the repository README
describes. The fix is planned for 5.10.6, 6.0.5, 6.1.6, 6.2.4 and 6.3.4.

## Reproducing and verifying with Docker

[`reproduce-patch-verify.sh`](reproduce-patch-verify.sh) takes an EMQX version, for example
`./reproduce-patch-verify.sh 6.3.3`. It starts a core node and a replicant node of
`emqx/emqx-enterprise:<version>` with Docker Compose, subscribes one member of a shared
subscription group on each node with `mqttx`, and kills the replicant. On the unpatched core node it
checks that the member of the dead replicant stays and that half of the messages to the group are
lost. It then copies the modules into the core node, loads them with the command above, and checks
that the modules are loaded, that no message is lost, that the router helper marks the replicant
down, and that a purge removes its member.

The script triggers the purge with `emqx_router_helper:schedule_force_purge()` instead of waiting
15 minutes. Set `WAIT_PURGE=1` to wait for the periodic purge.

The script passed on every affected version listed above. On 5.10.5 it also passed with `WAIT_PURGE=1`.

## How these files were built

The source of the three modules is the same in every affected version, and so is the source after
the fix on all lines. The modules were built from the fix commit
[`b74dccaab2`](https://github.com/emqx/emqx/commit/b74dccaab2c4a4f864967065788fb1777de20009),
with the header files of the latest release of each line (5.10.5, 6.0.4, 6.1.5, 6.2.3, 6.3.3), the
Mria and snabbkaffe header files that release ships, and the compiler options of the EMQX release
build:

```sh
erlc +debug_info +compressed +deterministic +warnings_as_errors \
    '+{compile_info,[{emqx_vsn,"261114-stale-shared-routes"}]}' \
    -Dsnk_kind=msg -DEMQX_FLAVOR=official <-DEMQX_ELIXIR on 6.x | -DEMQX_RELEASE_EDITION=ee on 5.10> \
    <module>.erl
```

5.10 and 6.0 were built with Erlang/OTP 27.3.4.2 (compiler 8.6.1.1), and 6.1 to 6.3 with Erlang/OTP
28.4.1 (compiler 9.0.5), the same compiler versions as in the releases. The same procedure, run on
the unpatched source of 5.10.5, 6.0.4 and 6.3.3, gives the same compiled code as the modules in
these releases (`beam_lib:md5/1`).

The patched modules were also built with the header files of every other affected version. Each
build gave the same compiled code as the files here for the same Erlang/OTP major.
