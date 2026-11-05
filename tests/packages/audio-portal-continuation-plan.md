# Format-2 audio continuation

The host contract checks pass in normal and production builds; see
[the qualification report](audio-continuation-host-check.md). No real format-2
preparation or native audio guest has run. Work began in the charged
`T/audio-continuation-source-01` sparse worktree, based on
`156c7497640dbf2015fae375ae12dccf64683956`.

Before review fixes, all thirteen initial files were independently copied to
`T/audio-continuation-draft-before-review-01`. They match the initial external
manifest SHA256 `b5982fa9c98765e1ff777ba18ff4e6f0eaab769ad0819a396222154d12282a3f`.
The adjacent copy map SHA256 is
`eaa052c9b6716fe6bd29010b28552259336ab66a58e1deb0a2878b6edf74e6e1`;
all copies are ordinary, have one link, and have different inodes from the
mutable draft. The main repository's initial review checkpoint remains a
historical record of that uncompiled initial draft.

The original format-1 producer, preparation schema, verifier, retainer, failed
capture, content store, and historical checkers are unchanged. The failed
preparation has no completed receipt. Its complete original seal attempt timed
out; this draft does not replace that result with a success claim.

The parallel `audiocontinue` module and `audio-portal-continuation.v` provide
prepare, frozen-preparation verification, and read-only guest-budget inspection.
There is no guest executor, qualification, or retainer in this draft. A future
guest/qualification format must be separately implemented and reviewed after
resources admit all retained artifacts.

The original reviewed tool Plan remains exactly SHA256
`d939f4091b42d556db5739845e9f099c0f2cd877a0be4332b91beeb665e90290`.
It supplies immutable identities and the same six charged roots, never an
executable command or environment from JSON. New typed Plans/manifests require
exact canonical encodings and independently reviewed SHA256 digests. All new
Plans, manifests, source, controller, and mutable phase output remain under the
same charged preparation root `T`.

## Immutable and mutable boundaries

`Donor2` covers both the entire failed `preparation-01` capture and the entire
`audio-input-store`. It inventories every ordinary file and directory, including
content, owner, permissions, device/inode, link count, size, mtime and ctime.
Symlinks, special objects, overlapping roots, and missing or extra entries fail.
Every regular-file inode's observed names must equal its link count across the
complete two-root forest. Historical capture/store hard links are allowed only
when all aliases remain inside that immutable forest.

Only fixed canonical relative roles may be borrowed: sysroot, GCC, V library,
stdatomic, matched-kernel evidence/kernel, V/tool identities, QEMU, firmware and
its original variable image. Old generated programs, source, controller, logs,
cross-probe results and package publisher are not borrowed. Limine was not
captured before the failed producer stopped, so it is independently copied from
the exact legacy original.

`Source2` declares `reviewed-content-with-base-provenance`: its complete
separately reviewed inventory is the content authority. `base_revision` binds
detached HEAD only as base provenance, and does not assert that reviewed source
equals a clean committed tree. The new Plan/receipt field is explicitly
`source_base_revision`; a reviewed patch on that base is permitted. Mutation
after the content manifest was reviewed fails exact comparison. Every source
file must have one link. The preparation independently
copies its fixed production closure into the new state. It builds a fresh
adapter, sandbox generator, generated C, objects, raw compiler traces and all
eight AArch64 ELF64 ET_EXEC targets. It creates a new signed tone/noaudio
publisher and independent account/action/runtime extras.

Before and after handled preparation failure or success, the engine attempts
all complete donor, external-source and 43 original-tool role inventories.
Actual observed values are retained before comparison, with explicit errors on
partial inventories. They are never replaced by expected values after failure.
Copied source is independently inventoried before and after. Mutable regular
files must have one link and cannot share any donor or source inode. The complete
new state inventory excludes only its exact final `preparation2.json` receipt.
Only the root directory nlink/size/times are normalized for publishing that
regular receipt: APFS includes regular children in the directory link count.
Root mode, owner, device/inode and all nonroot metadata remain bound, as do all
entries. Raw root metadata is still compared during each inventory walk.

The engine uses the existing `nativeguard` owner, fixed per-command environment,
private temporary/module directories, at most 300 seconds per command and at
most 3000 seconds for the entire preparation. Each child must exit zero with
observed ownership, reap, empty group, no held output pipe, and final ECHILD.
Producer and verifier share pure constructors for all twenty exact command
specifications, including every source, flag, output path and environment key.
Observed argv/environment JSON must equal the complete canonical specification;
an executable allowlist is insufficient. The verifier also checks all twenty
command cleanup receipts. The internal complete
kernel-audit leaf derives paths from the Plan and requires its current owner's
barrier/argv and independent copied controller. It does not accept arbitrary
checker commands or log paths. The unchanged original complete auditor runs
before and after target preparation under that owner.

