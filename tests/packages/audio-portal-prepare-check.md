# Native audio preparation checkpoint

The ARM audio controller can build and seal its eight target programs without
booting a guest. `--prepare-only` writes `preparation.json` and prints its SHA-256.
Review that digest and the complete retained preparation before executing:

```
audio-runtime --verify-prepared /absolute/preparation --prepared-sha256 REVIEWED_SHA256
audio-runtime --resume /absolute/preparation --prepared-sha256 REVIEWED_SHA256
```

Verification is read-only. Resume validates the original preparation, claims
`run/` exclusively and uses the prepared programs with the compiled scenario
table. It never calls a compiler or rediscovers the host. Used or changed trees,
receipt mismatches and command-line overrides fail before execution. A failed
attempt retains its run claim. Only the existing three-scenario gate can write
native qualification; preparing or verifying a basic-only tree cannot qualify
audio. The existing one-shot x86 path is retained.

The inventory includes file bytes, directory and file modes, empty directories,
all eight compiler traces and saved objects, the actual guest root, captured
loader and named runtime tools. Symlinks and special entries are refused. The
controller also binds source/current-controller bytes, generated C, artifact
maps, reviewed SO_PEERLOGIN kernel evidence, explicit runtime paths and selected
scenarios. Resume requires the original inputs to remain unchanged; QEMU and
host dynamic dependencies retain their observed host paths. This is an observed
input checkpoint, without a hermetic or reproducible toolchain claim.

Host validation passed at source baseline
`d366ee8810dee8f518c901008a779b1f53bd7ffc` plus the five maintained V source
changes accompanying this report. All four host tools built with pinned V
`ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5`,
LLVM 23.1.0 clang, `-prod -nocache -keepc -backend c`, and explicit `VINIX_ROOT`.
The 88 preparation controls and existing 34 strict ARM evidence controls passed;
both control runs retained identical selected-input hashes before and after.
Independent source review found no remaining blocker within the reviewed-digest,
stopped trusted-host scope. No target build, guest boot or native audio
qualification was performed for this change.

Complete preserved attempts and final receipts are outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/`:

- `prepare-host-03/host-build.json` records the final four builds, literal
  commands, tool/environment pins, generated C and source inventory. Its SHA-256
  is `28efbc0fa1d87735a757c77ffdd388109a3d4c098704bdf2c6c38297d8685b90`.
- `prepare-host-03/bundle.sha256` seals the host builds before the controls:
  `51ee84fea05517c059915a541e63dbf1cfb84e0d0f0d16d6875f8126bf3cbaed`.
- `prepare-host-validation.json` inventories all 22,666 entries in preserved
  `prepare-host-01`, `-02`, `-03` and the named external V recorder helpers,
  including literal internal symlinks without traversal. Two stopped-tree
  observations matched, and a separate verify invocation passed. SHA-256:
  `a2b9e1153f1443ecfaf6eefc927abe86f8f0bfd6d3f455aee81a58d63226f209`.

Attempt 01 is superseded. Attempt 02 built successfully but its source-root
mutation control also changed checkout discovery, producing a different correct
refusal than the test expected. The final checker binds checkout discovery to
its compiled source location. Attempt 02's logs, receipts and immutable source
snapshot are preserved; its hardlinked synthetic source leaf was detached and
restored to the exact as-run bytes, as documented beside that attempt. Attempt
03 passed all controls. The original `current-main-host-01` manifest and every
listed artifact were also reverified unchanged. The final inventory and helpers
bring new retained allocated state to less than 100 MiB, excluding preexisting
kernel and source hardlinks. Host SDK and original tool dependencies remain
observed inputs rather than a hermetic compiler closure.

The [current independent-fixture checkpoint](audio-independent-fixtures-check.md)
qualifies the fresh matched-kernel bindings and all 151 host controls. Target
preparation and guest audio execution remain pending.

The matched-kernel extension adds a separate format-2 receipt. Its exact reviewed
receipt binds both architecture ELFs, generated C, build logs, seven critical
sources and the original complete external audit. Local receipt validation only
establishes identity. Admission, retention, verification and pre-resume also run
the pinned complete-audit checker against the original complete bundle; a small
kernel copy cannot replace that bundle. The historical format-1 checks retain
their original requirements.

`audio-portal-prepare-run --inspect|--prepare PLAN PLAN_SHA256 NEW_COMMAND_DIRECTORY`
captures the selected source, compiler, runtime and kernel inputs under a reviewed
plan. Preparation requires committed source and the complete selected input map,
builds the eight AArch64 programs, retains all three audio scenarios and verifies
the result without starting a guest. The runner checks actual free space and
inclusive pathname allocation of its named charged roots. Repeated hardlinks
count repeatedly. This is not an exclusive physical-growth measurement.
Verification and pre-resume preserve fresh complete-audit logs under `TMPDIR`
and print that location. The runner supplies a charged temporary directory;
direct controller invocations retain those logs under their own `TMPDIR`.

The following matched-kernel attempts are historical as-run observations. The
later [fixture alias diagnosis](audio-binding-alias-diagnose.md) supersedes their
unchanged-history assumptions; the old whole-history inventory remains refused.

The interrupted matched-kernel host attempts are preserved at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-matched-host-01`.
Bootstrap attempts 01 and 02 failed compilation. Attempt 03 built all six host
tools, then refused a fixture because the sparse source checkout omitted the
tracked hardware runner. After restoring that exact tracked file, attempt 04
built all six tools successfully, but its first controls run was externally
interrupted without a final result or cleanup receipt. The historical
`audio-portal-prepare-continue.v` pins those six build artifacts and their frozen
source maps for fresh, read-only reuse of those prior artifacts. Its attempt 05
checked those bindings and then stopped at the original complete audit with actual exit 1:
the historical bundle's saved device identity differed from the current host.
No controls ran in attempt 05. Its original manifest and failure receipts remain
preserved; these attempts establish no new controls or native qualification.
The continuation keeps that old source profile and refuses later pin changes.

