# Kafka no-ack memory leak: EMQX Enterprise 5.8.11 and 6.3.0–6.3.2

This patch stops alias memory growth in Kafka and Confluent producer actions configured with
`parameters.required_acks = none`. It changes only `wolff_producer.beam`.

Choose either procedure, and apply it to every core and replicant node:

- **A. Install before startup:** put the beam in the patches directory before EMQX starts.
- **B. Hot apply:** copy the beam to a running node and load it with `c:l(wolff_producer)`.
  This stops new leaks without restarting the node or freeing memory already leaked.

## Compatibility and checksum

Choose the beam that matches the node. The two beams are not interchangeable.
EMQX 6.3.3 already includes the fix and does not need this patch.

| Patch directory | EMQX Enterprise | Wolff | Erlang/OTP |
| --- | --- | --- | --- |
| [`5.8.11/`](5.8.11) | 5.8.11 | 4.1.10 | 26 |
| [`6.3.0-6.3.2/`](6.3.0-6.3.2) | 6.3.0, 6.3.1, 6.3.2 | 4.2.1 | 28 |

Run commands from this patch directory. Set `PATCH=5.8.11` or `PATCH=6.3.0-6.3.2` to match
the target node, then check the downloaded beam:

```sh
(cd "$PATCH" && sha256sum -c wolff_producer.beam.sha256)
```

On a running node, check its versions and loaded module before applying:

```sh
emqx eval '{emqx_release:version(), application:get_key(wolff, vsn),
  erlang:system_info(otp_release), binary:encode_hex(wolff_producer:module_info(md5))}.'
```

Expect the versions in the selected row above and its original code MD5 below.
Stop if the versions or fingerprint differ. Code MD5 is a module fingerprint, not the file checksum.

| EMQX Enterprise | Module | Original code MD5 | Patched code MD5 |
| --- | --- | --- | --- |
| 5.8.11 | `wolff_producer` | `8EF010927F4294CC959E4CF4FFC6ADE1` | `FDC709163A7318C7EED6A15135CB0740` |
| 6.3.0–6.3.2 | `wolff_producer` | `4B74F08CDFF2BCFCF96318F781926B80` | `F3906B78A437AD5E5D9D4BCBCC59F514` |

For Kubernetes commands below, select the context and set the target namespace, pod, and container:

```sh
kubectl config current-context
NS=emqx
POD=emqx-core-0
CONTAINER=emqx
```

Run node commands through `kubectl -n "$NS" exec "$POD" -c "$CONTAINER" -- /opt/emqx/bin/emqx`.
The official image uses `/opt/emqx/data/patches`. If `node.data_dir` is customized, use its
`patches` subdirectory. Package installations use `/var/lib/emqx/patches`; portable installations
use `<install-dir>/data/patches`.

## A. Install before node startup

Copy the verified beam into the node's patches directory before starting EMQX. For example, with
the official container's data directory mounted at `/opt/emqx/data`:

```sh
mkdir -p /opt/emqx/data/patches
cp "$PATCH/wolff_producer.beam" /opt/emqx/data/patches/
```

Start the node normally, then verify the loaded module as described below.

### Kubernetes

Use an init container to copy the beam from a ConfigMap into the existing shared data volume:

```sh
PATCH_CONFIGMAP="wolff-noack-$(printf '%s' "$PATCH" | tr . -)-v1"
kubectl -n "$NS" create configmap "$PATCH_CONFIGMAP" \
  --from-file="wolff_producer.beam=$PATCH/wolff_producer.beam" \
  --from-file="wolff_producer.beam.sha256=$PATCH/wolff_producer.beam.sha256" \
  --dry-run=client -o yaml > wolff-noack-configmap.yaml
```

Add the ConfigMap and merge the matching fragment into both core and replicant pod templates:
[5.8.11](kubernetes-pod-template.yaml) or [6.3.0–6.3.2](6.3.0-6.3.2/kubernetes-pod-template.yaml).
For 6.3, match the init container image tag to the node's version; the example uses 6.3.2.
These are fragments: preserve the existing containers, volumes, and settings. Match the existing
data volume name (`data` in the example), any `subPath`, and the EMQX user's UID/GID.
The init container and EMQX must share the same data volume.
A PVC or `emptyDir` works; the init container copies the patch whenever a new pod is created.

For Argo CD, commit both changes to the deployment's Git source and sync the ConfigMap before
rolling out pods. For Helm or EMQX Operator, use the installed chart's values or the EMQX custom
resource; direct edits to generated workloads may be reverted. For a manually managed workload,
apply the ConfigMap before updating the pod template:

```sh
kubectl -n "$NS" apply -f wolff-noack-configmap.yaml
```

Before replacing a running pod, pause its incoming traffic and drain action queues and in-flight
requests. Memory buffers do not survive a restart, even with a PVC. With `required_acks = none`,
verify delivery at Kafka when draining matters. Roll out one node at a time while keeping core
availability, then verify each replacement pod and any new replicas.

