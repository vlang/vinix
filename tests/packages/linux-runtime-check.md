# Dynamic Linux package qualification

The V controller builds a target musl dynamic executable and a shared V library,
the static SDK Linux runner, and the production native sandbox. It checks that
the executable is a PIE (ET_DYN) with both PT_INTERP and PT_DYNAMIC before staging.
The guest imports the prepared app/runtime roots with the actual `pack-root` CLI, creates
a throwaway signing key, authenticates/enrolls a local repository through the CLI
and installs the Linux app.
The runtime includes upstream copyright and Vinix licensing documents.

```sh
V=/path/to/v v -path '@vlib|@vmodules|tests/hardware-platform' run tests/packages/linux-runtime-check.v \
  --arch aarch64 --kernel /build/arm/kernel/bin/vinix \
  --state-dir /tmp/package-linux-arm
V=/path/to/v v -path '@vlib|@vmodules|tests/hardware-platform' run tests/packages/linux-runtime-check.v \
  --arch x86_64 --kernel /build/x86/kernel/bin/vinix \
  --state-dir /tmp/package-linux-x86
```

Use a current kernel with the account-session and sandbox interfaces. The usual
[hardware controller options/toolchains](../hardware-platform/README.md) apply.
The payload builder additionally needs the matching `ARCH-linux-musl-gcc` with
dynamic `libc.so`; `VINIX_MUSL_CC_AARCH64` and `VINIX_MUSL_CC_X86_64` can select
compiler executable paths. Provide the corresponding musl copyright file with
`VINIX_MUSL_COPYRIGHT` when it is not at `build-support/musl/COPYRIGHT`.
No network repository, desktop, release credential or shell is needed. The
controller captures the kernel before building, and validates all fixture ELF
targets before embedding them. State directories must be new or empty.

The real `vinix-session` handoff and `vinix-sandbox` execute the signed runtime's
runner, which execs the signed musl loader. Its `--library-path` resolves the
external fixture library in the runtime's `usr/lib`; the executable's ordinary
host PT_INTERP path is bypassed. Guest assertions cover:

- Absolute guest and relative library symlinks becoming regular signed files.
- The runtime being installed as a dependency, with no extra requested root.
- Read-only full-closure review exposing the runtime and publisher, followed by
  fingerprint-bound install. Reusing the pre-install review fails as stale.
- A shared-library call returning 23, UID/EUID 1000 and zero supplementary groups.
- Literal arguments containing spaces, semicolons and a dollar sign.
- Private-data writes as the user; host libraries, the package tool and unrelated
  same-user data hidden by the production sandbox.
- Runtime library tampering being refused before execution; restoring the signed
  bytes permits launch again.
- Reviewed upgrade to a signed runtime without the required shared library producing
  the loader's library-name diagnostic and status 127; reviewed rollback restoring launch.
- That runtime-only update appearing in `view` and `--json updates` with the
  resolved version, publisher and action while the application's version stays
  unchanged. After the reviewed upgrade, Updates returns an empty success.
- Reviewed uninstall removing both the app and unused runtime while preserving user data.
- Repository revocation denying launches/rollback while reviewed uninstall remains
  usable, and an empty refresh retaining the sequence floor. Re-enrollment with
  an older signed index fails; re-enrollment with the latest exact index succeeds
  without changing installed state or personal data.
- Read-only signed repository enrollment review, fingerprint-bound trust apply,
  refusal of reused/stale trust confirmation, and reviewed revocation through
  the production CLI. The `PACKAGE TRUST REVIEW` marker covers this flow.
- Busy-writer diagnostics for maintenance, state, verification and launch before
  the service decodes a deliberately corrupt configuration. A policy change makes
  the pre-install review stale before any object acquisition; restoring the exact
  policy permits that review. `--json verify` refuses tampered runtime bytes.
  The `PACKAGE CONFIGURATION` marker covers these assertions.
- Read-only organization policy review exposing a blocked runtime on both its
  own row and the dependent app, ordinary-user apply denial, atomic policy-only
  publication, blocked launch and stale fingerprint refusal. A reviewed restore
  retains trust/account/installed state and permits the same app to launch again.
  The `PACKAGE ORGANIZATION` marker covers this flow.
- Failed offline mirror acquisition leaving no final repository, cleanup of its
  private staging tree, and retry using verified cached app bytes after the
  upstream app object is removed. The complete signed app/runtime mirror can be
  read under ordinary credentials and installed/verified in a clean offline
  store; exporting over the same destination is refused. `PACKAGE OFFLINE`
  covers these assertions.
- Complete `publish-release` output matching the canonical workspace index and
  signature, excluding private publisher state/manifests, refusing changed
  metadata at the same sequence, and installing/verifying its Linux/runtime
  closure in a clean offline store. `PACKAGE RELEASE` covers this flow.

