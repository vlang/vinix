# Reviewed application requirements in release builds

`stage.v --applications FILE` and `VINIX_PACKAGE_IMAGE_APPLICATIONS` select a
reviewed format-1 root manifest or format-2 deployment lock for the release's
advertised apps. Both normal staging and compiler-free preflight check that
complete set against the selected signed bundle before compiler lookup or image
publication. The report retains an exact source digest alongside the canonical
format-2 lock. The desktop/security staging path inherits the environment input,
and the native desktop image cache hashes its selection and contents.

Explicit file selection overrides the environment file. Explicit inline
`--require-app` IDs also override it. The two explicit forms cannot be combined
in either order. Missing or invalid selected files fail preflight. A format-2
input retains each version, publisher, manifest digest and minimum signed index
sequence in the staged declaration. Consumers review and authorize deployment
through the ordinary approval flow.

The new `ImageConfiguration.check_application_file` API uses the existing bounded
regular-file reader and strict deployment decoder, resolves from the captured
text once, and returns independently owned JSON. Callers free that text and close
both image plans. `application_requirements_sha256` is the digest of the exact
source bytes, including whitespace; inline/no-requirements reports use an empty
digest. See [SDK contract](../../tools/packages/SDK.md#application-requirements-files-in-desktop-builds).

## Checks and reproduction

The extended [application fixture](../../tools/packages/pkgcore/image_applications_test.v)
covers both targets, byte-identical repeated reports, exact source digests,
inline/file lock parity, changed whitespace/root ordering with stable canonical
results, and independent text after inputs/plans are removed.

It refuses malformed/incomplete/duplicate/unknown/incorrectly typed JSON,
trailing documents, wrong architectures, empty/duplicate/invalid/
oversized app sets, nonapp/missing roots and conflicting runtime requirements.
Missing files, directories, leaf links, FIFOs and oversized regular files refuse
without image writes; restoring valid input permits retry. The full signed
bundle's existing policy, payload, provenance and closure checks still apply.

The format-2 regression covers both targets. An exported lock for an older
version stages from a newer signed index with matching metadata. Changed pins,
sequence floors above the signed index, incomplete/extra closure and non-app
roots fail preflight. The plan survives source removal and requires the same
authenticated bundle capture at publication.

Real staging CLI assertions cover both hosts, literal paths, inherited file
selection, explicit-file and inline overrides of an invalid environment input,
mutual exclusion in either order, exact digest output and both check/normal
failure before compiler lookup. A valid normal gate reaches compiler admission;
the fixture intentionally supplies no target compiler. Earlier signed app-set
tests still check real reviewed offline deployment and integrity verification.
Structural app/runtime fixtures are never executed.

The [native desktop cache fixture](../../build-support/cachekey/desktop_test.v)
checks selected versus unselected/missing paths, file creation, same-size content
changes with restored timestamps, another path with identical bytes, clearing
the selection and embedded-NUL refusal. Existing source/tool/layer/configuration/
bundle cache regressions also run.

The [host driver](image-requirements-check.v) runs **30 build/run checks**:
the real stager, eleven package assertion suites, the desktop cache suite,
ASan/UBSan for the app/file fixture, real package CLI and signed CLI maintenance.
Leak detection is disabled; no whole-plan heap-retention claim is made.

The [guest controller](image-requirements-runtime-check.v) builds the real stager
and eight assertion programs. Each worker announces its start and forwards its
output to serial as it runs. Both guests must complete all fifteen report markers,
including the per-target CLI verdict, all eight processes and guest-initiated
QMP shutdown. Each receipt pins the kernel, PID 1, nine fixture binaries and raw
serial output.

```sh
v -o /tmp/image-requirements-check tests/packages/image-requirements-check.v
V=/path/to/reviewed/v /tmp/image-requirements-check /build/new-image-requirements-host

v -path '@vlib|@vmodules|.|tests/hardware-platform' \
  -o /tmp/image-requirements-runtime-check tests/packages/image-requirements-runtime-check.v
VINIX_HWTEST_TCG=1 V=/path/to/reviewed/v VFLAGS=-nocache \
  /tmp/image-requirements-runtime-check --arch aarch64 --kernel /build/aarch64-kernel \
  --state-dir /build/new-image-requirements-arm
```

Repeat for `x86_64` with its matching kernel and a fresh state directory. The
controller requires explicit TCG opt-in and checked inputs; list mode creates no
guest. Cross-toolchain prerequisites follow the [hardware controller](../hardware-platform/README.md).

## Format-2 staging follow-up

The application fixture passed normally and under ASan/UBSan with leak
detection disabled. Both runs exercised the real host stager. A separate run
built the real Hello, Counter and
Memo packages for AArch64 and x86-64, signed them with a disposable test
publisher, and exported one reviewed lock per target. Normal staging built the
target package tools and wrote an `applications.json` byte-identical to each
reviewed lock. Both staged roots were free of consumer package state.

The source patch against `25b0de45b`, host logs, native SDK build receipt,
preflight receipts and staged tool/declaration checksums are retained in
`~/.local/state/vinix/section14-resume-CUyEUnSR`. The SHA-256 of
`image-lock-stage.sha256` is
`33be27238193aa86bc81745f941f8987225cc41803be3902ec2a7393ab4d7707`.

In the guest run of that source snapshot, AArch64 passed the full requirements
suite with guest-initiated shutdown in 64.1 seconds. The x86-64 guest started
the suite and reached the 360-second deadline before the first worker verdict.
The boot logs and checksums are in `~/.local/state/vinix/r14-g-d9QK4S`, under
`aarch64` and `x86_64`. Each run reused the recorded cross-built fixtures and
the maintained scenario's verdicts with a short QMP socket path.

After tightening capture identity checks and retiring the resolver buffers
without an extra compiler-generated allocation, the final host fixture passed
again normally and under ASan/UBSan. Compiler-free preflight preserved and
re-exported both staged SDK declarations byte for byte. The tracked complete
AArch64 staging case retained 5,200 bytes in 44 records on both the original
source and the final source with this V compiler. The strict zero-retention
check therefore still fails on this baseline. The same state directory holds
`image-lock-final.sha256`, whose SHA-256 is
`440778bf079fc5c1df9ab283083f20c0c78fb16c7e35640bf7ac0883d743608d`.

## Per-target release staging

The real staging CLI passed for AArch64 and x86-64 with format-2 locks. The
fixture tested each target override, generic fallback, explicit option
precedence and refusal of invalid selected paths. The application assertions
passed under ASan/UBSan with leak detection disabled. The cache assertions
checked that changes to the selected path, bytes or leaf type invalidate the
AArch64 image keys and that x86-64 settings leave those keys unchanged.

A normal stage for each target used one environment containing both reviewed
configurations, separate repository paths and both reviewed locks. A disposable
test publisher signed the repository.
Each output retained its exact lock and signed repository bytes, contained
three static target tools and left consumer package state empty. These runs
staged into small image roots. Paired desktop ISO build and boot were outside
this run.

The source patch against `ab420ef6f`, host logs, preflight reports and staged
artifact hashes are in `~/.local/state/vinix/r14-target-1CoopZ`. The SHA-256 of
`checks.sha256` is
`497c515bf92b66ed75b64c94841fbff2531324da1fa486962cd76697c2c04b8b`.

All **30 host checks passed** at `da695e7ee`. The signed maintenance fixture
uses the host `mode_t` width when creating FIFO refusal cases. The same state
directory contains `qualification-final/qualification.json` and the complete
host logs. The SHA-256 of `qualification-host.sha256` is
`5d533b577885c0eac0f95cfe37137f3ce531f6d667cc009b152cba49b26f247b`.

The AArch64 guest at `8f9b09ad2` completed all eight fixture processes in
103.3 seconds and initiated QMP shutdown. The x86-64 guest at `da695e7ee`
booted and reached test startup. Its first worker emitted no verdict before
the 180-second deadline. Both used the retained release kernels from
`cf4e76718`. The same state directory contains the raw serial and QMP logs,
fixture binaries and the AArch64 receipt. The SHA-256 of
`qualification-guest.sha256` is
`809c2dca6d46e2829c5e327c39cda9322e60516ddba2833a79a1307b8e80552a`.

## Paired guest qualification

Two replays of the retained x86-64 image completed all eight workers with one
and two virtual CPUs. Fresh builds from `7bf207117` plus the streaming runner
change then passed the maintained suite on the same `cf4e76718` release kernels.
AArch64 completed in **124.2 seconds** and x86-64 in **132.8 seconds** with a
300-second x86-64 deadline. Both runs recorded every worker start and verdict,
the target-specific CLI verdict and guest-initiated QMP shutdown.

The runner source patch, retained image replay logs, new guest inputs, receipts
and serial/QMP logs are in `~/.local/state/vinix/r14-x86-3wLLds`. The SHA-256
of `qualification.sha256` is
`b9ab2f87ccf4f49d74550f6e82e6e392726bf093ed2936aa769c358d49652c41`.

## Paired desktop ISO qualification

One local paired `deploy-iso.sh --no-publish --no-test` run built both desktop
ISOs from `7c10afe81`, using prepared userland layers and the frozen November
23 compiler and UI2 inputs. A disposable publisher signed separate repository
indexes for the two targets. The x86-64 image selected sequence 3 and the
AArch64 image selected sequence 4. The configuration digest, reviewed format-2
lock, signed index, signature and payload bytes matched their selected inputs
when extracted from each finished ISO. Each extracted bundle passed preflight.

All eight QEMU checks passed with `test-iso.sh` from `be38c13fa`. x86-64 passed
default and BIOS live boots, UEFI installation, and UEFI and BIOS disk-only
boots. AArch64 passed VirtIO installation, a disk-only boot and a USB input
boot. Each scenario checked keyboard and pointer input. Both installations
passed GPT and VJFS layout validation. The first x86-64 run completed its boot
checks and lost its summary when the runner changed during execution. The
recorded x86-64 verdicts come from the fixed-revision rerun.

The runner's `--keep-qemu-disks` option retained the raw installation disks.
The V disk exporter admitted clean snapshots of their root partitions for
read-only inspection after disk-only boot. On both disks the configuration,
reviewed lock and complete repository matched the ISO bytes and passed
preflight again. Each lock was a single-link regular file owned by root with
mode 0644. The raw disk hashes remained identical across inspection.

Both ISOs, retained installation disks, extracted metadata, serial logs,
screenshots and build receipts are in `~/.local/state/vinix/r14-iso-buLjXi`.
The SHA-256 of `qualification.sha256` is
`9601c5ee5e241a8a60894cb5c950583a5702f022df364ed1593c38ab47f73cf8`.

## Release ISO package receipts

At `2292c4e8b`, `deploy-iso.sh` preflights the effective package selection for
each requested target before building. It verifies the package configuration,
complete signed offline bundles and application declaration read from the
finished ISO. A mismatch stops the release before boot tests or publishing.
The verified `vinix-packages-ARCH.json` files bind the ISO SHA-256 to the package
configuration and deployment hashes, publisher keys and signed indexes, and
selected application IDs. The release notes link them and `SHA256SUMS` covers
them along with the ISOs.

The two retained ISOs above passed with both the current V compiler and the
frozen release compiler. Both produced identical receipt bytes and retained
the expected AArch64 sequence 4 and x86-64 sequence 3. The maintained V controls
repacked an admitted package tree into small ISO fixtures. The matching ISO
passed. Changed configuration, missing declaration, damaged payload, invalid
signature, wrong preflight sequence, package-file symlink and duplicate member
each refused. A configuration-only ISO also passed.

An isolated `deploy-iso.sh --no-test --no-publish` replay used the retained
ISO as its build output. The matching target passed and its receipt appeared in
the release notes and checksum list. A valid per-target selection took
precedence over a missing generic file. Substituting the other target's ISO
stopped the driver before writing a receipt or release notes. The no-selection
replay produced its ordinary ISO checksum and notes.

To replay the controls, build `build-support/isoboot/package-receipt.v` and
`tests/packages/iso-package-receipt-check.v` with `-backend c -prod -cc cc` and
`-path '@vlib|@vmodules|.|build-support|tools/accounts'`. Run `package-receipt
plan ARCH` with the same environment used for the release, save its stdout to
`PLAN.json`, and then run `package-receipt verify ISO PLAN.json`. Run
`iso-package-receipt-check RECEIPT_TOOL STAGED_PACKAGE_ROOT PLAN.json NEW_WORK`
with one signed repository and a matching deployment in the staged root.

The receipts, controls, driver logs and input digests are in
`~/.local/state/vinix/r14-iso-package-receipts-L7k4Lo`. The stored run roots
matched their archive's bytes, modes, types and links. The SHA-256 of
`qualification.sha256` is
`7cf8c8296f4edadc508557179f0c26ea0768d88aa620bbf7fe0f346a0c8cde6a`.

## Qualification, 2026-10-16

All **30 host checks passed**, including the desktop cache assertions, the
extended app/file fixture under ASan/UBSan and signed CLI maintenance. Four
controller list/input/existing-directory guards passed. Fresh guests completed
all eight assertion programs and all thirteen report markers, then initiated
QMP shutdown: **AArch64 49.5 seconds**, **x86-64 46.9 seconds**, within the
180-second deadline. Both kernels match the installed-system Software receipts.

- [Host receipt](results/2026-10-16/image-requirements-host.json),
  [30 checks](results/2026-10-16/image-requirements-host.txt),
  [file/CLI assertions](results/2026-10-16/image-requirements-core.txt),
  [cache](results/2026-10-16/image-requirements-cache.txt),
  [sanitizer](results/2026-10-16/image-requirements-asan.txt) and
  [signed CLI regression](results/2026-10-16/image-requirements-cli.txt).
- [AArch64 receipt](results/2026-10-16/image-requirements-aarch64.json),
  [serial](results/2026-10-16/image-requirements-aarch64.serial.txt) and
  [QMP](results/2026-10-16/image-requirements-aarch64.qmp.txt).
- [x86-64 receipt](results/2026-10-16/image-requirements-x86_64.json),
  [serial](results/2026-10-16/image-requirements-x86_64.serial.txt) and
  [QMP](results/2026-10-16/image-requirements-x86_64.qmp.txt).
- [Source/toolchain/artifact ledger](results/2026-10-16/image-requirements-toolchain.json)
  and [V evidence verifier](results/2026-10-16/image-requirements-retain.v).

The verifier checks all twelve artifacts in each target receipt, exact app/file/
input/cache markers, successful processes, shutdown and unchanged kernel hashes.
The ledger includes package and cache sources, generated guest C, host/target
binaries, logs and helpers. Product/test sources were unchanged during the final
host and guest runs; documentation was finalized afterward.

This increment qualifies selected requirements, source provenance, normal/check
release gates and cache invalidation. It does not rebuild a full desktop image,
select a production publisher, migrate the legacy app catalog, or qualify full
graphical login/presentation, broader runtimes or device/crash behavior. Those
remain separate roadmap 14 work. No kernel code changes are involved.
