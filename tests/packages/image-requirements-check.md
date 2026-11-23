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

### Reviewed plans and release handoff

At `72780fea3`, `--package-review=DIR` requires an exact plan for every
requested target. Swapped architectures, a missing second target plan and
an unconfigured target all stopped the driver before checkout. Separate valid
plans for amd64 and arm64 passed with the signed mixed catalog.

The driver formed `SHA256SUMS` from the private verified receipts. A separate
checksum reader verified both ISO files and both public receipts. Changes to
the ISO or to the public receipt during the boot-test step blocked publication
of the checksum list. Changing the checksum list at the confirmation prompt
blocked the upload. A clean handoff passed the ISO, checksum list and receipt
to a local GitHub stub. The legacy run produced its ordinary ISO checksum.

The replay supplied fixture ISOs and stubbed the build, boot and upload steps.
The verifier read the actual package files from the fixture ISOs, including
the signed mixed bundle and its payloads. The eight ISO receipt controls and
the package repository fixture passed.

The paired fixture ISOs, plans, receipts and logs are in
`~/.local/state/vinix/r14-release-handoff-6QVM7E`. The SHA-256 of
`qualification.sha256` is
`2df1f66944c0dcd98b18350059c514b480b47fe72435a1d39ec384f4a220e293`.

### Complete release asset checksums

At `27674e1a3`, the driver records the image, bundle, sidecar and receipt digests
before boot testing. The manifest retains the digests supplied by the package
receipt verifier and checks each X11 and iOS checksum sidecar against its
payload. It checks every asset again after boot testing and at upload handoff,
alongside an exact comparison of the public `SHA256SUMS` and its private copy.

The real driver passed eight fixture scenarios with local build, boot and
GitHub stubs. The paired releases with and without package inputs had exact
checksum and upload lists. A bad build-time sidecar stopped before boot testing.
Changes to the X11 archive, to the iOS payload and its regenerated sidecar, or
to a package receipt during the boot step stopped the release. Changes to a
sidecar or the public checksum list at handoff also stopped it before upload.
The amd64 build-only path emitted all three asset checksums. The manifest
helper passed an ASan/UBSan round trip and refused missing verified assets.

Build and run the fixture driver with the matching case directories generated
by `iso-package-receipt-check` for each architecture:

```sh
v -backend c -prod -cc cc -o /tmp/iso-release-assets-check \
  tests/packages/iso-release-assets-check.v
/tmp/iso-release-assets-check "$PWD" /path/to/new-state \
  /path/to/x86_64-controls/match /path/to/aarch64-controls/match
```

Source, fixture inputs, checksums, upload argument logs and refusal diagnostics
are archived in `~/.local/state/vinix/r14-release-asset-manifest-Pv8dR8/qualification.tar.gz`.
Its SHA-256 is `514f7ddf2779eb023090f46382148abc81e57443cf6ebdc6a7986104298ebebf`.
All 129 entries in the extracted `qualification.sha256` passed.

### Verified upload staging

At `6ac3d03d6`, the driver copies release assets to a private staging
directory and checks the copied bytes against the recorded digests before
invoking GitHub. It supplies the recorded checksum list and generated notes
from that directory and removes the directory on exit.

All ten release-driver cases passed using local build, boot and GitHub stubs.
The new case overwrote the public amd64 ISO, X11 bundle, checksum list and
release notes in place after the uploader started. The uploader still read
every verified asset and the original notes and checksum list. The existing
refusals and the single-architecture build-only path passed. The staging
helper also passed ASan/UBSan checks for a verified copy, a source digest
mismatch and refusal to reuse an existing staging directory.

The paired fixture inputs, run logs, observed upload digests and source
revision are in
`~/.local/state/vinix/r14-release-upload-copy-ohWRaq/qualification.tar.gz`.
Its SHA-256 is `7b5559ee4e51c0cd0ba00f737561ebdd688b5e802f02b66c6209046f2fc7ce54`.
All 163 entries in the extracted `qualification.sha256` passed.

### Boot tests and upload share the staged ISOs

