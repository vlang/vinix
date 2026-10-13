# Application SDK 1

The public boundary is format-1 repositories/manifests, `vinix-package` commands
and versioned JSON, and the isolated launch contract below. Publishers do not
link desktop internals or write the database. Breaking changes require a new
`format`/`sdk` value; unknown versions are rejected. This does not freeze kernel,
Apple or internal compositor interfaces.

## Build and publish

```sh
v -o /tmp/vinix-package tools/packages/main.v
/tmp/vinix-package keygen /secure/publisher.seed
/tmp/vinix-package pack manifest.json /build/payload /build/new-repository
/tmp/vinix-package publish-release /build/new-repository company /secure/publisher.seed 1 2000000000 /srv/releases/company-1
```

`keygen` prints the lowercase-hex public key and creates a mode-0600, 32-byte
signing seed encoded as hex. Keep it outside repositories/deployment images.
Distribute the public key through an authenticated channel. Upload objects first,
then switch the web server to the complete new repository directory. Never change
content at an existing hash. Increase sequence for every index change, including
expiry. Administrators explicitly enroll, replace or revoke publisher keys using
the repository commands below; publishers cannot authorize their own keys.

Publisher and consumer use the [pinned V signing dependency](signing/README.md),
with its MIT license, source blob/digest ledger and reproducible V regeneration
tool. It preserves SDK-1 Ed25519 bytes and removes a compiler-sensitive variadic
point-initialization check. Upgrades require renewed source, reference-vector,
sanitizer and both-target qualification; compiler updates do not silently replace
this signing implementation. Standard-library hashing/entropy dependencies are
still part of the qualified toolchain closure.

`publish-release REPOSITORY_DIR ID SEED SEQUENCE EXPIRES NEW_DIRECTORY` builds a
complete consumer release without changing workspace indexes. It returns one
format-1 JSON object with `repository`, `public_key`, `sequence`, `expires`,
`index_sha256`, absolute `directory`, `package_count` and unique `object_count`.
The output contains only `index.json`, `index.sig` and `objects/`; publisher
manifests, state, locks and seeds are excluded. The seed must be an ordinary
private file owned by the publisher. Workspaces and destination ancestors must
be controlled by that administrator; sticky shared directories are supported.
Do not modify the workspace or seed while publishing.
An object whose digest matches the signing seed file is refused, catching an
accidentally packed seed; keep all credentials out of payload sources as well.

Every advertised version must have a complete dependency closure within this
workspace for its declared host architecture. An `all` data package must resolve
on both hosts. Runtime entrypoints and version bounds use the consumer solver;
a newer working version cannot hide an older broken version. The complete check
has the resolver's 100,000-step budget. This checks structural installability;
it does not execute apps, qualify foreign APIs, accept consumer licenses or
authorize firmware use. Proprietary/firmware declarations stay in signed metadata.

The command verifies and deduplicates objects, checks destination space with a
64 MiB reserve, creates a private `.vinix-release-*` sibling tree, verifies copied
bytes and flushes the tree. Exclusive atomic rename publishes the complete new
directory and refuses every existing destination, including one created during
the export. Output objects/metadata are 0644 and directories 0755. Filesystems
without exclusive atomic rename support fail closed. A post-publication flush
failure reports that the complete directory exists but its durability is uncertain.
Upload this complete release to a new remote directory, then switch the server's
release route. Serving a mutable workspace can expose a torn metadata pair.

Keep `.publisher/history.json` with the workspace and back it up. A private
publisher lock serializes release commands. Before publication, durable history
reserves the index sequence/digest for the repository ID and public key. Lower
sequences or changed metadata at the same sequence are refused. After a failure
or abrupt termination, retry the same seed, metadata, sequence and expiry into
the same absent destination or another new directory, or choose a higher sequence.
Never restore an older history to reuse a signed sequence. Normal failures remove
staging; an abrupt stop can leave a hidden tree that the administrator may remove
after the publisher process has stopped. Retry builds from the workspace, never
from abandoned staging. Keep client enrollment/replay checks in place as well.

`publish REPOSITORY_DIR ID SEED SEQUENCE EXPIRES` remains the workspace metadata
command for development and existing callers. It replaces the signature and
index separately and does not maintain publisher release history or check a
self-contained dependency closure. Use `publish-release` for distribution.

`pack` inventories ordinary payload files with paths, lengths, SHA-256 and
executable bits, and copies verified content into the repository. It replaces the
template's `files`. Symlinks/devices/sockets/path collisions are rejected. Include
upstream copyright/license documents. Packages, paths, dependencies, permissions
and MIME types are sorted, and JSON field order is fixed. Identical payload bytes,
sequence, expiry and seed produce identical index bytes and Ed25519 signature.
Binary build reproducibility remains the compiler/upstream build's responsibility.

### Import a prepared guest root

`pack-root recipe.json /build/guest-root /build/new-repository` imports an explicit
selection from a prepared upstream root. Verify upstream signatures and obtain
redistribution permission before preparing that root. This command does not
authenticate upstream packages, solve their dependencies, run install scripts or
infer licenses. Record the complete app/runtime dependency closure in the Vinix
manifest and include the upstream copyright/license files among the selectors.

```json
{
  "format": 1,
  "manifest": {
    "id": "org.example.musl-runtime",
    "version": "1.0.0",
    "architecture": "aarch64",
    "name": "Example Linux runtime",
    "license": "GPL-2.0-or-later AND MIT",
    "kind": "runtime"
  },
  "entries": [
    {"source": "bin/vinix-linux-runner", "path": "bin/vinix-linux-runner"},
    {"source": "lib", "path": "lib"},
    {"source": "usr/lib", "path": "usr/lib"},
    {"source": "licenses", "path": "licenses"}
  ]
}
```

