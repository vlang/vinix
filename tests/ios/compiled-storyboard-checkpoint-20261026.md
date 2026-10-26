# Compiled launch storyboard checkpoint — 2026-10-26

Implementation: `bfc6bdb15de2a5c7c79f4cbd6078dc4b89348c18`.
Inventoried source, including the guest-archive evidence fix:
`ee763d3bbf311e4fd65cfddc850143a2b7974949`. Advertising remains skipped.

Fortnite's explicit launch storyboard request now constructs the compiled
`LaunchScreen.storyboardc` controller and view graph. The bounded NIBArchive
reader validates counts, references and value ranges; construction accepts an
explicit class/property/outlet subset, checks geometry and resource containment,
and rejects cycles, aliases, unsupported graphs and partial image failures.
Snapshots own their resources, and repeated construction returns fresh objects.
This establishes this launch graph, not general Interface Builder compatibility.
`UILaunchStoryboardName` does not become `UIMainStoryboardFile`.

The five launch resources were extracted from the local Fortnite 42.30.1 IPA;
executables and frameworks came from the complete prior checkpoint below.
The real resources contain a 1024×1366 view and a 2048×1536 CgBI PNG. CgBI
channel conversion and alpha handling now feed the existing premultiplied image
path; ordinary RGBA PNG decoding has a separate regression case.

Fresh validation passes:

- ASan/UBSan parser checks, malformed archives and both actual compiled NIBs.
- Eight host build/execution steps, including normal and deterministic-hashing
  ASan/UBSan runs with real resources, independent snapshots, fresh instances
  and two drained runtime lifetimes. Leak detection is disabled.
- The guest storyboard fixture, including compiled graphs, malformed graphs,
  resource/symlink failures, partial decode cleanup, ordinary PNGs and existing
  XML/rejection cases; guest wait status is zero.
- All 14 ARM64 guest builds and all 12 guest regression fixtures. Commands,
  exit statuses and artifacts are preserved. Exploratory `host-initial`
  failures remain in the bundle and are superseded by successful `host` runs.

The unchanged Fortnite executable has SHA-256
`6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373`.
Three images load/bind, nine `+load` calls and three initializer groups return,
and application entry is reached. The compiled storyboard stop is gone; the
next observed stop is:

```text
V panic: iOS: unimplemented Objective-C method NSProcessInfo thermalState
```

Application exit is 1 (wait status 256); the diagnostic harness exits zero.
Progress remains **4/8 observable gates (50% of this checklist)**. A rendered
frame, interactive menu, login and playable match remain unverified. This
fraction does not estimate remaining engineering work or time. `--probe-no-ads`
binds SKAdNetwork to nil and changes application behavior; this is a diagnostic
run.

All 13 inline pthread-self reads are translated. The tagged 24 GiB virtual
reservation succeeds; seven headroom queries stay within the 2 GiB cgroup
limit, and final application OOM counters are zero. The sole signal fault is
the deliberate fixture, which captures all 31 ARM64 registers and restores
execution.

Complete evidence is preserved outside Git at
`/Users/alex/Library/Caches/vinix-ios/compiled-storyboard-20261026`:
1203 source records, 697 selected build-input records and 1720 manifest
records. Selected states are `probe-no-ads-241833` and `storyboard-730375`.
SHA-256 of `manifest.sha256`:

```text
3ae5be94ecc0c7664a0c41ecdef94fac56e660e7319596ae8824a028a8816619
```

Evidence seal, independent check and mutation selftest pass. Checks reject
resource differences against the preserved guest archive, missing media or
validation cases, failed statuses, changed startup/VM/memory/fault/exit
boundaries, altered logs and extra files. Historical checkers are unchanged.
The prebuilt kernel is inventoried, not rebuilt. Selected hashes do not seal
complete compiler, header or host-library closures.

Preserve the complete prior bundle at
`/Users/alex/Library/Caches/vinix-ios/application-badge-clear-20261026`, manifest
SHA-256 `a3abbb60855bf8871a1462fd2866296ed2e20cda126e882fee8a14f8ba21b454`.
Its resource investigation is superseded by the actual IPA extraction and
guest-resource overlay recorded here.

Reproduce with the frozen V compiler/environment from the
[window checkpoint](window-checkpoint-20261026.md), adding `tests/ios` to the
module path. Compile and run `compiled-storyboard-prepare.v EXTERNAL_OUT
PRIOR_BADGE_CLEAR_BUNDLE RESOURCE_APP` against an existing, external, unsealed
output directory. It builds tools, runs parser checks and builds/runs the
guest storyboard fixture. Set `VINIX_IOS_STORYBOARD_BUNDLE=OUTPUT/application`
for `notification-checks storyboard-host OUTPUT/host` and `checkpoint-run
probe OUTPUT`; run `checkpoint-run build OUTPUT` first. Run
`inventory-inputs ROOT OUTPUT SOURCE_REVISION`, then
`compiled-storyboard-evidence seal|check|selftest OUTPUT` and hash the manifest.
Exact compiler/linker commands and statuses are retained in the bundle.