A passing retained run writes `qualification.json` with architecture, SDK,
scenario and hashes/lengths for kernel, sandbox, dynamic payload, shared library,
musl loader, static runner, service, session runner and serial log. Keep the log
alongside the receipt; failure cannot produce a passing receipt. Retained images
contain fixture keys only.

The controller also builds a static stdout producer and the package core's HTTPS
output runner for each target. The guest runs the actual bounded pipe consumer,
including resume, range refusal, interrupted recovery, captured destination
checks, close-on-exec and child/descriptor retirement under a 32-descriptor limit.
`PACKAGE PIPE OUTPUT` is required; both binaries are pinned in the current receipt.
This exercises the target process/pipe/file boundary. Actual certificate and HTTP
behavior is qualified separately with host curl and the loopback TLS server in
[HTTPS output qualification](https-output-check.md).

The current controller also stages the signing-seed CLI probe. Both target
guests require `PACKAGE SIGNING SEED`, checking private ownership, bounded input,
hard-link/special-file refusal and reproducible retry through both publishing
commands. Its executable is included in the qualification receipt. Host tests
add deterministic replacements and a coupled signing/exclusion capture; see
[signing seed qualification](signing-seed-check.md).

The scenario passed on both targets on 2026-10-12 using an isolated build of
committed kernel revision `7ac619bd`. Retained receipts and complete serial logs:
[AArch64 receipt](results/2026-10-12/linux-aarch64.json),
[AArch64 serial](results/2026-10-12/linux-aarch64.serial.txt),
[x86_64 receipt](results/2026-10-12/linux-x86_64.json),
[x86_64 serial](results/2026-10-12/linux-x86_64.serial.txt).
Guest images were retained in the corresponding host state directories during
qualification. The x86_64 build used the V sampler generator directly, bypassing
the stale Python sampler recipe in that kernel revision.

The fingerprint-bound review flow also passed on both targets on 2026-10-12
with those same kernel artifacts:
[AArch64 review receipt](results/2026-10-12/review-aarch64.json),
[AArch64 serial](results/2026-10-12/review-aarch64.serial.txt),
[x86_64 review receipt](results/2026-10-12/review-x86_64.json),
[x86_64 serial](results/2026-10-12/review-x86_64.serial.txt).
Their `PACKAGE REVIEW` marker covers full runtime/publisher disclosure and stale
confirmation refusal; maintenance uses reviewed upgrade, rollback and uninstall.

The repository administration flow passed on both targets on 2026-10-12 with
those same kernel artifacts:
[AArch64 repository receipt](results/2026-10-12/repositories-aarch64.json),
[AArch64 serial](results/2026-10-12/repositories-aarch64.serial.txt),
[x86_64 repository receipt](results/2026-10-12/repositories-x86_64.json),
[x86_64 serial](results/2026-10-12/repositories-x86_64.serial.txt).
Their `PACKAGE REPOSITORY` marker covers authenticated enrollment, revocation,
retained replay floors after an empty refresh and successful re-enrollment.
These guests use initramfs; metadata publication interruption is simulated by
host fixtures, rather than tested as a physical power cut in these runs.

The resolved runtime-update view passed on both targets on 2026-10-12:
[AArch64 updates receipt](results/2026-10-12/updates-aarch64.json),
[AArch64 serial](results/2026-10-12/updates-aarch64.serial.txt),
[x86_64 updates receipt](results/2026-10-12/updates-x86_64.json),
[x86_64 serial](results/2026-10-12/updates-x86_64.serial.txt).
The `PACKAGE UPDATES` marker checks the service view/CLI Updates before and after
the reviewed runtime-only upgrade. Kernels were rebuilt from revision `7ac619bd`
in isolated worktrees with LLVM and `KERNEL_LINK_RANDOMIZE=0`; the x86_64 sampler
used the V generator directly. These are newly built artifacts, with hashes in
the receipts. Exact kernels are cached locally under
`build/package-update-qualification/kernels/ARCH-7ac619bd` for reruns.
Headless UI fixtures separately check per-row complete upgrade review, new/removed
dependency presentation, dependency-root guards, blocked-plan diagnostics and
zero retained redraw allocations. View reload and blocked-status measurements
match the JSON decoder's independent EOF allocation baseline.

This qualifies this musl loader/package tuple and its stated assertions. It does
not qualify arbitrary Linux libraries, upstream apps, glibc, graphics/audio
brokers, network traffic, Wine or Apple API coverage. Use the separate
[native enforcement](runtime-check.md) and [persistent recovery](persistence-check.md)
checks for generation leases and ext2 transaction crash checkpoints.