Both selector paths are relative; destinations cannot overlap. The input root
must be an ordinary directory and remain unchanged during import. File and
directory aliases are materialized into regular files in a private workspace;
absolute links resolve inside the captured **guest** root, never the publisher's
host filesystem. Relative parents are resolved after intermediate links and
cannot traverse above that root. Broken links, cycles, more than 40 link hops,
special files and oversized payloads fail. Input files/links are untouched.
Executable modes become 0755 and other file modes become 0644, with no inherited
setuid bits. The existing `pack` canonical inventory/signing rules then apply.
Identical materialized bytes produce identical metadata, regardless of selector
order or the upstream aliases. Do not select account databases, host settings,
devices or unrelated applications. Proprietary and firmware flags stay explicit
publisher declarations, subject to administrator policy.

### Build a pinned application catalog

`pack-catalog catalog.json /build/prepared-roots /build/new-workspace` builds an
entire publisher workspace in one operation. Prepare authenticated upstream
sources and their redistribution notices first. Inventory them with `pack-root`,
review its returned package metadata and complete file records, then retain those
records in the catalog lock. The builder never guesses libraries, architecture,
permissions, licenses or publisher trust from an upstream installation.

| Field | Meaning |
| --- | --- |
| `format` | Required integer `1`. |
| `architectures` | Required nonempty list of distinct `aarch64`/`x86_64` targets. |
| `packages` | Required nonempty list of at most 4,096 imports. |
| `packages[].source` | `aarch64`, `x86_64` or `shared`, naming an ordinary directory beneath the prepared-roots directory. |
| `packages[].recipe` | A format-1 prepared-root recipe, with its complete manifest and explicit selectors. |
| `recipe.manifest.files` | Required, nonempty pinned inventory: every file has explicit `path`, `sha256`, `bytes` and `executable`. |
| `recipe.manifest.proprietary`, `firmware` | Required booleans, including explicit `false` declarations. |

Each target-specific import's source must match its manifest architecture. Data
declared `all` uses `shared`. Every ID/version must cover every declared target;
duplicate identities and mixed shared/target-specific versions fail. Explicit
runtime runners and every dependency must resolve for each advertised version.
As in release publication, `all` data must resolve on both supported hosts.
The recipe rejects unknown fields, duplicate fields (including escaped spelling),
missing disclosures and missing file pins. The existing 8 MiB metadata limit
applies, and normal package/selector bounds still apply.

The builder captures every selected source directory before copying any package.
Guest symlinks resolve beneath that captured architecture root using `pack-root`
rules. Unexpected files, wrong sizes or changed executable status fail before
copying those files; changed bytes and missing pins also fail. There is no
fallback to an unpinned source, another architecture or a host library.

Imports remain in a private staging directory. Space checks cover unique objects,
metadata, the largest materialized package and a 64 MiB reserve, with a separate
check of the temporary filesystem. Before publication, the builder verifies all
manifests, objects and canonical recipe again. Success atomically publishes a
new 0700 workspace containing `objects`, `manifests` and `catalog.json`; an
existing destination is never replaced. Failed builds remove their staging
directory. An abrupt process kill can leave an unpublished private
`.vinix-catalog-*` directory; inspect/remove that owned directory and retry with
a new destination. A reported parent-directory flush failure means the workspace
is already visible and needs storage verification before signing.

Success emits one format-1 JSON object with `directory`, sorted `architectures`,
`package_count`, `object_count` and `catalog_sha256`. The digest covers the exact
canonical `catalog.json` bytes. Package/selector/file ordering and input JSON
whitespace do not change canonical output. Identical pinned inputs produce
identical workspace manifests; the normal release publisher then produces the
same index/signature for the same sequence, expiry and seed.

```sh
vinix-package pack-catalog catalog.json /build/prepared-roots /build/new-workspace
vinix-package publish-release /build/new-workspace company /secure/publisher-seed 1 EXPIRES_UNIX /build/new-release
```

Expose the release directory to consumers and enroll its authenticated public key
through the existing repository workflow. Catalog construction emits no signed
index, generates no key and accepts no license on behalf of consumers. The
canonical workspace lock records that import; later manual `pack`/`pack-root`
changes require a newly reviewed lock/build for reproducible catalog assembly.
This publisher workflow does not authenticate upstream archives or qualify the
applications' executable/runtime ABI or graphical sessions.

### SQLite CLI publisher profile

`sqlite-catalog SQLITE_VERSION RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY`
inventories a specific Linux application closure and emits its reviewed catalog
lock. Both `PREPARED_ROOTS/aarch64` and `PREPARED_ROOTS/x86_64` must exist, each
with these ordinary payloads and redistribution notices:

```text
bin/sqlite3                 musl PIE command-line executable
bin/vinix-linux-runner      static SDK 1 runner
lib/libc.so                musl shared loader/libc
lib/libsqlite3.so.0         shared SQLite library
licenses/sqlite-COPYRIGHT
licenses/musl-COPYRIGHT
licenses/vinix-COPYING
```

The profile checks ELF64 little-endian target/type and bounded program headers,
requires an interpreter on the CLI and no interpreter on the static runner or
shared libraries, and checks the imported object headers again. Executable
payloads are limited to 512 MiB each; notices must be nonempty and at most 1 MiB.
This structural check does not identify an arbitrary file as genuine SQLite,
authenticate its source or certify its library ABI. The publisher declares the
numeric SQLite version and a runtime version in `>=1.0.0,<2.0.0`, and must build
and qualify that closure before signing it.

The lock contains four pinned packages: `org.sqlite.cli` and
`org.vinix.sqlite-runtime` for each architecture. The application contains the
CLI and SQLite notice. Its separate runtime contains the runner, library, musl
loader/libc and all three notices; the same musl bytes are also installed at
`lib/ld-musl-ARCH.so.1`. The application declares a runtime dependency in
`>=1.0.0,<2.0.0`, so a qualified compatible library update can leave the CLI
package unchanged. Changes outside that range require a revised application
contract. Licenses remain visible in package metadata and payloads; proprietary
and firmware disclosures are explicitly false for this profile.