Do not mount the beam directly onto a file in the data PVC using ConfigMap `subPath`: removing
that mount can expose an empty placeholder beam and prevent EMQX from booting. The init copy
avoids that problem. Copying the beam into an image is also insufficient if a volume hides it.

## B. Hot apply to stop further growth

Copy the verified beam into the running node's patches directory, then load it:

```sh
mkdir -p /opt/emqx/data/patches
cp "$PATCH/wolff_producer.beam" /opt/emqx/data/patches/
emqx eval 'c:l(wolff_producer).'
```

Expect `{module,wolff_producer}`. On Kubernetes:

```sh
kubectl -n "$NS" exec "$POD" -c "$CONTAINER" -- mkdir -p /opt/emqx/data/patches
kubectl cp -c "$CONTAINER" "$PATCH/wolff_producer.beam" \
  "$NS/$POD:/opt/emqx/data/patches/wolff_producer.beam"
kubectl -n "$NS" exec "$POD" -c "$CONTAINER" -- /opt/emqx/bin/emqx eval \
  'c:l(wolff_producer).'
```

No node, action, or producer restart is needed. Existing leaked aliases remain allocated;
this procedure only stops new growth. Verify the loaded module below.

The patches directory must be writable and on the node's code path, as it is in the official
image. For a custom data directory missing from the code path, add it before calling `c:l/1`:
`emqx eval 'code:add_patha("/custom/data/patches").'` (expect `true`).
A file copied into a running pod may disappear when the pod is replaced. Use A (Install before node
startup) in the deployment configuration to keep replacement pods patched.

## Verify the loaded module

After either procedure, run on every node:

```sh
emqx eval '{binary:encode_hex(wolff_producer:module_info(md5)), code:which(wolff_producer)}.'
```

For Kubernetes:

```sh
kubectl -n "$NS" exec "$POD" -c "$CONTAINER" -- /opt/emqx/bin/emqx eval \
  '{binary:encode_hex(wolff_producer:module_info(md5)), code:which(wolff_producer)}.'
```

Expect the patched code MD5 for the selected release and a path ending in
`patches/wolff_producer.beam`. Pod readiness or `{module,wolff_producer}` alone does not prove the
patched beam was loaded.

## Remove before upgrading

Remove `wolff_producer.beam` from the patches directory and remove any deployment step that
copies it there before starting an upgraded node. Otherwise it overrides the upgraded library.
Preserve other patch files. To roll back, remove this override and restart the node
using the same draining procedure; the original code MD5 should return.

For the Kubernetes init-container installation, temporarily replace the init container's `args`
with `["rm -f /emqx-data/patches/wolff_producer.beam"]` and roll out before upgrading EMQX.
Keep that cleanup step until every reusable PVC, including scaled-down replicas, has been cleaned.
Then remove the patch init container and its volume, and delete the ConfigMap after no pod
template references it.

## Source and validation

Each beam changes only the alias cleanup in its matching Wolff version:

- 5.8.11: [Wolff 4.1.10](https://github.com/kafka4beam/wolff/blob/4bab2e0d8506e8c918b43e719971b84507cf60d5/src/wolff_producer.erl#L547-L550)
  with [source.patch](5.8.11/source.patch), compiled using the official 5.8.11 image's OTP compiler.
- 6.3.0–6.3.2: [Wolff 4.2.1](https://github.com/kafka4beam/wolff/blob/4feffa6534a960377507fb2dc840db07548b2533/src/wolff_producer.erl#L720-L723)
  with [source.patch](6.3.0-6.3.2/source.patch), compiled using the official 6.3.2 image's OTP 28
  compiler and Kafka protocol 4.3.2 headers. Compiling the unchanged source reproduced the original
  module fingerprint in all three official images. The patched fingerprint matches the fixed
  producer in 6.3.3.

Build image digests:

- `emqx/emqx-enterprise:5.8.11`:
  `sha256:9cbe95c05b2790293cccbe416ef03001beb13c8089ff5e1059dbdcb9bd4477d6`.
- `emqx/emqx-enterprise:6.3.2`:
  `sha256:135116400e11b25224350b2e55c874f4e224d357b593fb554ca1b1f398c631ac`.

The 100,000-request real-Kafka allocator regression failed before the fix and passed with each
beam: zero live aliases before and after, zero unscanned bytes, and Kafka's end offset verified.
The 6.3 test was run separately with each of the 6.3.0, 6.3.1, and 6.3.2 images. Each also passed
hot apply with `c:l/1`, loading at startup, and removal followed by startup with the original module.

Earlier 5.8.11 Kubernetes testing covered PVC pod replacement, fresh-PVC scale-up, `emptyDir`
recreation, and removal before startup. Chart- and Operator-specific configuration must be adapted
to the installed version.

The permanent fixes are in [wolff#125](https://github.com/kafka4beam/wolff/pull/125),
[wolff#124](https://github.com/kafka4beam/wolff/pull/124),
[emqx#19994](https://github.com/emqx/emqx/pull/19994), and
[emqx#19992](https://github.com/emqx/emqx/pull/19992).
