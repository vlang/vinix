# Application distribution

Vinix has a native V application package service, `vinix-package`, and a
**Software** desktop application. They manage signed repositories and immutable
application generations on AArch64 and x86_64. The desktop security-tools stage
installs the service, sandbox launcher, Software process link and XDG registration
directory. It preserves existing configuration; a fresh image enrolls no keys.

This application store is separate from the Alpine `pkg`/`apk` system layer.
Existing Alpine ports and special downloads still use that frontend and its
persistence rules. They do **not** acquire these rollback guarantees. Release
migration of that catalog remains part of roadmap acceptance.

## Trust and configuration

An administrator creates `/etc/vinix-packages/config.json`:

```json
{
  "format": 1,
  "architecture": "aarch64",
  "launch_user": "",
  "repositories": [{
    "id": "company",
    "url": "https://software.example.org/vinix",
    "public_key": "REPLACE_WITH_THE_PUBLISHER_64_CHARACTER_HEX_PUBLIC_KEY"
  }],
  "policy": {
    "offline": false,
    "allowed": [],
    "pins": [],
    "permissions": ["network", "files", "process", "display", "audio"],
    "licenses": [],
    "allow_firmware": false,
    "reserve_bytes": 67108864
  }
}
```

Replace the intentionally invalid example key with a publisher key obtained
through your organization's trusted channel. No key is learned from an index.
Keep configuration/state owned by the administrator and unwritable by ordinary
users. Removing a repository/key revokes acquisition, rollback and subsequent
launches from that publisher. A root administrator can still alter installed code
or local sequence records; this is not hardware protected antirollback.

Ed25519 authenticates the exact index bytes **before** decoding. The service
checks repository identity, format, expiry, increasing sequence and same-sequence
equivocation. Refresh commits all configured repositories together; failure keeps
the previous catalog. SHA-256 and length authenticate every payload. Transport
accepts certificate-validated HTTPS or an absolute local `file://` repository.
HTTP, unknown architectures, unsafe paths, special files, symlinks, conflicting
file paths and ambiguous package ownership are rejected.

## Install, maintenance and recovery

```sh
vinix-package update
vinix-package search editor
vinix-package info editor
vinix-package plan install editor
vinix-package install editor
vinix-package updates
vinix-package upgrade
vinix-package rollback
vinix-package remove editor
vinix-package verify
vinix-package gc
```

Search covers names, IDs and descriptions. Info shows publisher, repository,
license, permissions, target and installed version. Dependency ranges have
inclusive minimum/exclusive upper versions. Resolution backtracks across all
constraints, supports cycles and selects only the host target or independent
**data**. Install prefers compatible installed versions; upgrade/deploy choose
the latest satisfiable closure. Dependencies cannot silently switch repositories.

Changes take an exclusive process-released filesystem lock. Before downloading,
space is checked for the complete staged generation, missing cached payloads,
filesystem overhead and the configured reserve. Files stream in 64 KiB blocks.
Partial downloads persist as `objects/HASH.part`; retries resume and verify the
complete hash. Complete partial files are promoted without network access. Hash
failures discard the partial file. Network/storage failure leaves activation
unchanged.

Each generation contains package state, the full payload closure, launcher
records and a running-application lease. Files/directories are flushed before
publication; POSIX rename switches `current` atomically. The next transaction
retires abandoned stages. A crash before activation exposes the old complete set;
a crash after it exposes the new complete set. Actual durability depends on the
filesystem/device honoring flush and rename. No maintainer scripts or implicit
user-data migrations run during activation.

Rollback checks payloads and current organization/key policy before restoring
the previous generation. Uninstall removes the app and unused dependencies from
the active generation; explicitly installed dependencies remain roots. Packages
still required by another root cannot be removed alone. Removal works without a
valid/reachable catalog, including after publisher revocation. Previous payloads
remain for rollback. `gc` retains active/previous and leased generations, removes
older unused generations and unused complete objects, and clears abandoned
partial downloads.

Personal data under `~/.local/share/vinix-apps/ID` survives uninstall/rollback.
After uninstall an ordinary user can explicitly erase it with
`vinix-package purge-data ID`. No package owns arbitrary home files. Data/schema
compatibility across rollback remains the developer's responsibility.

## Software and execution

**Software** offers catalog, installed and updates filters, description search,
publisher/permission/license review, install/uninstall confirmation, repository
refresh, update-all, rollback, launch, progress and recent failure output. A running
mutation prevents normal window close. Mutations require administrator access;
there is no setuid service or automatic privilege escalation.