The CLI requests no optional permissions or associations. In Software, select
the installed SQLite application and choose **Launch in Terminal**. From an
existing Terminal, use `vinix-package run-terminal org.sqlite.cli`; it opens
`@DATA@/database.sqlite3` in the ordinary account's private app data directory.
SQLite WAL, journals and temporary files stay inside the existing sandbox
contract. The baseline file operations include advisory locks (`flock`), which
operate on open file descriptors and grant no additional paths. The launcher's
descriptor-closing rules still apply. Arbitrary home-directory databases,
document arguments and extension loading are outside this profile. Uninstall
removes the app/runtime closure and registrations while retaining the database;
rollback also retains it.

Success atomically publishes a new 0700 directory containing only `catalog.json`
and returns format-1 JSON with `profile: "sqlite-cli"`, `directory`, `catalog`,
`catalog_sha256`, both versions and `architectures`. No key, signed index or
consumer enrollment is created. The usual captured-root import, free-space
checks, canonical metadata and no-overwrite rules apply. Handled failures remove
temporary payloads; an abrupt kill can leave a private `.vinix-sqlite-profile-*`
directory for inspection and removal. Keep prepared roots stable and review the
lock; `pack-catalog` rejects changes to its pinned inputs.

```sh
vinix-package sqlite-catalog 3.53.4 1.0.0 /build/sqlite-roots /build/sqlite-lock
vinix-package pack-catalog /build/sqlite-lock/catalog.json /build/sqlite-roots /build/sqlite-workspace
vinix-package publish-release /build/sqlite-workspace company /secure/publisher-seed 1 EXPIRES_UNIX /build/sqlite-release
```

The maintained [SQLite qualification](../../tests/packages/sqlite-profile-check.md)
builds unmodified, hash-pinned upstream SQLite using V orchestration, then checks
real database, library upgrade, rollback and offline reinstall behavior on both
hosts. The fixture publisher key is for testing; it is not a supported public
repository or an enrollment decision for users.

## Manifest

```json
{
  "id": "org.example.editor",
  "version": "1.0.0",
  "architecture": "aarch64",
  "name": "Example Editor",
  "description": "A text editor for project documents",
  "homepage": "https://example.org/editor",
  "license": "MIT",
  "proprietary": false,
  "firmware": false,
  "kind": "native",
  "runtime": "",
  "entrypoint": "bin/editor",
  "arguments": [],
  "permissions": ["files"],
  "associations": ["text/plain"],
  "dependencies": [],
  "files": [],
  "sdk": 1
}
```

IDs begin with lowercase ASCII and contain lowercase letters, digits, dot, dash
or underscore, at most 128 bytes. Versions have three numeric components without
leading zeros/prereleases. Architecture is the **Vinix host target**, `aarch64` or
`x86_64`. Only data declares `all`; publish binaries for the actual qualified
host/runtime combination. No implicit architecture aliases/fallback exist.

Generated file records are
`{"path":"bin/editor","sha256":"64 lowercase hex characters","bytes":1234,"executable":true}`.
There are no setuid bits, device nodes, link instructions, absolute output paths
or package scripts. Limits: 16,384 files, 4 GiB/file, 64 GiB/package, 8 MiB per
index/combined cached snapshot/state record. Relative paths have no dot/parent or
empty components, backslashes or controls, and are at most 1,024 bytes.

Dependencies are
`{"id":"org.example.runtime","minimum":"2.0.0","before":"3.0.0"}`.
Minimum is inclusive, before exclusive; either may be empty. Each ID appears once.
Encode runtime/API compatibility in these bounds. Virtual providers, optional
dependencies and external solver hooks are outside format 1.

### FFmpeg local media publisher profile

`ffmpeg-catalog RUNTIME_VERSION PREPARED_ROOTS NEW_LOCK_DIRECTORY` inventories
the pinned FFmpeg **8.0.1** local media profile on AArch64 and x86_64. Its three
packages are `org.ffmpeg.cli`, `org.ffmpeg.probe` and
`org.vinix.ffmpeg-runtime`. Both applications declare only `files`, share the
runtime in the compatible `>=1.0.0,<2.0.0` range, and use the packaged static
Linux runner and musl loader. Firmware/proprietary flags remain false.

Each `PREPARED_ROOTS/aarch64` and `PREPARED_ROOTS/x86_64` contains:

```text
bin/ffmpeg, bin/ffprobe                 ELF64 musl PIE applications
bin/vinix-linux-runner                  static target V SDK runner
lib/libc.so                            target musl loader/library
lib/libavcodec.so.62, libavdevice.so.62
lib/libavfilter.so.11, libavformat.so.62
lib/libavutil.so.60, libswresample.so.6, libswscale.so.9
licenses/ffmpeg-LICENSE.md, ffmpeg-COPYING.LGPLv2.1
licenses/musl-COPYRIGHT, vinix-COPYING, v-COPYRIGHT
sources/ffmpeg.tar.xz                   exact pinned upstream source archive
sources/build.json                     retained build command vectors
sources/linux-runner.v, ffmpeg-build.v, ffmpeg-source.json
```

The source archive's length and SHA-256 must match
[ffmpeg-source.json](../../tests/packages/ffmpeg-source.json). ELF format,
architecture, interpreter presence and ordinary executable metadata are checked
before import and again on captured payload objects. All notices/build sources
are required, nonempty and bounded. Symlinks are materialized within captured
guest roots. The output is a canonical `catalog.json` only; temporary payload
copies are removed. Both architectures, closure, source pin, disk reserve and
new destination requirements are enforced before publication. `pack-catalog`
subsequently rechecks the exact inventory pins.