Reviewed repository trust changes passed on both targets on 2026-10-12 using
those cached kernel artifacts:
[AArch64 trust-review receipt](results/2026-10-12/repository-manager-aarch64.json),
[AArch64 serial](results/2026-10-12/repository-manager-aarch64.serial.txt),
[x86_64 trust-review receipt](results/2026-10-12/repository-manager-x86_64.json),
[x86_64 serial](results/2026-10-12/repository-manager-x86_64.serial.txt).
`PACKAGE TRUST REVIEW` covers read-only authenticated metadata disclosure,
fingerprint-bound enrollment, stale-confirmation refusal and reviewed revocation.
The headless Software fixture separately covers GUI editing, frozen confirmation,
long URL review, cancellation, invalid/stale responses and saved-trust/failed-refresh
diagnostics. Form/review redraws retained zero allocations; status/review reloads
matched the JSON decoder baseline after retirement. These are CLI/host-UI checks;
the ordinary-user graphical session and public display broker remain release gates.

Configuration-lock and JSON integrity checks passed on both targets on 2026-10-12
using those same cached kernels:
[AArch64 configuration receipt](results/2026-10-12/configuration-aarch64.json),
[AArch64 serial](results/2026-10-12/configuration-aarch64.serial.txt),
[x86_64 configuration receipt](results/2026-10-12/configuration-x86_64.json),
[x86_64 serial](results/2026-10-12/configuration-x86_64.serial.txt).
`PACKAGE CONFIGURATION` covers writer exclusion before configuration decoding,
busy launch refusal, changed-policy stale confirmation before acquisition and
integrity checks with JSON output. The host service fixture also covers client
reuse after trust/policy changes and confirms fresh-image status stays read-only.

Organization policy review/apply and restoration passed on both targets on
2026-10-12 with those cached kernels:
[AArch64 organization receipt](results/2026-10-12/organization-aarch64.json),
[AArch64 serial](results/2026-10-12/organization-aarch64.serial.txt),
[x86_64 organization receipt](results/2026-10-12/organization-x86_64.json),
[x86_64 serial](results/2026-10-12/organization-x86_64.serial.txt).
`PACKAGE ORGANIZATION` covers dependency impact, ordinary-user denial, policy-only
publication, blocked launch, stale confirmation and reviewed restoration. Host
fixtures additionally cover explicit license/firmware acceptance, strict input
validation, cyclic dependencies and policy removal/deployment behavior.

The first AArch64 run failed after the organization-policy flow when the explicit
musl loader's randomized base was `0x400000`, overlapping the original probe's
fixed-address ELF image. This produced `Not a valid dynamic program` instead of
the missing-library diagnostic:
[failure artifact record](results/2026-10-12/organization-aarch64-fixed-address-failure.json),
[complete failed serial log](results/2026-10-12/organization-aarch64-fixed-address-failure.serial.txt).
It produced no passing receipt. The controller now builds the probe with
`-fPIE -pie` and requires ET_DYN before staging; the retained organization runs
use that PIE payload. Fixed-address executables require separate address-layout
qualification with this explicit-loader path. These runs do not fix or qualify
all kernel ASLR/address-layout combinations.

Atomic offline mirror export and clean offline app/runtime installation passed
on both targets on 2026-10-12 using those same cached kernels:
[AArch64 offline receipt](results/2026-10-12/offline-aarch64.json),
[AArch64 serial](results/2026-10-12/offline-aarch64.serial.txt),
[x86_64 offline receipt](results/2026-10-12/offline-x86_64.json),
[x86_64 serial](results/2026-10-12/offline-x86_64.serial.txt).
The host fixture also interrupts the exporter before publication, verifies the
destination is absent, removes upstream objects, and completes a cache-only retry.
It checks corruption and a directory created immediately before the exclusive
rename. These offline export runs use an initramfs; persistent-device power-cut
durability of removable media still needs separate qualification.

Complete publisher release export and clean offline installation passed on both
targets on 2026-10-12 with those cached kernels:
[AArch64 release receipt](results/2026-10-12/release-aarch64.json),
[AArch64 serial](results/2026-10-12/release-aarch64.serial.txt),
[x86_64 release receipt](results/2026-10-12/release-x86_64.json),
[x86_64 serial](results/2026-10-12/release-x86_64.serial.txt).
`PACKAGE RELEASE` checks reproducible canonical metadata, complete runtime objects,
exclusion of private publisher files, sequence-equivocation refusal and consumer
installation/verification. Host fixtures additionally check every advertised
version/architecture, copied-object corruption, space preflight, existing/raced
destinations, writer locks and abrupt exporter exit after durable sequence
reservation followed by exact retry. Signing metadata remains private until that
reservation. These runs do not qualify publisher-disk power-cut durability.

