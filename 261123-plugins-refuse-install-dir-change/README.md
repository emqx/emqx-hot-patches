# Fixed plugin install directory: EMQX Enterprise 5.8.6 to 6.3.3

With this patch, `plugins.install_dir` keeps the value that the node started with. A configuration
update that sets another directory fails, with this reason in the error:

```
install_dir_cannot_be_changed_at_runtime
```

This applies to every runtime update of the `plugins` configuration root: `PUT /api/v5/configs` in
`merge` and `replace` mode, `emqx ctl conf load`, and the other update paths. An update that
carries the directory in use works as before. For an update without `install_dir`, see
[Behaviour after the patch](#behaviour-after-the-patch). Plugin install, start, stop, enable and
disable do not change.

To change the directory after you apply the patch, set it in `etc/emqx.conf` or with the
environment variable `EMQX_PLUGINS__INSTALL_DIR`, then restart the node.

The patch replaces one module, `emqx_plugins.beam`.

The same change ships in normal releases through
[emqx/emqx#20192](https://github.com/emqx/emqx/pull/20192) (5.8, 5.9, 5.10) and
[emqx/emqx#20191](https://github.com/emqx/emqx/pull/20191) (6.x).

There is no file for 5.8.0 to 5.8.5. Upgrade those nodes to a later release.

## Compatibility and checksum

Take the file for the exact version of the node.

| Directory | EMQX Enterprise | Erlang/OTP | Original code MD5 | Patched code MD5 |
| --- | --- | --- | --- | --- |
| [`5.8.6-5.8.10/`](5.8.6-5.8.10) | 5.8.6 to 5.8.10 | 26 | `CD72487F7F9AF85FEFA0B7ECF85A024D` | `B6341EC967E257251A240EEFD5136A12` |
| [`5.8.11/`](5.8.11) | 5.8.11 | 26 | `EE9591556207464D6560DF95F15377A2` | `AA56293886F64B4BA81D9C49030BCAD9` |
| [`5.9.0/`](5.9.0) | 5.9.0 | 27 | `D883E4EBACAE4A83FB88FF65D6B66953` | `BF25FDEB9F550F1D65A88C87CD656835` |
| [`5.9.1-5.10.3/`](5.9.1-5.10.3) | 5.9.1, 5.9.2, 5.10.0 to 5.10.3 | 27 | `0B07A7DF4A4873A0D8E76C62683E7A21` | `9D93A0862E5F6AFC25977504E4AE97AD` |
| [`5.9.3-5.10.4/`](5.9.3-5.10.4) | 5.9.3, 5.10.4 | 27 | `C4889C427CAF2364BDF948B69C000E99` | `BAD27298EFD2C6A050A078B603F6B951` |
| [`5.10.5/`](5.10.5) | 5.10.5 | 27 | `5C3AD50A4D521DC86227D077101E10B1` | `775C885A155665AF1347717220FA0304` |
| [`6.0.0-6.0.2/`](6.0.0-6.0.2) | 6.0.0 to 6.0.2 | 27 | `0B07A7DF4A4873A0D8E76C62683E7A21` | `6CBA5E8832A220345D11DB399FB82CBB` |
| [`6.0.3/`](6.0.3) | 6.0.3 | 27 | `6B033CB0F080EC15D6A27B7FFEBE3453` | `39F2DE682977F435EA654FD1939D6F84` |
| [`6.0.4/`](6.0.4) | 6.0.4 | 27 | `6E5EE80E495F7CEF1EE85F3B52967276` | `6F0EB0519696C943A71514719791AE70` |
| [`6.1.0/`](6.1.0) | 6.1.0 | 28 | `C3561E2126B6DF533FCCEB9D0ED0D6C2` | `361500F43243C3A33560D0BD9B64F100` |
| [`6.1.1/`](6.1.1) | 6.1.1 | 28 | `4958B5A861C1D44CF578762725E6865B` | `CC32D5227221C209C5DDF858396DF8D5` |
| [`6.1.2-6.2.2/`](6.1.2-6.2.2) | 6.1.2, 6.2.1, 6.2.2 | 28 | `34085C4FF26D8BB8D07D791E41A5312F` | `6709FACC9B1766219622055B4D339914` |
| [`6.1.3/`](6.1.3) | 6.1.3 | 28 | `72D33926A571C4985CA4DDA7C205A57C` | `EED82869E01C0C10DD6B9F1C26114914` |
| [`6.1.4-6.2.3/`](6.1.4-6.2.3) | 6.1.4, 6.2.3 | 28 | `011E8292D11C9717B8A41ABBA7D3CE08` | `743F13E6ABBFC36AFCEDB2759FDC788C` |
| [`6.1.5/`](6.1.5) | 6.1.5 | 28 | `CEB69B64BF35954218F58327F29A8078` | `F878768DFEF9EA219CE4629FCD571B05` |
| [`6.2.0/`](6.2.0) | 6.2.0 | 28 | `053CB53F37829ACABE4305CF149BB50E` | `6E8B45255BDF1B91DEFD374F509D5495` |
| [`6.3.0-6.3.2/`](6.3.0-6.3.2) | 6.3.0 to 6.3.2 | 28 | `B1CC0DE462C716C68FC2F5FA72A3F933` | `185B6498E11687AA4820B93FECCE9780` |
| [`6.3.3/`](6.3.3) | 6.3.3 | 28 | `1848A73814A6D2936866928DC5CB2C6D` | `BA0A6310121D341904DE41DEA4B186A2` |

Code MD5 is a module fingerprint (`emqx_plugins:module_info(md5)`), not the file checksum.

The module of a release contains all the other plugin changes of that release. A file from another
row would put the plugin code of another release on the node. Use each file only on the releases of
its row, even when two rows have the same original code MD5 (`5.9.1-5.10.3/` and `6.0.0-6.0.2/`).

Run the commands below from this patch directory. Set `PATCH` to the directory of your version, for
example `PATCH=6.3.3`. Check the downloaded file:

```sh
(cd "$PATCH" && sha256sum -c emqx_plugins.beam.sha256)
```

## Before you apply the patch

On every node, check the version, the loaded module and the plugin install directory in use:

```sh
emqx eval '{emqx_release:version(), erlang:system_info(otp_release),
  binary:encode_hex(emqx_plugins:module_info(md5)), emqx_config:get([plugins, install_dir])}.'
```

Expect a release and Erlang/OTP major from the table, and the original code MD5 of that row.
**Stop if the fingerprint differs.**

Check that the directory is the one that you configured. The default is `"plugins"`, relative to
the EMQX installation directory. **After the patch, you cannot change the directory at runtime.**
If the directory is not the expected one, correct it before you apply the patch, on every node:

```sh
printf 'plugins { install_dir = "plugins" }\n' > /tmp/plugins-dir.hocon   # your directory
emqx ctl conf load /tmp/plugins-dir.hocon
```

A directory set at runtime is kept in the cluster configuration and stays in use after a restart,
unless `etc/emqx.conf` or `EMQX_PLUGINS__INSTALL_DIR` sets it. Both of these replace it at the next
start.

**Apply the patch on every node of the cluster.** A node without the patch still accepts a
directory change, and it sends the change to the other nodes. A patched node keeps its own
directory and logs a warning with `msg: plugins_install_dir_change_ignored`. It still applies the
other parts of that update, and all later configuration updates.

## A. Install before node startup

Copy the verified file into the patches directory (see the [repository README](../README.md)), then
start or restart the node:

```sh
cp "$PATCH/emqx_plugins.beam" /opt/emqx/data/patches/
```

The node loads the patched module at boot.

For Kubernetes, copy the file from a ConfigMap into the data volume with an init container, as
described for the [Kafka no-ack patch](../261117-kafka-noack-alias/README.md#kubernetes). Use
`emqx_plugins.beam` in place of `wolff_producer.beam`.

## B. Hot apply

Copy the verified file into the running node's patches directory, then load it:

```sh
cp "$PATCH/emqx_plugins.beam" /opt/emqx/data/patches/
emqx eval 'case code:soft_purge(emqx_plugins) of true -> c:l(emqx_plugins); false -> old_code_in_use end.'
```

Expect `{module,emqx_plugins}`. The next configuration update uses the patched module. No restart is
needed, and running plugins are not affected.

`old_code_in_use` means that a process still runs code from an earlier load of the module. Nothing
was changed. This can occur when you run the command a second time. Check the loaded module as
described below; if it is not the patched one, report the result to EMQX support.

A file copied into a running container or pod is lost when the container is recreated. Use A in
the deployment configuration as well, so that replacement nodes stay patched.

## Verify the loaded module

After either procedure, on every node:

```sh
emqx eval '{binary:encode_hex(emqx_plugins:module_info(md5)), code:which(emqx_plugins)}.'
```

Expect the patched code MD5 of your row, and a path that ends in `patches/emqx_plugins.beam`.

## Behaviour after the patch

- The directory is compared as text. `"plugins/"` and `"./plugins"` are other values than
  `"plugins"`. Use the value exactly as the check above prints it.
- On 5.8, 5.9, 5.10 and 6.0.0 to 6.0.3, `PUT /api/v5/configs` and `emqx ctl conf load` fill in the
  default of each missing key before the update. A `plugins` block without `install_dir` therefore
  sets the default directory. On a node that uses another directory, it now fails. Include
  `install_dir` with the value in use, or leave the `plugins` block out.
- On every version, `mode=replace` with a `plugins` block without `install_dir` sets the default
  directory, with the same result.

## Remove before upgrading

Remove the module file from the patches directory, and any deployment step that copies it there,
before you start an upgraded node. Otherwise it overrides the module of the new release, and a
file built for an older Erlang/OTP can fail to load.

```sh
rm /opt/emqx/data/patches/emqx_plugins.beam
```

## Source and validation

Each file was compiled from the module source at the release tag in the table below, with
`source.patch` of its directory applied. The compile options were those of the release:
`debug_info`, `compressed` and `deterministic`, and the same defines. Each patch adds the same
check as the matching emqx/emqx pull request: [#20192](https://github.com/emqx/emqx/pull/20192) for
the 5.x directories, [#20191](https://github.com/emqx/emqx/pull/20191) for the 6.x directories.

| Directory | Source tag | Erlang/OTP used to compile |
| --- | --- | --- |
| `5.8.6-5.8.10/` | `e5.8.10` | 26.2.5.14-1 |
| `5.8.11/` | `e5.8.11` | 26.2.5.14-1 |
| `5.9.0/` | `e5.9.0` | 27.3.4.2-8 |
| `5.9.1-5.10.3/` | `e5.10.3` | 27.3.4.2-8 |
| `5.9.3-5.10.4/` | `e5.10.4` | 27.3.4.2-8 |
| `5.10.5/` | `e5.10.5` | 27.3.4.2-8 |
| `6.0.0-6.0.2/` | `6.0.2` | 27.3.4.2-8 |
| `6.0.3/` | `6.0.3` | 27.3.4.2-8 |
| `6.0.4/` | `6.0.4` | 27.3.4.2-8 |
| `6.1.0/` | `6.1.0` | 28.2, the compiler of the official 6.1.0 image |
| `6.1.1/` | `6.1.1` | 28.2, the compiler of the official 6.1.1 image |
| `6.1.2-6.2.2/` | `6.2.2` | 28.4.1-10 |
| `6.1.3/` | `6.1.3` | 28.4.1-10 |
| `6.1.4-6.2.3/` | `6.2.3` | 28.4.1-10 |
| `6.1.5/` | `6.1.5` | 28.4.1-10 |
| `6.2.0/` | `6.2.0` | 28.4.1-10 |
| `6.3.0-6.3.2/` | `6.3.2` | 28.4.1-10 |
| `6.3.3/` | `6.3.3` | 28.4.1-10 |

Validation:

- A build of the unpatched source in the same way reproduces the original code MD5 of the
  official images.
- The original code MD5 in the compatibility table was read from the official image of every
  release that the table lists.
- Each file was tested on the oldest and the newest official image of its directory, with the
  commands of this README. Results below. "Refused" means that `PUT /api/v5/configs` in `merge` and
  `replace` mode and `emqx ctl conf load` with another directory failed with
  `install_dir_cannot_be_changed_at_runtime`, and the directory in use did not change. "Same
  value accepted" means that both modes accepted the directory in use. The plugin test installed the
  demo plugin package of the EMQX test suites after `emqx ctl plugins allow`, then started,
  stopped, enabled, disabled and uninstalled it through the HTTP API and `emqx ctl plugins`.

| Image | Directory | Original code MD5 matched | Before the patch: other directory accepted | Hot apply | After hot apply: refused | After hot apply: same value accepted | After hot apply: plugin install, start, stop, enable, disable, uninstall | After restart: module loaded from `patches`, same three results | New errors or critical entries in the node log |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `emqx/emqx-enterprise:5.8.6` | `5.8.6-5.8.10/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:5.8.10` | `5.8.6-5.8.10/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:5.8.11` | `5.8.11/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:5.9.0` | `5.9.0/` | yes | yes | yes | yes | yes | yes | yes | one, also without the patch (see below) |
| `emqx/emqx-enterprise:5.9.1` | `5.9.1-5.10.3/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:5.10.3` | `5.9.1-5.10.3/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.0.0` | `6.0.0-6.0.2/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.0.2` | `6.0.0-6.0.2/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:5.9.3` | `5.9.3-5.10.4/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:5.10.4` | `5.9.3-5.10.4/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:5.10.5` | `5.10.5/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.0.3` | `6.0.3/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.0.4` | `6.0.4/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.1.0` | `6.1.0/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.1.1` | `6.1.1/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.1.2` | `6.1.2-6.2.2/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.2.2` | `6.1.2-6.2.2/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.1.3` | `6.1.3/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.1.4` | `6.1.4-6.2.3/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.2.3` | `6.1.4-6.2.3/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.1.5` | `6.1.5/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.2.0` | `6.2.0/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.3.0` | `6.3.0-6.3.2/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.3.2` | `6.3.0-6.3.2/` | yes | yes | yes | yes | yes | yes | yes | none |
| `emqx/emqx-enterprise:6.3.3` | `6.3.3/` | yes | yes | yes | yes | yes | yes | yes | none |

One run per image. The only log entries were the shutdown notice of the restart, and on 5.9.0 a
crash of `emqx_telemetry` on the demo plugin information, which the same test without the patch
also shows.

- Two-node clusters of 5.8.11, 6.0.4 and 6.3.3, with the patch on one node only: a directory change
  started on the node without the patch was applied there. The patched node kept its directory,
  logged `plugins_install_dir_change_ignored`, and applied the later configuration updates from
  both nodes. The same change started on the patched node failed.
- A node started with `EMQX_PLUGINS__INSTALL_DIR` set (5.8.11, 6.0.3, 6.0.4, 6.3.3) reported that
  directory as in use, and the patch kept it.