`--verify` reads frozen identity, complete inventories and preparation audit
receipts. It launches no process and does not refresh the original complete
audit. Neither preparation nor frozen verification qualifies native audio.
Unknown formats/fields, changed input forests, wrong-role paths, hard-link
aliases, failed command cleanup, absent targets/traces/objects, or any refusal
receipt prevent preparation acceptance.

Completion is a separate publication boundary. The engine writes only
`preparation2.pending.json` while performing full candidate verification,
resource checks, an existing-owner sticky cancellation check and the final
deadline admission. Candidate verification excludes only that exact pending
file and requires the completed receipt absent. Atomic native
`renamex_np(..., RENAME_EXCL)` is the last fallible operation; no readback,
deadline check or refusal write follows successful publication. Public frozen
verification excludes only `preparation2.json` and requires pending absent.
Thus a failed late gate plus a failed refusal write leaves no acceptable
completed receipt. Deadline admission is immediately before publication;
the rename's completion time is not measured by a later fallible check.

All eight target roles require an ordinary executable ELF64 ET_EXEC file, not
only matching header bytes. Observation of a failed donor is independent per
root: obtainable capture entries and the intact store are retained with their
own errors even if one traversal fails. Strict acceptance remains complete
comparison and alias closure. The native output writer uses an explicit
promoted 32-bit mode argument, checked in the retained generated C.

## Resource limits and current refusal

The cap remains 2 GiB aggregate across the same six roots, including every
failed attempt, donor, retry, worktree, log and source copy. Allocated accounting
counts every pathname's blocks; apparent accounting conservatively rounds every
entry to 4 KiB. These are conservative endpoint admissions. Existing nativeguard
samples allocated usage and free space while children run; the draft does not
claim continuous apparent-usage enforcement. Start free-space admission remains
2 GiB and the live floor remains 1 GiB.

Preparation reserves at least 200 MiB for new source/controller copies, all
eight generated/C/object/ELF outputs, tools, compiler temporaries, publisher,
extras and logs. This is an explicit planning assumption, not a measured upper
bound. Receipt reserve is separately required: twice the encoded known after
maps (donor, legacy, external source and copied-source upper estimate), plus
32 MiB for the final receipt and 8 MiB plus 64 KiB for refusal/bookkeeping,
rounded up to 4 KiB. The per-child allocated cap is tightened by that actual
reserve, and apparent endpoint admissions preserve it too. The 16 MiB generic
floor alone cannot cover this donor's approximately 15 MiB legacy map. Input
growth beyond the bounded observations produces an explicit incomplete-evidence
refusal, never an accepted receipt.

The latest retained measurement before this source-only work was 1,752,152 KiB
allocated and 1,901,015 KiB apparent, leaving only 196,137 KiB gross apparent
headroom before new source/proof reserves. Even 200 MiB plus the generic 16 MiB
receipt floor cannot fit. A real continuation preparation is presently refused
before creating state. No second capture or continuation has been launched.

Guest-budget inspection additionally reserves all three retained scenarios.
Each includes a payload-derived power-of-two FAT boot image (at least 64 MiB),
the actual original firmware variable image (at least 64 MiB), at least 64 MiB
combined rootfs/archive allowance, 46,084,096 bytes for 240 seconds of 48 kHz
stereo 16-bit PCM plus a WAV header page, and at least 16 MiB of logs. A 64 MiB
archive estimate already makes the FAT image at least 128 MiB after kernel,
loader, configuration and filesystem headroom. These planning floors do not
prove actual archive/output sizes. A future executor needs a measured output
projection, its own phase claim/log/cache roots, complete postchecks and the
same aggregate cap. Read-only budget inspection creates no run claim.

No reviewed `Donor2` or `Source2` manifest currently exists. The old failed seal
is not one. Before any proposed execution, complete separately reviewed pinned
manifests and a concrete manifest-production owner/admission must be provided.
This draft supplies complete inventory APIs but intentionally does not silently
generate or trust a replacement donor manifest during preparation.

## Validation scope and further integration checks

Source review covered format isolation, canonical containment, alias closure,
environment/command boundaries and publication. There are no changes to
format-1 files. The host report distinguishes exercised controls from the
larger manifest, target, publisher and real-preparation integration matrix below;
that full matrix remains required before native acceptance.

Required coverage for the complete preparation path includes:

1. Compile the new module/CLI with the pinned compiler in normal and production
   builds, private charged caches, strict C pointer diagnostics and explicit
   nativeguard/recoveryguard lookup roots. Inspect generated C and preserve
   every failed bootstrap without editing earlier output.
2. Run the checked-in pure budget, all-eight-trace, donor/inventory and alias
   controls in a fresh charged `AUDIO_CONTINUATION_TEST_ROOT`. Cover integer
   overflow, exact dual-cap boundaries, dynamic proof reserve and current
   196,137 KiB gross-headroom refusal. No temporary-root fallback is allowed.