At `e805a0c99`, the driver verifies private, read-only copies before boot
testing and gives the same ISO paths to the boot runner and uploader. The
driver rechecks the staged bytes after the boot run. A build with
`--no-publish` also tests private copies. With `--no-test`, staging happens
at publication.

All thirteen release-driver fixtures passed with local build, boot and GitHub
stubs. The new regression overwrites the public amd64 ISO while the boot stub
reads the two ISO inputs, then restores it before the stub returns. The
previous driver at `d07366ed9` handed different bytes to boot and upload.
The new driver handed both consumers the same staged paths and digests.
Replacing a staged ISO before the boot stub returns stops publication.
The explicit `--no-test` path also passed.

The helper passed ASan/UBSan staging, source modification and digest refusal
checks. QEMU attached the staged files as read-only optical media on x86-64
and AArch64 with guest execution paused.

Paired fixtures, baseline and fixed observations, and source and toolchain
identities are in
`~/.local/state/vinix/r14-release-tested-isos-LZf6r1/qualification.tar.gz`.
Its SHA-256 is `0fcdefaf6bd8967fcb1903811d4acebe9432ed823ad0951b359e11b400b9f6cf`.
All 244 entries in the extracted `qualification.sha256` passed.

### Release receipts use the staged ISOs

At `08a2c8409`, the release driver captures the assets before package
verification. The package verifier hashes and extracts the same private
ISO that the boot runner and uploader receive. Standalone
`package-receipt verify` makes its own read-only ISO copy in its temporary
workspace and removes the copy on exit.

All fifteen release-driver fixtures passed. The build, boot and GitHub
steps used local stubs, and the extraction wrapper invoked real `xorriso`.
While the wrapper ran, it temporarily changed the public amd64 ISO. The
previous driver at `a05b8c454` tried to extract that file and failed. The
updated driver extracted from the same staged ISO that it handed to the
boot and upload steps. A package-bearing release with `--no-test` passed
with the same receipt and upload paths.

All 33 receipt controls passed for each architecture in production and
ASan/UBSan builds. Standalone checks on both builds and architectures
also retained byte-identical receipts when the public ISO changed during
extraction, cleaned up the private copies and refused writable inputs to
`verify-staged`.

The paired inputs, source revisions, complete controls and release logs
are in `~/.local/state/vinix/r14-release-receipt-capture-uonSbh/qualification.tar.gz`.
Its SHA-256 is `82b815920dbd0edc6a22cf0367549dd6a3bc14e0de59774b2e613593e013ced3`.
All 1,366 entries in the extracted `qualification.sha256` passed.

### Shared release workspace lock

At `344350575`, the driver takes an exclusive directory lock on
`build-release/work` before tag selection, source checkout or tag output
creation. The driver retains the lock through the upload or build-only exit.

All 16 release-driver fixtures passed using local build, boot and GitHub stubs.
The prior driver at `428a55e54` let a competing release reuse the source
worktree and finish writing its checksums while the first run was still
preparing dependencies. The updated driver refused contenders at dependency
preparation and upload, before either contender created its tag output. A
retry after the first release finished produced its checksums.

On the HFS+ test volume, ASan/UBSan checks confirmed exclusion on one
directory, independent locks on separate workspaces, successful unlock and
refusal when the descriptor was missing. An APFS check confirmed that another
process could acquire the lock after the only holder was killed.

The fixtures, baseline and updated run logs, and source revisions are in
`~/.local/state/vinix/r14-release-workspace-lock-tMtPt9/qualification.tar.gz`.
Its SHA-256 is `bb089a99d910cabff72d37fbf0fb261ee065d46416e1df3569d934d3accf0698`.
All 291 entries in the extracted `qualification.sha256` passed.

### GitHub release tag verification

