# EMQX hot patches

Compiled Erlang modules that EMQ publishes so a running EMQX node can be corrected without
upgrading it.

Each directory is one patch, named `YYMMDD-<subject>`. Read the `README.md` inside it: it states
which EMQX versions the patch applies to, and how to verify that it took effect.

A hot patch is a stop-gap. The same correction also ships in a normal release, and upgrading is the
supported path.

## Applying a patch

EMQX puts its patches directory at the front of the code path, so a module there takes precedence
over the copy inside the release.

| Deployment | Patches directory |
| --- | --- |
| Docker | `/opt/emqx/data/patches` |
| `deb` / `rpm`, started through systemd | `/var/lib/emqx/patches` |
| Portable `tar.gz` | `<install-dir>/data/patches` |

Verify the download, copy it in, then load it on the running node:

```sh
sha256sum -c <module>.beam.sha256
cp <module>.beam <patches-dir>/
emqx eval 'c:l(<module>).'
```

Expect `{module,<module>}`. `c:l/1` loads the module on the node it runs against only, so repeat
this on every node of the cluster.

A patch copied into a running container is lost when the container is recreated. Add it to your
image or deployment as well.

## Apply a patch only to the versions it names

Each patch README lists the EMQX release versions it was built and verified against. Do not use it
outside that range.

A module compiled for one Erlang/OTP major version loads on that version and on newer ones, but not
on older ones. An older node rejects it with
`Error loading module <module>: corrupt atom table` and keeps the original module, so the node
reports no failure while remaining unpatched.

## Remove a patch before upgrading

**Delete the module from the patches directory before you upgrade EMQX, then restart the node.**

The patches directory wins over the release, and nothing in an upgrade clears it. A module left
behind keeps overriding the one in the new release, so the upgrade silently does not take effect
for that module — and because the patch is older than the release, it can reintroduce exactly what
the upgrade fixed. If the new release moves to a newer Erlang/OTP major, the stale module can also
fail to load and take the components that depend on it down with it.

```sh
rm <patches-dir>/<module>.beam
```

After upgrading, confirm the new release's own module is in use with the verification command in
the patch README.

## Patches

| Patch | Subject |
| --- | --- |
| [`261023-eMudhra`](261023-eMudhra) | Removes a withdrawn eMudhra root certificate from the CA trust store bundled in the EMQX release. |