`vinix-package run ID [ABSOLUTE_DOCUMENT...]` executes as an ordinary user through
`vinix-sandbox`, failing closed if confinement is unavailable. Apps have private
data, temporary directories and Wine prefixes. Package/runtime paths come from
one immutable generation, with no implicit host Wine/Linux/Apple installation.
The environment is explicit and arguments are literal. `files` authorizes only
supplied documents. Display/audio paths are granted only when declared. See
[the sandbox's enforcement boundaries](../tools/sandbox/README.md).

For today's root desktop, an administrator can set `launch_user` to an existing
ordinary account in the root-owned configuration. Software shows **Launch as
NAME**. The service starts `vinix-session run --isolated NAME` and re-executes
itself after the session tool has verified all user/group IDs, cleared account
memberships and capabilities, and set `no_new_privs`. The ordinary service then
re-reads current trust/policy, acquires the generation lease, verifies payloads
and creates private data as that user. Root never creates or changes files in
the application data directory. The child's exit status and output reach Software.

An empty `launch_user` requires the caller to be an ordinary user already.
Root/system/greeter accounts cannot be selected, and an ordinary caller cannot
use the setting to change identity. Create the account with the account tools
first; staging installs the session runner but does not invent an account or
enroll a publisher. Direct unprivileged launches need empty supplementary groups;
`vinix-session run --isolated USER /usr/bin/vinix-package run ID` supplies that
profile when invoked by an administrator. Documents must be accessible to that
account, including their parent directories.

This application session does not take the hardware seat or authenticate a
desktop login. Direct display/input/audio device access remains denied without
the seat, even when a package declares those permissions. Graphical runtimes
need a separately qualified display/audio broker. Full ordinary-user desktop
sessions and a public native GUI protocol remain release work.

Installed applications appear in Start's All Programs/search and Quick Launch.
Search includes package IDs and descriptions. Both use one bounded registry read
from an administrator-owned immutable generation; arbitrary XDG `Exec` commands
are not imported. Opening a launcher refreshes registration, so install/remove,
upgrade and rollback become visible without restarting the desktop. Runtime/data
packages are omitted. Package actions use stable IDs, independent of row order.

Files' application chooser opens the shared, paged **Open With** dialog. Packages
are offered only for their declared MIME types when they declare `files` access.
Installation never takes over user defaults. An explicit choice is saved as
`package.ID` in the session association store and used by Files, document search
and session document requests. Removal or loss of the MIME/file grant uses the
built-in fallback while retaining that preference for rollback or reinstall.

Each package launch opens a Software window and passes literal arguments to
`vinix-package run`; the service rechecks the current package/dependency closure,
publisher policy and payloads before sandbox execution. The window shows output
and launch failures, including missing or invalid launch-account configuration.
Closing it while the application runs is prevented to retain the generation
lease. This monitor is suitable for noninteractive programs and apps using their
declared display runtime; interactive terminal input still requires the CLI.
It does not turn the internal native compositor protocol into a public GUI SDK.

Install, uninstall, Update all and Rollback first request a read-only review of
the complete resolved package set. The paged review shows additions, version or
payload changes, retained packages and removals, including implicit runtimes and
data. Each row exposes its description, old/new version, architecture, runtime,
publisher/key, license/proprietary/firmware flags and declared permissions. A
summary shows estimated next-generation/cache space, available space and the
configured reserve. Confirm appears only after a valid matching review arrives;
Cancel releases the review without changing the installation.

Confirmation passes the review fingerprint and original operation/IDs to the
service. It recomputes the plan under the writer lock and rejects changed state,
policy, provenance or payload metadata before cleanup, acquisition or activation.
A stale review returns a diagnostic and requires a new review. Ordinary CLI
maintenance remains compatible; fingerprints add a freshness check for graphical
and SDK clients, and administrator access is still required. Failed dependency
resolution and unsupported review responses leave Confirm unavailable.

Non-data/non-runtime packages also get `.desktop` launchers with MIME types,
package ID and runtime provenance. `/usr/share/applications/vinix-packages` points
through activation, so XDG registration removal/rollback follows package state.
Ordinary sessions can execute packages using the CLI or an XDG-aware launcher.

## Offline and organization deployment

```sh
vinix-package mirror /media/new-mirror editor browser
vinix-package --offline install editor
vinix-package deploy /etc/company/applications.json
```

Mirror exports signed indexes and the resolved payload closure. On the offline
machine enroll each `/media/new-mirror/REPOSITORY_ID` as a `file://` repository
with the same ID/key, then `update`. Expiry and sequence checks still apply;
publishers must plan suitable expiry for offline use. Indexes may advertise apps
outside the exported closure; those requests report missing payloads.

Organization policy restricts the complete dependency closure through `allowed`,
version `pins`, permitted `permissions` and accepted proprietary `licenses`.
Firmware is blocked unless `allow_firmware` is explicitly set; packaging does not
flash hardware. Apps cannot grant themselves policy or accept their own license.

A deployment manifest reconciles the requested roots atomically:

```json
{"format":1,"architecture":"aarch64","packages":["editor","browser"]}
```

Use `plan deploy editor browser` first. Deployment does not change trust/policy
or refresh repositories implicitly. Runtime updates are ordinary signed packages
in the reviewed upgrade/deployment closure; no background updater is introduced.

## SDK and qualification

[SDK 1](../tools/packages/SDK.md) defines reproducible metadata, signing,
publishing, format and launch interfaces. The
[V fixtures](../tests/packages/distribution-check.v) exercise real filesystem
transactions, signatures, resolution, recovery, rollback, publisher tooling and
Software controls, registry trust/retirement, shared launchers and document
associations, plus both package target builds and desktop configurations.
Allocator fixtures check menu redraws and cached reads for zero retained storage,
and registration retirement against the standard JSON decoder's measured
one-byte EOF-marker allocation per decode under `-manualfree`.
The same allocator checks measure Software review redraws at zero retention,
and review decode/cancellation/close against that independent decoder baseline.
Service and CLI fixtures check complete dependency disclosure and rejection of
changed catalogs, policy, active state or operation/IDs before acquisition.
The [accounts guest suite](../tests/accounts/README.md) adds a `packages` scenario
for signed installation, the root-to-account handoff, literal documents,
user-owned data, publisher revocation and uninstall. Its sandbox substitute
observes the exec boundary; it does not qualify pledge/unveil or GUI runtimes.

The [production-sandbox guest check](../tests/packages/runtime-check.md) signs
native applications and an explicit runtime dependency, installs them with the
real CLI and launches through the staged native `vinix-sandbox`. It checks
private-data writes, literal document grants, denied reads outside those grants,
read-only application/runtime files, network and process permission enforcement,
and rejection of modified application/runtime payloads. While an app is running,
it upgrades the app/runtime, uninstalls them and collects garbage: the leased old
payload closure stays readable until the app exits, after which it is collected
and personal data remains. Passing retained runs include artifact hashes.

This checks the native package launch contract on both architectures. A socket
creation check does not qualify network services; the explicit native fixture
runtime does not qualify Linux, Wine, Mach-O or graphical API compatibility.
The guest root is an initramfs, so these runs do not qualify persistent-device
power-cut durability.

Publishers can now use `vinix-package pack-root` with explicit source/destination
selectors to import a verified prepared guest root. It materializes library and
directory symlinks within the captured guest namespace, rejects escapes/cycles
and special files, and emits the same canonical regular-file package inventory.
Upstream authentication, redistribution permission and the explicit runtime
dependency closure remain publisher responsibilities. License documents,
proprietary/firmware declarations and runtime updates remain visible in signed
metadata and organization policy; no upstream install scripts run.

The [dynamic Linux qualification](../tests/packages/linux-runtime-check.md)
packages a target musl loader, the static SDK runner and a shared V library as an
explicit runtime. A dynamically linked ELF application uses that loader and the
signed closure's `lib`/`usr/lib` directories through the production sandbox.
The fixture checks ordinary identity, literal arguments, private-data writes,
hidden host paths, runtime tamper refusal, missing-library diagnostics, rollback
and removal of the unused runtime with personal data preserved. It qualifies
the loader/package contract; individual upstream applications and graphics
services still require their own coverage.

The [persistent-storage recovery check](../tests/packages/persistence-check.md)
adds a real ext2 volume and abrupt QEMU SIGKILL/reboot cycles at the staged,
published and activated transaction checkpoints. It verifies the old/new active
set, partial-object/cache recovery, offline upgrade, rollback, removal,
registration and personal-file metadata. The same volume survives both boots;
the host neither restores package state nor repairs the filesystem. These
completed checkpoints passed on both targets; interruptions inside filesystem or
device operations and physical write-cache loss remain outside this fixture.

The release gate remains open: enroll a release publisher, migrate/qualify the
advertised native/Linux/Wine/Apple catalog, integrate ordinary-user graphical
sessions, qualify wider filesystem/device crash windows and measure wider
runtime sandbox profiles. Apple packaging does not provide general macOS/AppKit
compatibility; Windows/Linux packaging does not expand runtime API coverage.
