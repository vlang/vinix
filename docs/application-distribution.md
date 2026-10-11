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
refresh, update-all, rollback, progress and recent failure output. A running
mutation prevents normal window close. Mutations require administrator access;
there is no setuid service or automatic privilege escalation.

`vinix-package run ID [ABSOLUTE_DOCUMENT...]` executes as an ordinary user through
`vinix-sandbox`, failing closed if confinement is unavailable. Apps have private
data, temporary directories and Wine prefixes. Package/runtime paths come from
one immutable generation, with no implicit host Wine/Linux/Apple installation.
The environment is explicit and arguments are literal. `files` authorizes only
supplied documents. Display/audio paths are granted only when declared. Today's
root desktop cannot launch through this command. See
[the sandbox's enforcement boundaries](../tools/sandbox/README.md).

Non-data/non-runtime packages get `.desktop` launchers with MIME types, package
ID and runtime provenance. `/usr/share/applications/vinix-packages` points through
activation, so registration removal/rollback follows package state. Installation
preserves user defaults. Native Start/Open With still uses built-in factories;
consuming these dynamic XDG records remains release work. Ordinary sessions can
execute packages using the CLI or an XDG-aware launcher.

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
Software controls, plus both package target builds and desktop configurations.

The release gate remains open: enroll a release publisher, migrate/qualify the
advertised native/Linux/Wine/Apple catalog, integrate ordinary-session and dynamic
launchers/associations, qualify guest power-cut/reboot behavior and measure wider
runtime sandbox profiles. Apple packaging does not provide general macOS/AppKit
compatibility; Windows/Linux packaging does not expand runtime API coverage.