At `0ea630c36`, the driver checks an existing tag against the commit being
built and skips occupied tag and release names when choosing an automatic
tag. At handoff it creates a missing ref at the built commit, checks the
result, and invokes GitHub CLI with `--verify-tag`. GitHub's release API uses
the requested target when it creates a missing tag.
[GitHub release API](https://docs.github.com/en/rest/releases/releases#create-a-release)

All 24 release-driver fixtures passed with local stubs. The previous driver
at `0783b5d00` reached the upload command with a mismatched existing tag.
The updated driver refused an initial mismatch before output creation and
an intervening tag change before upload. It reused an existing matching
tag, skipped a bare tag and a separate release during automatic selection,
and accepted a concurrent creation only when the new ref matched the built
commit. Lookup and creation failures also refused publication.

The helper passed ASan/UBSan checks for absent and escaped tag names, tag
creation, same-commit retry, and mismatch. A read-only call to GitHub's public
API confirmed that the fully qualified annotated tag resolves to the
underlying commit SHA.

The baseline and updated runs, paired fixture inputs, API observations, and
source revisions are in
`~/.local/state/vinix/r14-release-tag-i1TnaU/qualification.tar.gz`.
Its SHA-256 is `837cffe9fe405f2c159976fa724d9438ddf01f5a166ec91c2a056a51809508c1`.
All 442 entries in the extracted `qualification.sha256` passed.

### GitHub draft verification before publication

At `2aae337e5`, the driver creates a draft, uploads the verified assets and
reads back the draft by its numeric ID. It checks the release metadata, the
exact asset set, each upload state and every SHA-256 digest, including the
digest of `SHA256SUMS`. It resolves the tag again before publishing the draft
by ID. A normal upload failure leaves the draft for inspection. With
`--draft`, the verified release remains a draft.
[GitHub release asset API](https://docs.github.com/en/rest/releases/assets#list-release-assets)

All 33 release-driver fixtures passed using local stubs. The previous driver
at `83ddc2585` proceeded to publish in the fixture where the tag moved during
upload. The new driver retained the draft when the tag moved or disappeared,
the draft metadata changed, the upload was interrupted, or the asset list
contained a bad digest, an incomplete upload, a missing asset or an extra
asset. The verified prerelease draft also passed.

ASan/UBSan checks covered the exact draft, a wrong draft ID, modified release
notes and digest mismatches for both an ISO and the checksum list. Read-only
requests to GitHub's public API confirmed the numeric release ID and
`sha256:` asset digest format.

The paired inputs, run logs, draft states and source revision are in
`~/.local/state/vinix/r14-release-draft-verification-N2InLu/qualification.tar.gz`.
Its SHA-256 is `b0a8743b71f3c6170218bdc12db4a5ae5114fd4449f68d7c76ab633d84c8165a`.
All 671 entries in the extracted `qualification.sha256` passed.

### Asset uploads use the created draft ID

At `49e2634ae`, the release driver checks the upload URL in GitHub's
draft-creation response against the expected GitHub.com repository and
numeric draft ID. It streams the assets from the verified manifest to
that endpoint in batches of up to five. The driver waits for all uploads
in a failed batch before returning the draft ID and failed asset names
in the error. [GitHub asset upload API](https://docs.github.com/en/rest/releases/assets#upload-a-release-asset)

All 35 release fixtures passed with local GitHub stubs. The previous
driver at `210fffe40` used a tag lookup and reached a replacement draft
after the original disappeared. The updated driver stopped at the
original upload endpoint. It also refused an upload URL containing a
different ID before sending any assets.

ASan/UBSan checks covered the exact manifest asset set, an interrupted
batch and a foreign upload host. A loopback test with the real GitHub CLI
confirmed the draft-specific request path, asset name, content length and
exact binary request body. A public GitHub response confirmed the upload
URL template.

The paired inputs, simulated draft state, transport checks and source
revisions are in
`~/.local/state/vinix/r14-release-exact-upload-lJSNNM/qualification.tar.gz`.
Its SHA-256 is `e26880c5849922bc488b8aeb77078e80dd9b74f459f60f00431109e2de40543d`.
All 913 entries in the extracted `qualification.sha256` passed.

### Interrupted draft upload recovery

At `88f1ce131`, the release driver saves the draft ID, repository, tag,
commit, prerelease setting, checksum manifest and notes before uploading.
`--resume-draft=ID` revalidates the original local assets and the remote tag
and draft. It uploads the missing assets, skips completed uploads with
matching digests and verifies the exact asset set before publishing or
leaving the release as a draft.

All 41 release fixture checks passed using signed inputs for both
architectures, local GitHub stubs and host helpers compiled once from the
same sources the driver uses. The interrupted upload resumed with the
same draft ID after the public checksum list changed. The fixture rejected
duplicate uploads and confirmed that publishing the completed draft needed
no additional uploads. Recovery refused a changed local ISO, a mismatched
remote digest, a different repository and an already published release.
ASan/UBSan controls restored the saved manifest and notes byte for byte
and refused both a duplicate record write and an invalid recovery ID.

The paired inputs, run logs, simulated draft state and recovery records
are in
`~/.local/state/vinix/r14-release-resume-run-Cja4yh/qualification.tar.gz`.
Its SHA-256 is `54186cc7d8f548b4f76659221230340663efdfa16c0af891726eace482547c26`.
All 899 entries in the extracted `qualification.sha256` passed.

### Published release confirmation

At `bd55b1eb0`, the driver reads the release by numeric ID after attempting
publication. It checks the published state, release metadata, exact asset
digests and tag commit before reporting success. With the saved recovery
record and original assets, `--resume-draft=ID` can confirm an already
published release without sending another upload or publish request.
[GitHub release readback API](https://docs.github.com/en/rest/releases/releases#get-a-release)

All 49 release fixture checks passed against the committed script with
signed inputs for both architectures, local GitHub stubs and host helpers
compiled once from the driver's sources. The previous driver at `5fab77715`
rejected recovery after publication. The new driver confirmed publication
after a lost response and recovered after a failed readback. It refused to
report success when the release was still a draft, an asset digest differed
or the tag moved. A separate run compiled the host helpers through the
driver and confirmed the release with closed input. All 11 fixture upload
and mutation records kept their original checksums.

ASan/UBSan checks covered a verified release and refusal of a missing or
null draft state, a mismatched digest and a different upload destination.
A read-only GitHub API call confirmed the fields on a public release.
[Public release response](https://api.github.com/repos/cli/cli/releases/449359903)

The paired inputs, baseline and committed runs, API observations and source
revisions are in
`~/.local/state/vinix/r14-release-publication-l7xDNK/qualification.tar.gz`.
Its SHA-256 is `13cf06005a0453ff6b50cd0188df9aeb977fbcf3389365eb1c8ca2d15d0d956f`.
All 1,395 entries in the extracted `qualification.sha256` passed.

### Initramfs layout verification

At `deaccaa03`, the ISO verifier reads the same POSIX USTAR header types and
octal mode and size fields used by the release packer. It requires one gzip
compression layer. Package parent directories must appear before their members,
allow ordinary accounts to read and traverse them, and exclude shared writes.
The scratch tree is created from explicit directory entries before checking the
signed selection.

Both target plans passed 19 host controls with the production verifier and again
under ASan/UBSan. The baseline issued receipts for all eleven new negative cases
on both targets. They cover inaccessible and search-only directories, missing or
late parents, legacy and contiguous file types, PAX path replacement, non-USTAR
headers, leading spaces in a size field, bzip2 and nested gzip. The shared tar
reader tests and the configuration-only receipt replay also passed.

The retained x86-64 mixed-catalog fixture produced an identical receipt. The
previous AArch64 handoff fixture lacked an explicit `/etc` entry and refused.
Repacking the same signed tree with its parents produced a matching package
selection and a new ISO digest. Both retained bootable desktop ISOs passed the
archive checks and reached repository verification, which refused their expired
fixture indexes.

Build the two host tools as described above. The test runner can generate fresh
signed fixtures without relying on an older fixture index's lifetime:

```sh
fixture=/path/to/new-fixture
iso-package-receipt-check fixture aarch64 "$fixture"
VINIX_PACKAGE_IMAGE_CONFIG_AARCH64="$fixture/config.json" \
VINIX_PACKAGE_IMAGE_REPOSITORIES_AARCH64="$fixture/bundle" \
VINIX_PACKAGE_IMAGE_APPLICATIONS_AARCH64="$fixture/staged/usr/share/vinix-packages/applications.json" \
  package-receipt plan aarch64 > "$fixture/plan.json"
iso-package-receipt-check /path/to/package-receipt "$fixture/staged" \
  "$fixture/plan.json" /path/to/new-check-output
```

The fixtures, baseline and fixed outcomes, and mixed-catalog evidence are in
`~/.local/state/vinix/r14-iso-boot-layout-luLPhK/qualification.tar.gz`.
Its SHA-256 is `4ec9818f3a349e9468d707d28dbce344014915c50ada177cb7ecf8e356d769ec`.
All 179 entries in the extracted `qualification.sha256` passed.

### Complete gzip member verification

At `33bacba6d`, the boot archive reader checks one gzip member through its
trailer and requires physical EOF. The streaming decoder validates the CRC
and uncompressed length, enforces the boot trailer's 32-bit size limit, and
continues to the trailer when it encounters the TAR end block first.

Both target plans passed 25 host controls with the production verifier and
with ASan/UBSan. The previous verifier issued receipts for an empty leading
gzip member, a second member after the archive, raw trailing bytes, a bad CRC,
and an incorrect uncompressed size. Both versions refused a truncated trailer.
The six shared reader tests and the descriptor-only probe passed, including
128 repetitions each for normal skip, body EOF and padding EOF. The descriptor
probe linked without archive or compression libraries, and the host ZIP
consumer built with its own zlib declarations.

The two retained mixed-catalog ISOs and the configuration-only fixture produced
byte-identical receipts. The complete retained desktop initramfs files reached
repository authentication, which refused their expired fixture indexes.

The paired fixtures, before-and-after receipts and diagnostics, build logs and
references to the retained ISO inputs are in
`~/.local/state/vinix/r14-iso-gzip-members-PUo9Vj/qualification.tar.gz`.
Its SHA-256 is `a02456b88fb2cfecd2b8f0ecb014a79e31e58be42a3e60a9507cfcb2fc805b02`.
All 202 entries in the extracted `qualification.sha256` passed.

### Exact repository names

At `32fbcf46f`, ISO verification checks repository entry names before creating
the scratch tree. It admits the existing publisher identifier grammar, the
literal `index.json`, `index.sig` and `objects` names, and lowercase SHA-256
object filenames.

The baseline issued receipts for ISOs with an extra `Index.json` or uppercase
object digest on case-insensitive HFS+ and refused those same ISOs on
case-sensitive HFS+.
The fixed verifier refused both variants on both filesystems. All 27 host
controls passed per target plan on each filesystem, along with the ASan/UBSan
runs on case-insensitive HFS+. The mixed-catalog and configuration-only
fixtures reproduced their receipts byte for byte.

The fixtures, diagnostics and build logs are in
`~/.local/state/vinix/r14-iso-repository-names-ClY7eX/qualification.tar.gz`.
Its SHA-256 is `3d0bb1dc4a3060393740829425e925d69a2c5be7b327757ed4806b6b39f54ed2`.
All 383 entries in the extracted `qualification.sha256` passed.

### Archive link verification

At `0eeb1ed6f`, the verifier checks link targets in initramfs order. Hard links
must name a previously listed regular file outside the protected package paths.
An earlier admitted hard link may serve as the target of another link. The
verifier also refuses archive entries that traverse a symbolic-link parent.

Both target plans passed 33 host controls with the production verifier and
under ASan/UBSan. The six new cases cover a valid hard-link chain and ordinary
symlink, a hard link to package configuration, a directory target, a forward
target, a symbolic-link target, and a member under a symbolic-link parent. The
mixed-catalog and configuration-only fixtures reproduced byte-identical receipts.
The retained bootable desktop ISOs passed the archive checks and reached the
repository authentication check for their expired fixture indexes.

The fixtures, verification logs and retained ISO input checksums are in
`~/.local/state/vinix/r14-iso-archive-links-kVzVtp/qualification.tar.gz`.
Its SHA-256 is `b9540411300a7a5edcaa741c0c1bc21c8fa30a7e9e6679f637cde00913aa8e8b`.
All 304 entries in the extracted `qualification.sha256` passed.

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