3. Add and run full manifest/schema controls: format 1 supplied as 2, unknown or
   duplicate JSON fields, wrong roles, noncanonical parents, source/donor/state
   overlap, outside aliases, missing/extra entries, wrong detached base or
   changed reviewed content,
   forged controller, existing/refused state and uncharged Plan paths.
4. Run ownership and failure controls under the existing owner: real timeout,
   nonzero child, held pipe, output flood, environment restoration, changed
   donor/source during a handled failure, partial original-tool inventory,
   and proof-reserve exhaustion. Require all independently obtainable after
   observations and clear refusal when any inventory is incomplete.
5. Run frozen receipt controls: each missing/extra target, C, trace or object;
   wrong-architecture/non-executable ELF; wrong runtime copy; account/config/
   action mismatch; signed publisher/key/payload/permission mismatch; altered
   original-audit argv/output/checked receipt; missing/failed command cleanup;
   changed metadata; ignored path abuse; every candidate/resource/cancellation/
   deadline refusal before publication, including a failed refusal write;
   exclusive publication collision; direct internal-audit invocation and
   stale/wrong-pid barrier. Checked-in boundary tests exercise the production
   completion driver, all eight missing-execute-bit cases, strict schemas and
   the honest source-content/base contract. Owner tests exercise the real
   engine command path with a small synthetic V child for clean/nonzero/
   timeout/held-pipe cleanup and parent-environment restoration; they never
   execute a compiler, original audit or guest.
6. Re-run unchanged relevant format-1 controls to establish isolation. Run
   repository source-policy checks. Only after the source and host controls
   pass may the new implementation be committed. No native qualification is
   implied by that commit.

Actual manifest creation, preparation and any guest phase require a separate
concrete resource review. No source change authorizes an infeasible run or
enlarges the existing cap.

Historical host plans used a 96 MiB internal allocation. Reviewed plan 11
explicitly increased it to 112 MiB, including an untouched 16 MiB tail, within
the unchanged 2 GiB six-root hard cap. All old plans and failed outputs remain.
No real input manifests, capture, preparation, complete original audits or
guests were admitted by the host stage. Generic compiler observations are
endpoint-only, without RSS or typed compiler-descendant cleanup claims.

## Qualified host build composition

The pinned compiler encounters a namespace collision between a private
nativeguard global and a dependency function. Qualification used complete
independent private overlays with an exact eleven-reference internal global
rename. `audio-continuation-owner-source.v --controls ORIGINAL PRIVATE_GUARD`
checks the exact original hash, inverse identity, independent output and three
source refusals. Its `--emit` writer has not been executed or qualified.
The shared repository nativeguard remains unchanged. Put the private overlay
and its nativeguard alias parent before the unchanged dependency roots in
`-path`. Retained host plans 11/12 record expanded commands and environments.
This does not qualify the default shared-guard import composition.

Use explicit `-new-compiler -no-retry-compilation -nocache`, pinned V/clang,
strict incompatible-pointer diagnostics, a recorded clean environment, explicit
SDK and fresh charged temp/module/cache directories. Matching launcher/driver
source establishes fail-closed dispatch; environment marker names alone are
not that proof. Actual generated C and all remaining compiler outputs are kept.

The matching outer `v test` entry dispatches an unavailable external reporter.
The qualified route uses the ordinary module directory, an exact six-file
comma-separated `-file-list` and explicit `-o`, without a `test` token.
Generated C must contain all 44 definitions and all 44 main calls. Compilation
does not execute tests.

The pinned compiler strips language assertions under `-prod`. Its first
production-test compile is preserved as failed qualification and was never
executed. The seven `audiocontinue-production` companions are test-only source
for a separate private overlay: copy all ten unchanged implementation files,
replace the six tests with those companions and add `production_checks.v`.
Never add that helper to the production implementation module.

Every one of 126 assertion conditions becomes an ordinary checked call.
Before any test, the helper verifies hard-coded original hashes/site counts,
full inverse byte equality, source independence and all ten implementation
files' equality. Independent review checks every condition and generated C.
Set `AUDIO_CONTINUATION_PROD_ORIGINAL` to the immutable normal module; the helper
uses its own source path for the derived root. Run the same binary first with
`AUDIO_CONTINUATION_PROD_FORCE_FAILURE=1`: require exact exit 1, all three
markers and an empty fixture parent. Set it to 0 and require all 44 tests to
complete. Fail-fast ordinary checks survive `-prod`; no compiler change is used.

Normal and production tests use fresh `AUDIO_CONTINUATION_TEST_ROOT`, the exact
six `AUDIO_CONTINUATION_CHARGED_ROOTS`,
`AUDIO_CONTINUATION_RETAIN_FIXTURES=1` and a pinned finite child fixture.
There is no temporary-root fallback. Four real engine-command cases cover
clean, nonzero, timeout and held-pipe cleanup under the unchanged owner.
