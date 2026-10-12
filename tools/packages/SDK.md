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
/tmp/vinix-package publish /build/new-repository company /secure/publisher.seed 1 2000000000
```

`keygen` prints the lowercase-hex public key and creates a mode-0600, 32-byte
signing seed encoded as hex. Keep it outside repositories/deployment images.
Distribute the public key through an authenticated channel. Upload objects first,
then switch the web server to the complete new repository directory. Never change
content at an existing hash. Increase sequence for every index change, including
expiry. Key rotation/revocation requires administrator configuration.

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
access and write/create private-data access. `files` grants supplied documents,
not the entire home; `network`, `process`, `display`, `audio` request corresponding
sandbox promises/device or IPC paths. Organization policy can refuse requests.
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

The built-in `NativeApp` V interface and VAPP version 11 remain internal desktop
contracts. Third-party ui2 clients need compositor adapter qualification. Importing
`desktop/app_process.v` is not a supported standalone UI SDK protocol.

## Repository and JSON interfaces

```text
index.json                       format, repository, sequence, expires, packages[]
index.sig                        hex Ed25519 signature of exact index.json bytes
objects/SHA256                   immutable content
manifests/ID-ARCH-VERSION.json    publisher input, not consumer trust input
```

Expiry is UTC Unix seconds; sequence is a positive increasing integer. The signed
index embeds full manifests/hashes; consumers never acquire unsigned side metadata.

`view` emits one `{format:1,generation,architecture,offline,catalog_error,rows}`
JSON object. Rows include ID/name/description, available/installed version, target,
kind, repository/key, license/proprietary/firmware flags, permissions, explicit
install/update flags and policy diagnostic. Expired/missing catalogs set
`catalog_error`; installed rows remain visible. `status` emits format-1 installed
state; `plan` emits `{requested,packages}`; `--json search/info/updates` emits one
row per line. Consumers ignore additional fields and reject unknown formats.
Success is exit 0; failures are nonzero with stderr diagnostics. Human progress
text is not a machine protocol.

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

[Persistent package recovery](../../tests/packages/persistence-check.md) tests
abrupt QEMU termination and recovery on the same ext2 disk at the staged,
published and activated checkpoints on both architectures. It checks cached
partial-object recovery, offline upgrade, rollback, launcher removal and retained
personal-file metadata. Its receipts cover those checkpoints; publishers must
still qualify app data migrations, underlying filesystem/device crash behavior
and their runtime's API coverage.
