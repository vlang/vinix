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
expiry. Administrators explicitly enroll, replace or revoke publisher keys using
the repository commands below; publishers cannot authorize their own keys.

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

Launch reads trust/policy under the package reader lock and acquires its generation
lease before releasing that lock. The ordinary child repeats this admission check
after the credential handoff. Later revocation prevents new launches; an already
admitted process retains its validated snapshot and lease until exit.

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
install/update flags and policy diagnostic. Pending rows include `update_action`
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

[Persistent package recovery](../../tests/packages/persistence-check.md) tests
abrupt QEMU termination and recovery on the same ext2 disk at the staged,
published and activated checkpoints on both architectures. It checks cached
partial-object recovery, offline upgrade, rollback, launcher removal and retained
personal-file metadata. Its receipts cover those checkpoints; publishers must
still qualify app data migrations, underlying filesystem/device crash behavior
and their runtime's API coverage.
