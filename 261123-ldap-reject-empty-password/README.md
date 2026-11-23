# LDAP bind with an empty password: EMQX Enterprise 5.8 to 6.3

With this patch, EMQX refuses an empty password before an LDAP bind. A login with an empty
password gets the wrong-password result, and EMQX sends no bind request to the LDAP server. This
applies to:

- Dashboard LDAP single sign-on.
- The MQTT LDAP authenticator with the `bind` method. On 5.10 and later, it also no longer logs an
  `ldap_bind_failed` error for an empty password.

Logins with a non-empty password do not change.

The patch replaces one module: `emqx_ldap_bind_worker.beam` on 5.8 and 5.9, and `emqx_ldap.beam` on
5.10 and later.

The same change ships in normal releases through
[emqx/emqx#20188](https://github.com/emqx/emqx/pull/20188) (5.8, 5.9),
[emqx/emqx#20189](https://github.com/emqx/emqx/pull/20189) (5.10) and
[emqx/emqx#20190](https://github.com/emqx/emqx/pull/20190) (6.x).

## Compatibility and checksum

Take the file for the exact version of the node.

| Directory | EMQX Enterprise | Erlang/OTP | Module | Original code MD5 | Patched code MD5 |
| --- | --- | --- | --- | --- | --- |
| [`5.8/`](5.8) | 5.8.0 to 5.8.3 | 26 | `emqx_ldap_bind_worker` | `0CF6FCCBB8419B217EE65CFC132E183D` | `CCD8294DCA1EBB7DC20373B564AAAE77` |
| [`5.8/`](5.8) | 5.8.4 to 5.8.11 | 26 | `emqx_ldap_bind_worker` | `4824041224F676D36824291078807CED` | `CCD8294DCA1EBB7DC20373B564AAAE77` |
| [`5.9/`](5.9) | 5.9.0 to 5.9.3 | 27 | `emqx_ldap_bind_worker` | `95B9CA346B79EE4B320E9920A4BC52A6` | `A42D53B15370E1DE89F0D74A71904956` |
| [`5.10.0/`](5.10.0) | 5.10.0 | 27 | `emqx_ldap` | `04DAD218AA2F677D2D658999F2732331` | `93FCF94E181CC5C6256B2A4580448A58` |
| [`5.10.1-5.10.5/`](5.10.1-5.10.5) | 5.10.1 to 5.10.5 | 27 | `emqx_ldap` | `B03BD734EE0B02432144EDA597571196` | `DBCAF90F91406F622C7E0CA8F21F814A` |
| [`6.0/`](6.0) | 6.0.0 to 6.0.4 | 27 | `emqx_ldap` | `B03BD734EE0B02432144EDA597571196` | `DBCAF90F91406F622C7E0CA8F21F814A` |
| [`6.1/`](6.1) | 6.1.0 to 6.1.5 | 28 | `emqx_ldap` | `6335E71B8F315AD6C229A975CE6422A5` | `7D6BE7256EA3F26C10D5B016F3511437` |
| [`6.2/`](6.2) | 6.2.0 to 6.2.3 | 28 | `emqx_ldap` | `642BF52A8F6B1FF0C74225299D503FF4` | `2BBA1455E744AE1A9749924EE999440C` |
| [`6.3/`](6.3) | 6.3.0 to 6.3.3 | 28 | `emqx_ldap` | `642BF52A8F6B1FF0C74225299D503FF4` | `2BBA1455E744AE1A9749924EE999440C` |

Code MD5 is a module fingerprint (`Module:module_info(md5)`), not the file checksum. Directories
with the same patched code MD5 hold the same compiled code.

Use each file only on the releases of its row. For example, the `5.10.1-5.10.5/` file calls a
function that 5.10.0 does not have, and the `5.10.0/` file would put the LDAP health check of 5.10.0
back on a later release.

Run the commands below from this patch directory. Set `PATCH` to the directory of your version
and `MOD` to its module, for example `PATCH=6.3 MOD=emqx_ldap`, or
`PATCH=5.8 MOD=emqx_ldap_bind_worker`. Check the downloaded file:

```sh
(cd "$PATCH" && sha256sum -c "$MOD.beam.sha256")
```

On the running node, check the version and the loaded module before you apply the patch:

```sh
emqx eval '{emqx_release:version(), erlang:system_info(otp_release),
  binary:encode_hex(emqx_ldap:module_info(md5))}.'
```

On 5.8 and 5.9, use `emqx_ldap_bind_worker` in place of `emqx_ldap`.

Expect a release and Erlang/OTP major from the table, and the original code MD5 of that row.
**Stop if the fingerprint differs.**

## A. Install before node startup

Copy the verified file into the patches directory (see the [repository README](../README.md)), then
start or restart the node:

```sh
cp "$PATCH/$MOD.beam" /opt/emqx/data/patches/
```

The node loads the patched module at boot.

For Kubernetes, copy the file from a ConfigMap into the data volume with an init container, as
described for the [Kafka no-ack patch](../261117-kafka-noack-alias/README.md#kubernetes). Use the
module file of your directory in place of `wolff_producer.beam`.

## B. Hot apply

Copy the verified file into the running node's patches directory, then load it:

```sh
cp "$PATCH/$MOD.beam" /opt/emqx/data/patches/
emqx eval 'case code:soft_purge(emqx_ldap) of true -> c:l(emqx_ldap); false -> old_code_in_use end.'
```

On 5.8 and 5.9, use `emqx_ldap_bind_worker` in place of `emqx_ldap`, in all three places.

Expect `{module,emqx_ldap}` (or `{module,emqx_ldap_bind_worker}`). The next login uses the patched
module. No restart of the node, of the LDAP connections, of an authenticator or of the single
sign-on backend is needed.

`old_code_in_use` means that a process still runs code from an earlier load of the module. Nothing
was changed. This can occur when you run the command a second time. Check the loaded module as
described below; if it is not the patched one, report the result to EMQX support. Do not use
`code:purge/1` for this: it kills the LDAP connection processes.

A file copied into a running container or pod is lost when the container is recreated. Use A in
the deployment configuration as well, so that replacement nodes stay patched.

## Verify the loaded module

After either procedure, on every node:

```sh
emqx eval '{binary:encode_hex(emqx_ldap:module_info(md5)), code:which(emqx_ldap)}.'
```

On 5.8 and 5.9, use `emqx_ldap_bind_worker` in place of `emqx_ldap`.

Expect the patched code MD5 of your row, and a path that ends in `patches/emqx_ldap.beam` (or
`patches/emqx_ldap_bind_worker.beam`).

## Remove before upgrading

Remove the module file from the patches directory, and any deployment step that copies it there,
before you start an upgraded node. Otherwise it overrides the module of the new release, and a
file built for an older Erlang/OTP can fail to load.

```sh
rm /opt/emqx/data/patches/emqx_ldap.beam /opt/emqx/data/patches/emqx_ldap_bind_worker.beam
```

## Source and validation

Each file was compiled from the module source at the release tag in the table below, with
[`source.patch`](6.3/source.patch) of its directory applied. The compile options were those of the
release: `debug_info`, `compressed` and `deterministic`, and the same defines. Each patch adds the
same check as the matching emqx/emqx pull request.

| Directory | Source tag | Erlang/OTP used to compile |
| --- | --- | --- |
| `5.8/` | `e5.8.11` | 26.2.5.14-1 |
| `5.9/` | `e5.9.3` | 27.3.4.2-8 |
| `5.10.0/` | `e5.10.0` | 27.3.4.2-8 |
| `5.10.1-5.10.5/` | `e5.10.5` | 27.3.4.2-8 |
| `6.0/` | `6.0.4` | 27.3.4.2-8 |
| `6.1/` | `6.1.5` | 28.4.1-10 |
| `6.2/` | `6.2.3` | 28.4.1-10 |
| `6.3/` | `6.3.3` | 28.4.1-10 |

Validation:

- A build of the unpatched source in the same way reproduces the original code MD5 of the
  official images.
- The original code MD5 in the compatibility table was read from the official image of every
  release that the table lists.
- On 5.8.0 to 5.8.3, the module differs from 5.8.4 only in the source line numbers that it
  writes into log metadata. The `5.8/` file is therefore also correct for those releases.
- Each file was tested with the commands of this README on the oldest and the newest official
  image of its directory, with an LDAP server that has the directory users of the EMQX test
  suites. Before the hot apply, the node had Dashboard LDAP single sign-on and an MQTT LDAP
  authenticator with the `bind` method configured, with open LDAP connections. Results after the hot
  apply:

| Image | Directory | Hot apply | Dashboard LDAP login, empty password (HTTP status) | Dashboard LDAP login, correct password (HTTP status) | MQTT LDAP bind authentication, empty password | MQTT LDAP bind authentication, correct password | After restart: module loaded from `patches`, both logins as after the hot apply |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `emqx/emqx-enterprise:5.8.0` | `5.8/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:5.8.11` | `5.8/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:5.9.0` | `5.9/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:5.9.3` | `5.9/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:5.10.0` | `5.10.0/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:5.10.1` | `5.10.1-5.10.5/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:5.10.5` | `5.10.1-5.10.5/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:6.0.4` | `6.0/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:6.1.0` | `6.1/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:6.1.5` | `6.1/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:6.2.3` | `6.2/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:6.3.0` | `6.3/` | ok | 401 | 200 | rejected | accepted | yes |
| `emqx/emqx-enterprise:6.3.3` | `6.3/` | ok | 401 | 200 | rejected | accepted | yes |

One run per image. No unexpected error in the node log. The original code MD5 matched before the
patch on every image.