The V builder [ffmpeg-build.v](../../tests/packages/ffmpeg-build.v) checks the
archive pin, snapshots and extracts the unmodified upstream source, invokes its
configure/make build with target musl compilers, and compiles the V SDK runner.
It disables automatic external dependencies, GPL/nonfree options, network,
hardware acceleration and assembler optimizations. The enabled local media
subset includes AVI/MPEG-4, WAV/PCM, raw video, generated test video/sine audio,
scale/format and audio resampling. This profile is deliberately narrower than
an unrestricted Alpine FFmpeg installation. The upstream
[license description](https://ffmpeg.org/doxygen/trunk/md_LICENSE.html) explains
the LGPL/GPL configuration split. LGPL notices and corresponding
upstream source are retained with the runtime; runtime versions are an explicit
publisher compatibility declaration, not inferred ABI certification.

```sh
ffmpeg-build /secure/ffmpeg-8.0.1.tar.xz /build/new-ffmpeg-inputs
vinix-package ffmpeg-catalog 1.0.0 /build/new-ffmpeg-inputs/roots /build/new-ffmpeg-lock
vinix-package pack-catalog /build/new-ffmpeg-lock/catalog.json /build/new-ffmpeg-inputs/roots /build/new-ffmpeg-workspace
vinix-package publish-release /build/new-ffmpeg-workspace company /secure/publisher.seed 1 EXPIRES_UNIX /srv/new-ffmpeg-release
```

The source pin records exact bytes from the official upstream HTTPS archive;
it does not verify the upstream PGP signature or enroll a consumer publisher.
Authenticate upstream delivery and review the configuration before public
publication. [Qualification](../../tests/packages/ffmpeg-profile-check.md)
covers the retained compiler/kernel tuple and enabled media subset.

## Runtimes and launch

| Kind | Requirements |
| --- | --- |
| `native` | Executable entrypoint in its own payload or explicit runtime. Static V is the initial portable case. |
| `linux` | Explicit target loader/library runtime and executable runner, qualified against Vinix's syscall/ABI subset. |
| `windows` | Explicit target Wine/translation runtime and runner; executable/resources remain in the app payload. |
| `apple` | Explicit target Mach-O compatibility runtime and runner for its qualified API subset; no general AppKit promise. |
| `runtime` | Target-specific immutable runtime files, updated as a normal dependency, with no app launcher. |
| `data` | Assets/docs or explicitly licensed firmware payloads; no app launcher. |

`runtime` names a declared dependency of kind `runtime`; `entrypoint` then names
an executable **inside that runtime**. For example, a Windows app uses
`"entrypoint":"bin/wine-runner"` and `"arguments":["@APP@/program.exe"]`.
Runners must use packaged loaders/libraries rather than host-global installations.
Use `pack-root` to materialize a verified prepared runtime's symlinks, or supply
ordinary files directly to `pack`.

For a dynamically linked **musl** Linux application, package the target static
[`vinix-linux-runner`](linux-runner.v) inside its runtime. Package staging builds
the SDK artifact at `/usr/libexec/vinix/vinix-linux-runner`; the installed app
must declare its signed runtime copy as the entrypoint. For an AArch64 example:

```json
{
  "kind": "linux",
  "runtime": "org.example.musl-runtime",
  "entrypoint": "bin/vinix-linux-runner",
  "arguments": ["@RUNTIME@/lib/ld-musl-aarch64.so.1", "@APP@/bin/application"],
  "dependencies": [{"id":"org.example.musl-runtime","minimum":"1.0.0","before":"2.0.0"}]
}
```

The runner execs that absolute loader with `--library-path`, the service's
`LD_LIBRARY_PATH`, the application and literal arguments/documents. The ELF's
host-global PT_INTERP path is not used. Library directories include `lib` and
`usr/lib` in the app, runtime and transitive dependency payloads. The production
sandbox hides host loader/library paths; missing packaged libraries fail with
the loader's diagnostic and exit status. No shell or runtime download occurs.
The process inherits the ordinary identity, permissions and service generation
lease. This runner targets musl's loader protocol; other Linux loaders need an
explicit qualified runner. Bundling libraries alone does not supply every Linux
syscall, service, plugin/data search path or graphics API.

The explicit environment includes `HOME`, `TMPDIR`, `WINEPREFIX`, `PATH`,
`LD_LIBRARY_PATH`, `LANG`, and declared `DISPLAY`. Argument substitutions
`@APP@`, `@DATA@`, `@RUNTIME@` are literal paths, never shell evaluation. Supplied
document paths follow those arguments. Apps receive read/execute payload/runtime
access and write/create private-data access, including advisory file locking.
`files` grants supplied documents, not the entire home; `network`, `process`,
`display`, `audio` request corresponding sandbox promises/device or IPC paths.
Organization policy can refuse requests.
See [actual enforcement limits](../sandbox/README.md).

Apps must handle denied access/missing services and save in private data or a
supplied document. Keep on-disk data compatible with version rollback. A service
lease preserves the generation until the launched process exits; runners must
remain alive while children use runtime files.

Installed apps register automatically in Start and Quick Launch. A declared
`associations` MIME type plus the `files` permission makes an app available in
the shared Open With chooser. Documents are appended as literal arguments;
install/upgrade never changes user defaults. Uninstall removes active handlers,
with user preferences retained for rollback/reinstall. Desktop launches use a
Software output/diagnostic window and the same `run` contract; terminal input
requires CLI execution. Execution requires an ordinary user identity with no
supplementary groups. An administrator may configure `launch_user` for the root
desktop: the session runner drops credentials before re-executing the service,
and the ordinary service rechecks trust and acquires its own generation lease.
The chosen account cannot come from a package, an argument or an environment
variable. This profile does not acquire the hardware seat; display/audio runtimes
still require broker qualification. An ordinary caller uses its own identity.

Launch reads trust/policy under the package reader lock and acquires its generation
lease before releasing that lock. The ordinary child repeats this admission check
after the credential handoff. Later revocation prevents new launches; an already
admitted process retains its validated snapshot and lease until exit.

The built-in `NativeApp` V interface and VAPP version 11 remain internal desktop
contracts. Third-party ui2 clients need compositor adapter qualification. Importing
`desktop/app_process.v` is not a supported standalone UI SDK protocol.

### Interactive terminal execution

`run-terminal ID [ABSOLUTE_FILE...]` is an additive SDK 1 command. Standard input
and output must both be terminals; redirected streams fail before launch. It
uses the same package state lock, payload/trust/policy verification, ordinary
identity transition and immutable-generation lease as `run`. The explicit
terminal launch adds the `tty` promise and `TERM=linux`. Filesystem grants and
package permissions remain the normal declared closure/private-data/document
grants; it unveils no device directory. Plain `run` retains its existing promise
set and batch behavior. Manifests, signatures and metadata digests are unchanged.

Software exposes **Launch in Terminal** for installed applications. Its trusted
Terminal implementation starts `/usr/bin/vinix-package run-terminal ID` on a
new PTY through literal `execve` arguments, with an explicit environment and no
shell. The child claims the controlling terminal and receives only descriptors
0, 1 and 2. Linux/Vinix closes all higher descriptors with `close_range`; host
fixtures enumerate their open descriptors before fork. Geometry is set before
execution, reads are nonblocking, and ordinary Terminal input/paste, resizing,
UTF-8/VT rendering and bounded scrollback apply.

The application occupies Software until it exits, then **Back to Software**
refreshes the catalog. Normal close/return is refused while it runs. Forced
desktop retirement closes the PTY and lets terminal hangup reach its process
group; it does not kill a package lease holder independently of its sandbox
child. Applications that ignore hangup may remain alive with their leases.
The existing Start/Quick Launch requests retain their launch behavior; this
terminal action is an explicit choice within Software. This provides CLI
interaction, not a graphical display broker or an arbitrary application runtime.
See [qualification](../../tests/packages/terminal-check.md).

### Literal command arguments

```text
vinix-package run-args ID [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]
vinix-package run-terminal-args ID [--data-cwd] [--file ABSOLUTE_FILE]... -- [LITERAL_ARGUMENT...]
```

These additive SDK 1 commands keep the signed entrypoint and fixed manifest
arguments, then append the supplied literal argument vector. Values after `--`
are never parsed as service options, evaluated by a shell or substituted with
package/data/runtime paths. Empty arguments, spaces, newlines, leading options
and shell punctuation retain their bytes; NUL and arguments exceeding 4,096
bytes are refused. The input permits at most 256 arguments and 256 documents,
with at most 64 KiB total including terminators.

`--file` is an access grant, separate from the argument vector. Each document
must be an existing absolute regular file and the application must declare
`files`; grants retain the normal read/write semantics. Documents are **not**
automatically appended in this mode. A path appearing in an argument grants
no access by itself. New output files can be created in private application
data; outside that directory, an existing file requires an explicit grant.
`--data-cwd` selects that private data directory as the working folder, so
relative outputs are retained there. It adds no paths, permissions or argument
substitutions. Without the flag, the working folder remains the installed app.
The ordinary child validates the request again after the credential handoff.
For example, after installing the FFmpeg profile as an administrator:

```sh
vinix-package run-args org.ffmpeg.cli -- -version
vinix-package run-args org.ffmpeg.cli --data-cwd -- -f lavfi -i testsrc2=size=64x48:duration=1 -c:v mpeg4 -threads 2 "example with spaces.avi"
vinix-package run-args org.ffmpeg.cli -- -f lavfi -i testsrc2=size=64x48:rate=10:duration=1 -c:v mpeg4 -threads 2 /home/alex/.local/share/vinix-apps/org.ffmpeg.cli/example.avi
vinix-package run-args org.ffmpeg.probe --file /home/alex/.local/share/vinix-apps/org.ffmpeg.cli/example.avi -- -v error -show_streams /home/alex/.local/share/vinix-apps/org.ffmpeg.cli/example.avi
```

Use the ordinary account's own private-data path. The root caller uses only the
administrator-configured `launch_user`, reconstructs literal `--file`/`--`
arguments for the isolated child, and the child rechecks limits, trust, policy,
files and payloads before sandboxing. Generation locking/leases and declared
permissions remain the usual launch contract. Terminal mode additionally checks
terminal input/output and supplies `tty`/`TERM=linux`. `run`/`run-terminal` keep
their existing document-appending behavior. Manifest/index/signature formats
and digest encoding are unchanged.

V SDK callers use `command_launch(argv) !CommandLaunch` to parse the service
prefix and `Service.run_command(id, input, terminal) !int` to execute it;
`command_launch_plan` exposes the same validated sandbox plan for inspection.

Software's **Launch options…** form exposes these commands for installed apps.
Enter arguments using single/double quotes to group values and backslash to
escape the following character outside single quotes. Empty quoted arguments
are preserved. Variables, wildcards, substitutions, redirection and pipelines
remain literal; incomplete quotes/escapes fail before starting the service.
The fields retain UTF-8 text exactly and reject invalid/control-character pastes
and edits beyond 4,096 bytes instead of silently truncating them.

Add each document's absolute path to **Allowed files**, then use its path
explicitly among the app arguments. Duplicate paths are refused, files can be
paged and removed, and an unfinished file entry must be added or cleared before
launch. **Working folder: private app data** is the default in this form; its
relative outputs are saved under the ordinary account's
`~/.local/share/vinix-apps/ID`. Choose **installed app** for apps needing their
packaged assets as the working folder. **Run** shows captured diagnostics;
**Run in Terminal** transfers the exact vector to Software's PTY. Input, grants
and working-folder choice cannot change while a worker is active. Cancelling,
reloading or closing clears the draft; failed batch execution retains it for
correction. The service performs the actual file/access/trust/policy checks.

`pkgprotocol.command_words(text)` implements this bounded quoting grammar and
returns owned strings; `command_vector` validates and builds owned CLI arguments.
Release either with `free_command_values`. SDK vectors accepted by `run-args`
remain literal and never pass through this editor grammar again.

## Repository and JSON interfaces

```text
index.json                       format, repository, sequence, expires, packages[]
index.sig                        hex Ed25519 signature of exact index.json bytes
objects/SHA256                   immutable content
manifests/ID-ARCH-VERSION.json    publisher input, not consumer trust input
```

Expiry is UTC Unix seconds; sequence is a positive increasing integer. The signed
index embeds full manifests/hashes; consumers never acquire unsigned side metadata.

`repo-enroll ID URL PUBLIC_KEY_HEX` authenticates a current index with the supplied,
independently authenticated Ed25519 key before enabling that repository. Run
`update` to publish its catalog. Reusing an ID replaces the URL/key and preserves
architecture, launch account and policy. Local `file://` repositories support
offline enrollment. `repo-revoke ID` disables that publisher without fetching
metadata or deleting installed payloads/personal data; uninstall remains available.
Key replacement also revokes launch/rollback trust for old-key installations.

`--json repo-list` emits `{format:1,architecture,repositories,history}`.
Repositories contain `{id,url,public_key}`; history contains
`{id,public_key,sequence,index_sha256}` for enrolled, revoked and replaced keys.
Listing takes a shared lock once a package store exists; an active writer gives
a busy diagnostic. A fresh image can be listed without initializing its store.

`repo-review enroll ID URL KEY` and `repo-review revoke ID` emit a read-only
format-1 `RepositoryReview`: `operation`, `architecture`, `id`, `url`,
`public_key`, `previous_url`, `previous_public_key`, `fingerprint`,
`index_sha256`, `sequence`, `expires`, `package_count` and `remembered_sequence`.
Enrollment verifies a current signed index with the supplied key and checks
retained replay/equivocation floors. No objects are downloaded and neither trust
nor persistent package state changes. A private metadata workspace is removed
on ordinary completion. Revocation needs only current configuration; its index
digest, sequence, expiry, count and remembered-sequence fields are empty/zero.
Its previous/current URL and key identify the exact configuration to disable.

Call `repo-apply FINGERPRINT enroll ID URL KEY` or
`repo-apply FINGERPRINT revoke ID` with the reviewed operation/arguments. Under
the writer lock, the service reloads configuration and compares the complete
intent; enrollment also re-verifies the signed index and sequence history.
Changed metadata, policy, launch account, repository/key or remembered floors
fail as stale before publishing trust/history. Review again. The fingerprint is
an opaque freshness check and grants no administrator authority. After successful
enrollment call `update` to load the combined catalog; a refresh failure does not
undo the trust change. Revocation retains payloads, personal data and history.

The lightweight [`pkgprotocol` repository module](pkgprotocol/repositories.v)
provides bounded `decode_repositories`, `decode_repository_review`, input/response
validation and explicit `close()` methods for consumers with manual memory
management. Status has at most 4096 repository/history records and encoded
responses are bounded to 8 MiB. Unknown formats and incomplete intents fail closed.

History is keyed by ID/key, independent of mirror URL, and records exact signed
index bytes. Reject lower sequences and changed bytes at an existing sequence;
increase sequence for expiry renewals too. Revocation and empty refreshes retain
floors. History is durable before configuration/catalog publication: retry an
interrupted enrollment/refresh with the same or a newer signed index. An older
cache is refused until refreshed. The administrator owns this local history;
it is not a hardware trust anchor. See the
[administration and recovery contract](../../docs/application-distribution.md#trust-and-configuration).

`view` emits one `{format:1,generation,architecture,offline,catalog_error,update_error,rows}`
JSON object. Rows include ID/name/description, available/installed version, target,
kind, repository/key, license/proprietary/firmware flags, permissions, explicit
install/update flags and policy diagnostic. Additive `installed_name`,
`installed_kind` and `installed_permissions` fields describe the actual installed
manifest for launch controls; an explicitly empty installed permission set must
not inherit the planned candidate's permissions. Older consumers may ignore
these fields; older services retain the previous presentation fallback.
Pending rows include `update_action`
(`install`, `update`, `remove`; otherwise empty), with `updatable:true`. They
come from one complete `upgrade` resolution and include runtime/data additions,
updates and removals, even if no application version increases. `version` is the
planned target; removals retain the installed version/provenance. Constraints,
policy and installed publisher ownership determine this plan. Manifest/key
changes and pin-required downgrades also count; index sequence renewal alone
does not. Call `review upgrade`, then `apply` with that review to maintain this
whole set. Installing an individual dependency makes it an explicit root and
has different semantics.

Expired/missing catalogs set `catalog_error`; resolution failures set
`update_error`, leave all update flags false, and retain installed metadata.
`updates` returns nonzero for either error, so an empty successful result means
no advertised package changes. New catalog applications show available publisher
metadata; full installation resolution occurs during review. The view is read
under a shared package lock and rejects more than 4096 rows or 8 MiB of encoded
metadata. `status` emits format-1 installed
state; `plan` emits `{requested,packages}`; `--json search/info/updates` emits one
row per line. Consumers ignore additional fields and reject unknown formats.
Success is exit 0; failures are nonzero with stderr diagnostics. Human progress
text is not a machine protocol.

For live operation progress, pass `--progress` to `update`, `install`, `remove`,
`upgrade`, `apply`, `deploy`, `deployment-apply` or `rollback`. It is refused with
`--json` and other commands. Ordinary human output/diagnostics are retained;
presentation records occupy complete stdout lines prefixed by
`VINIX-PACKAGE-PROGRESS ` followed by a format-1 JSON object. The producer flushes
each frame. Readers must handle frames split across pipe reads and multiple
frames in one read. These events neither authorize changes nor replace exit
status, payload verification or the installed-state protocol.

Every record explicitly contains `format`, `phase`, `package`, `repository`,
`path`, `current` and `total`. Phases are `resolve` (resolved reviewed inputs),
`metadata` (signed catalog transfer), `download`, `verify`, `copy` (staged payload),
`stage` (staged package count), `activate` and `complete`. Package/repository IDs
may be empty when a phase covers the entire operation. Paths are safe relative
payload/metadata paths. Download/copy counters use bytes; stage counters use
packages. A zero total is indeterminate. A byte counter reaching its total
does not mean the transaction completed. `resolve`, `verify` and `activate`
have zero counters; `complete` has `current:1,total:1` and is emitted only after
the relevant durable publication/activation succeeded, including unchanged
transactions. Failures may leave a partial phase and emit no completion event.

Frames are bounded to 8192 bytes. Identifiers/paths, phase-specific counter
limits, JSON field types and formats are validated by
[`pkgprotocol.decode_progress`](pkgprotocol/progress.v). Decoded events own their
strings; `.close()` releases them under manual memory management. Consumers
ignore unsupported/malformed frames and continue to report human diagnostics
and process exit status. Counter progress is sampled approximately every 200 ms
during HTTPS transfers and local copies, plus initial/final transfer counters;
package and verification boundaries may emit additional frames.

V administrative clients set `Service.progress` to an optional observer.
Config-taking transaction fixtures use `TransactionOptions.progress`; the service
uses its own configured observer when forwarding transaction options. Callbacks
receive borrowed event strings valid for the call: clone any retained fields,
and do not close borrowed events. Observers are presentation hooks, outside the
review identity; current trust, policy and resolved inputs are still checked
under the package lock. No observer enables an installation cancellation mode.

Maintenance commands load configuration under the package writer lock; read-only
review/plan/status/verification use its reader lock. The command's startup cannot
retain an older policy or publisher after a completed administration change.
`verify`, including `--json verify`, checks all installed payloads before reporting
success. Readers and launches return a busy-transaction diagnostic promptly.
On a fresh image, status/verification do not initialize package state. Direct
administrator edits to configuration must honor the same lock or quiesce package
operations; arbitrary root filesystem writes are outside this contract.

V administrative clients can use [`pkgcore.Service`](pkgcore/service.v) with
`root` and a per-command `offline` flag. It retains no configuration snapshot.
Its `refresh`, `transact`, `deploy`, `plan`, `review`, `rollback`, `collect`,
`mirror`, `state`, `verify` and `run` methods acquire the appropriate lock before
loading configuration. Config-taking core functions remain explicit snapshot
operations for isolated fixtures; they do not reload administrator configuration.
Production clients should use the service or the versioned CLI protocol.

`deployment-lock [ID...]` emits a format-2 `{format,architecture,packages,locked}`
document. `packages` contains sorted explicit roots; `locked` contains the entire
resolved dependency/runtime closure, sorted by ID. No IDs selects the current
requested roots; explicit IDs replace them. Resolution prefers authenticated
installed versions, otherwise the latest compatible candidates. Each locked
record requires `id`, `version`, `architecture`, `repository`, `public_key`,
`minimum_sequence` (positive unsigned 64-bit) and `metadata_sha256` (lowercase
SHA-256). Roots and records are unique and bounded to 4096 each.

The metadata digest is SHA-256 of SDK-1 JSON encoding of the complete `Package`
struct, plus a terminating LF. Fields follow the order in [`model.v`](pkgcore/model.v),
including empty/default fields; files sort by path, dependencies by ID,
permissions and MIME associations lexically. Launch arguments retain their order.
`package_metadata_digest` is the supported V implementation. Repository identity,
key and minimum sequence are separate lock fields; index expiry/sequence renewal
does not change the manifest digest. Every selected package must match exact
ID/version/architecture/publisher/digest in the current authenticated catalog,
whose signed sequence must meet the lock floor and persistent replay history.
The regular resolver still checks policy, installed publisher ownership, version
ranges, runtime entrypoints and full closure; unused/missing records fail.

`deployment-review FILE` emits the existing format-1 `pkgprotocol.Review`, with
operation `deploy`, complete target/removal rows and disk requirements. Its opaque
fingerprint binds a deployment-specific domain, canonical document, configuration,
installed state and exact authenticated plan. `deployment-apply FINGERPRINT FILE`
rechecks these under the writer lock before stage cleanup, acquisition or
activation. File-specific and generic `review/apply deploy IDs` fingerprints are
not interchangeable. Whitespace and root/record ordering do not change identity;
changed lock floors, format, policy, state or selected metadata require review.
An unchanged successful proposal can reuse its fingerprint. Apply progress is
human text by default; `--progress` adds the bounded presentation events described
above. Authorization remains administrator access.

Both file commands also accept format-1 `{format,architecture,packages}` root
documents, which resolve the latest satisfiable closure. `deploy FILE` supports
both formats without a review fingerprint for existing administration scripts.
Inputs require explicit fields and JSON types, matching architecture, bounded
regular files and unique roots/records; null, unknown/duplicate keys and malformed
digests/versions fail. A format-2 empty roots/records set removes all applications.
No deployment changes trust/policy or refreshes implicitly. URLs are intentionally
unbound: approved signed mirrors work offline with the same publisher and lock,
subject to normal expiry/replay checks and availability of every locked object.
Rollback/data retention use the standard transaction contract.

V clients use `Service.lock_deployment`, `Service.review_deployment`,
`Service.apply_deployment`, `DeploymentLock`, `DeploymentPackage` and
`package_metadata_digest`. Returned reviews own presentation fields and use the
usual `Review.close()` contract. Configuration is loaded after taking the lock.

Software's Deployment form uses these file-specific review/apply commands. It
retains the complete decoded review, freezes the literal file path, and closes the
snapshot on cancellation, failed review or handoff to apply. Other SDK clients
should preserve that same intent: the returned `names` describe roots read from
the document and must not replace the reviewed file in a generic `apply deploy`
call. Keep the path available for retry and preserve the nonzero service exit and
diagnostic tail separately from progress events.
The [Software deployment checks](../../tests/packages/deployment-ui-check.md)
cover this workflow and snapshot retirement independently of the service tests.

`policy` emits a canonical format-1 `{format,architecture,policy}` document from
persistent configuration. `policy-review FILE` emits
`{format:1,architecture,generation,fingerprint,previous,proposed,rows}` without
modifying configuration or fetching metadata. Input files must contain the format,
matching host architecture and all policy fields: `offline`, `allowed`, `pins`,
`permissions`, `licenses`, `allow_firmware`, `reserve_bytes`. Boolean/number fields
use their JSON types; null/missing fields and type coercion are refused. Unknown
and duplicate object keys fail, including duplicate escaped spellings, at the root,
policy and each pin record. Unique escaped keys have the same canonical identity.
Policy sets contain unique entries; pin IDs appear once and version ranges use the
dependency contract. Allowlists/pins/licenses have at most 4096 entries, licenses
are nonempty printable strings up to 256 bytes, permissions use the five named
grants and disk reserve is at most 1 TiB. Sets/pins are sorted in output.

Review rows cover every installed package with ID/name/version/kind, license,
proprietary/firmware flags, publisher ID/key, requested-root flag and
`diagnostic_before`/`diagnostic_after`. Every row field is required with its JSON
type, including false flags and empty diagnostics. Empty diagnostics mean the complete
dependency closure is allowed by current trust and the corresponding policy.
Runtime restrictions consequently appear on dependent application rows too.
Review needs neither a usable catalog nor a live publisher.

`policy-apply FINGERPRINT FILE` loads the complete configuration, installed state
and canonical proposed document under the writer lock, refuses stale reviews and
atomically saves only organization policy. Whitespace/list ordering does not
change proposed-policy identity; changed settings, trust, account selection or
installed state do. Successful unchanged proposals may reuse a fingerprint: it
is a freshness check, not a one-time authorization token. Both `policy` and apply
return a format-1 document. `--offline` never implicitly changes persistent policy.
Existing applications/data/generations/trust are retained; restrictive policy
still allows uninstall. Explicit administrator-owned configuration is required.

V clients use `Service.policy`, `Service.review_policy`, `Service.apply_policy`,
`PolicyDocument` and `PolicyReview`. `decode_policy_review` checks bounded complete
responses and installed provenance. Returned documents/reviews and decoded
reviews own their presentation fields; call `.close()` after use under manual
memory management. Unknown/duplicate keys in review roots, policies, pins and
installed rows are refused; formats other than 1 are
refused. See [organization administration](../../docs/application-distribution.md#offline-and-organization-deployment).

`review install|remove|upgrade|deploy|rollback [ID...]` emits a format-1 review
without downloading payloads or changing installed state. It includes the active
generation, rollback target generation, operation/IDs, target requested roots,
and every package in the target closure plus removed packages. Rows contain
`action` (`install`, `update`, `keep`, `remove`), previous/target versions, runtime,
publisher/key, license/proprietary/firmware flags and declared permissions.
`disk_needed`, `disk_available` and `disk_reserve` are byte counts; estimates
include the complete next generation, missing cached objects and metadata.
Removal uses installed provenance and remains available after publisher expiry
or revocation; rollback verifies retained payloads and current trust/policy.

After review, call `apply FINGERPRINT OPERATION [ID...]` with the returned
`fingerprint`, operation and IDs. The service resolves again under its writer
lock and compares the complete manifests/payload hashes, provenance, requested
roots, active state, configuration/policy and rollback target. Changed inputs
fail with a stale-review diagnostic before cleanup, downloads or activation;
obtain a fresh review. Free-space/cache changes are checked again at apply time.
The fingerprint is an opaque freshness check, not an authorization credential;
administrator access is still required. Ordinary install/remove/upgrade/deploy
and rollback commands remain available for existing scripts.

The lightweight [`pkgprotocol` V module](pkgprotocol/review.v) provides `Review`,
`ReviewPackage`, bounded `decode_review`, validation and explicit `Review.close()`
for consumers with manual memory management. Service-created and decoded reviews
own their presentation fields. Renderers should retain the snapshot while it
is on screen, pass literal arguments to `apply`, then close it on cancellation,
replacement or handoff. Additional JSON fields are ignored; unknown formats,
invalid provenance and incomplete requested-package records are refused.

[The V example](../../examples/package-hello/main.v) and target manifests show a
native payload. `v run examples/package-hello/build.v /build/new-example-repository`
cross-compiles and packs both ELF targets using the matching musl compilers.
Sign/enroll the repository, then install/verify/run/remove
on an ordinary Vinix session. Run [the V fixtures](../../tests/packages/distribution-check.v)
before publishing, and advertise only host/runtime/app tuples with retained guest
qualification receipts.

For the native launch contract, run the
[production-sandbox qualification](../../tests/packages/runtime-check.md) against
both target kernels. It checks real permissions, explicit immutable runtime
dependencies, tamper refusal and generation leases through update/uninstall/GC;
retained passing runs record hashes of the kernel, sandbox, payload, service,
session runner and serial output. These fixtures qualify package mechanics,
not the API coverage of a Linux, Windows, Apple or graphical runtime.

The [dynamic Linux check](../../tests/packages/linux-runtime-check.md) exercises
`pack-root`, this runner, a target musl loader and a shared V library under the
production sandbox on both architectures. Its receipts qualify this narrow
loader/package tuple; qualify actual upstream applications separately.

The current dynamic Linux fixture uses a position-independent executable. The
explicit loader is itself mapped as an executable, so a fixed-address program
can collide with its randomized image on the qualified kernel. Qualify that
address layout separately; the current PIE fixture is not evidence that every
fixed-address binary works. The dynamic-check documentation retains the observed
collision and the passing PIE reruns.

[Persistent package recovery](../../tests/packages/persistence-check.md) tests
abrupt QEMU termination and recovery on the same ext2 disk at the staged,
published and activated checkpoints on both architectures. It checks cached
partial-object recovery, offline upgrade, rollback, launcher removal and retained
personal-file metadata. Its receipts cover those checkpoints; publishers must
still qualify app data migrations, underlying filesystem/device crash behavior
and their runtime's API coverage.