Fresh atomic-kernel attempt 06 passed the original complete audit and all six
production host builds. Its preparation controls stopped when a malformed legacy
seal was refused with a JSON parse error instead of the historical refusal text.
The controller now preserves that legacy refusal at the format probe. Attempt 06
retains the actual failure and complete owned-group cleanup receipt; its remaining
controls did not run.

Attempt 07 passed all six production host builds and all 149 controls: 88
preparation checks, 34 strict evidence checks and 27 matched-kernel checks. Its
original complete audit before the builds also passed. The final audit did not
start because actual free space was below its 2 GiB admission threshold; attempt
07 therefore retains an incomplete overall result rather than a qualification.

The maintained `audio-portal-prepare-finish.v` completed attempt 08 with actual
exit 0. It pins the six successful build executables, generated C, command arrays,
environments, results and independent source snapshot from attempt 07, reuses
those artifacts read-only and completes the final original audit. Exact selected
source, tool and evidence maps, plus the complete reused attempt-07 tree map,
were identical before and after. The final audit returned actual 0 with a reaped
child, `ECHILD`, an empty owned process group and no held pipe. Qualification
`qualification-08/qualification.json` has SHA-256
`d9313653aa3653f8f12bd90e2a8a96af5fd90026c8ce73d2896e04e81c5c5132`.
The native guard's final inclusive allocation was 1,500,999,680 bytes under the
2 GiB cap; final actual free space was 3,156,932 KiB.

The source baseline is `37ea063a412d3dfbe7f1eb2c77fc2bc152928255` plus the
accompanying source changes. The final controller is SHA-256
`24ca64ca7d591b4d6e63c14e9ed83b917af2e1c1f12bf8b1d0bdedb34dc693c7`,
and the finalizer source is
`8f21c48977bef63786b993ddab3e3c2257ff2fd92c3600c733c695f4920aef31`.
The matched kernel receipt is
`2d93f496c9f17a029eff5691070fb6093cad741380b28a87736f12ebfa35e5cb`,
requiring the complete original bundle at
`/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-20261026`.
That historical bundle is now refused and cannot admit fresh preparation.
This is host qualification of preparation and refusal checks. No target program
build, guest execution or native audio runtime qualification was performed.
This final receipt was appended after the source capture; the qualified
implementation bytes remain unchanged.

The whole preserved host history has a canonical inventory at
`/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-matched-host-01-seal-02/complete/inventory.json`,
SHA-256 `bfb9db85b6253b2b6f0351f3e993c997f1c3604d106f944cd633b5c24a6e7572`.
The original sealing commands reached their 300- and 600-second bounds with
actual exit 137; their two-scan inventories are identical. The independent
300-second original check also timed out with actual 137. All partial output,
logs and statuses are preserved outside the host history. After free space
recovered, the fresh unchanged-original check, bounded to 600 seconds, returned
actual exit 1: `state object changed during read:` followed by the host-history
path `/qualification-04`. Its 140-byte `check-02.log` has SHA-256
`963c3962e9d3531a22eae097f878f7c1ca8191d9074e669d2064d852a1a6b7f8`.

Read-only diagnosis also found a persistent directory-metadata mismatch: the
saved `qualification-04` entry has modification and change times `1793025223`,
while two later observations both read `1793035156`. Device, inode, mode, owner
and group still match. The original checker compares raw directory size and all
metadata before and after traversal, then compares the complete canonical
inventory; canonical directory size is zero. The error establishes a change
during its read, and the later timestamp mismatch prevents treating the refusal
as a resolved transient. Manifest, checker and checker-source hashes remain
unchanged. No retry, resealing or metadata exemption followed this diagnosis.
The whole-history inventory remains unqualified. The 149 controls and final
attempt-08 audit retain their recorded successes, with the limited host scope
described above; the attempt-08 receipt still has the reported hash.

The later alias diagnosis also found four changed historical fixture files.
Their independent as-run source snapshots remain preserved. No old alias or
metadata was repaired, restored or resealed; see the diagnosis for the exact
paths and correction receipt.
