# EMQX hot patches

Compiled Erlang modules that EMQ publishes so that a running EMQX node can be corrected without
upgrading it.

Each directory is one patch, named `YYMMDD-<subject>`. Read the `README.md` inside the directory
you need: it states which releases the patch applies to, how to install it, and how to verify that
it took effect.

A patch here is a stop-gap. The same correction also ships in a normal release, and upgrading to
that release is the supported path. Use a patch when you cannot upgrade yet.

## How a patch is applied

EMQX puts its patches directory at the front of the code path, so a module placed there takes
precedence over the copy inside the release. The directory depends on how EMQX was installed:

| Deployment | Patches directory |
| --- | --- |
| Docker | `/opt/emqx/data/patches` |
| `deb` / `rpm`, started through systemd | `/var/lib/emqx/patches` |
| Portable `tar.gz` | `<install-dir>/data/patches` |

Copy the module there, then load it on the running node:

```sh
emqx eval 'c:l(<module>).'
```

The command returns `{module,<module>}` on success.

Two things to keep in mind. `c:l/1` loads the module on the node it runs against only, so repeat it
on every node of the cluster. And a patch placed in a container at run time is lost when the
container is recreated, so add it to your image or your deployment as well.

## Verifying what you downloaded

Every module ships with a `certifi.beam.sha256`-style checksum file next to it:

```sh
sha256sum -c <module>.beam.sha256
```

A BEAM file is tied to the Erlang/OTP major version it was compiled with. It loads on that version
and on newer ones, but not on older ones: an older node rejects it with
`Error loading module <module>: corrupt atom table` and keeps the original, so the node reports no
failure while remaining unpatched. Take the file for your release line, not for another.

## Patches

| Patch | Subject |
| --- | --- |
| [`261023-eMudhra`](261023-eMudhra) | Removes a withdrawn eMudhra root certificate from the CA trust store bundled in the EMQX release. |