Qualification used an isolated V/library snapshot at `826e96f56c`; the
[compiler identity record](results/2026-10-12/release-toolchain.json) retains its
binary length/hash and complete source revision. The full host/UI/target check
used `--direct-tests --cross --desktop`, compiling and running every existing
assertion runner directly with declaration pruning disabled. The separately
linked launcher C fixture disables the compiler crash handler; assertions and
nonzero process exits still fail qualification. The newer shared compiler failed
before guest boot with omitted Ed25519 type declarations and process-launch C
headers. Cached test-tool/run modes also failed. Those attempts produced no
passing guest receipts. The
isolated snapshot avoids changing another session's toolchain and does not claim
that the newer compiler regressions are fixed.

Reviewed deployment locks passed on both targets on 2026-10-12 using the same
cached kernels and isolated compiler snapshot:
[AArch64 deployment receipt](results/2026-10-12/deployment-aarch64.json),
[AArch64 serial](results/2026-10-12/deployment-aarch64.serial.txt),
[x86_64 deployment receipt](results/2026-10-12/deployment-x86_64.json),
[x86_64 serial](results/2026-10-12/deployment-x86_64.serial.txt).
`PACKAGE DEPLOYMENT` covers exact application/runtime metadata and publisher
floors, clean offline reproduction from a relocated signed mirror, stale apply
refusal, ordinary-user denial, retention of an approved runtime after a signed
update, reviewed downgrade and normal generation rollback. All nine recorded
artifact hashes/sizes were checked against staged files before retaining receipts.
Host fixtures additionally cover same-version metadata substitution, missing or
extraneous closure records, policy enforcement, canonical document ordering,
unknown/duplicate keys (including escaped keys), type/range limits and rejection
before acquisition or abandoned-stage cleanup. File-based and generic deployment
review fingerprints are deliberately separate.

The host/UI/target driver uses `--direct-tests --cross --desktop`. Direct mode
retains declarations in fixture executables as well as assertion runners; the
first CLI fixture compilation omitted imported session/Ed25519 types under
pruning and produced no successful full-host result. All fourteen assertion
runners and CLI checks subsequently passed. Shared generated UI directories
were unavailable, so the remaining integration checks use
private assets generated by the V workflow builder. `VINIX_PACKAGE_TEST_UI2`
selects their module parent; `VINIX_PACKAGE_TEST_DESKTOP` selects the generated
desktop asset directory, with current desktop sources still overlaid. These are
generated from the preferred sibling ui2 checkout; the older `third_party/ui2`
snapshot lacked the current desktop text-field interfaces. UI/desktop checks use
that matching checkout; the already passing package cross-builds are retained.
The standalone launcher fixture sets `CPATH` to the repository's `desktop`
directory for the concurrently added GPU ABI header. The
[qualification identity record](results/2026-10-12/deployment-toolchain.json)
retains the compiler, source and individual qualification-log hashes.
These guest checks are initramfs/sandbox qualification runs. The ext2 crash suite
qualifies the shared transaction engine
separately; locked deployment through a graphical administration flow and
persistent-device power-cut behavior remain separate release gates.

Structured operation progress and verification of staged copies passed on both
targets on 2026-10-13 using the same cached kernels and pinned compiler:
[AArch64 progress receipt](results/2026-10-13/progress-aarch64.json),
[AArch64 serial](results/2026-10-13/progress-aarch64.serial.txt),
[x86_64 progress receipt](results/2026-10-13/progress-x86_64.json),
[x86_64 serial](results/2026-10-13/progress-x86_64.serial.txt).
`PACKAGE PROGRESS` checks bounded byte counters, download/copy/verification
phases, completion after activation and the real signed offline app/runtime
closure. All nine artifact hashes and lengths were checked before retention.
Host fixtures additionally cover resumed partial bytes, a failing child with
retained data, killing/reaping an oversized transfer child, staged-copy corruption
before publication, stale review before acquisition, strict protocol bounds and
fragmented GUI pipe frames. The controlled child tests exercise transfer
monitoring without replacing curl or claiming a live HTTPS server qualification.
The [compiler/source record](results/2026-10-13/progress-toolchain.json) retains
the pinned toolchain identity and qualification-log/source hashes.

The UI fixture verifies an observable progress bar while a worker runs, bounded
incomplete lines, ignored invalid records, useful failure diagnostics and reset
on worker replacement. Allocator checks cover repeated progress redraws and
decoded-event retirement. Qualification uses private generated UI assets and
the documented compiler/include-path settings. A host build first hit exhausted
disk space; retained earlier package-run artifacts were cleaned without changing
source or evidence. These tests qualify progress and the shared package engine;
graphical session/display-broker and application catalog release gates remain.
