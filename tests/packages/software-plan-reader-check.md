# Package and deployment plans in the compact Software reader

**Read plan** is available after an install/remove/upgrade/repair/rollback or
deployment proposal is admitted, in full and compact windows. Plan pages show
operation, target architecture, fingerprint, active/restore generations, exact
required/available/reserved bytes, argument/root/package counts and the captured
deployment filename. Operation-specific explanations cover replacement,
uninstall, authenticated repair and rollback into a new generation; personal
data retention and rollback limits stay explicit.

The reader starts at the review's selected package, or an overview when none is
selected. Item navigation visits every frozen operation argument followed by
every package, including removals and retained dependencies. Package pages reuse
the complete details presentation: names/descriptions, versions/actions, role,
architecture/kind/runtime, publisher/repository, permissions, license and
proprietary/firmware flags. Invalid presentation text gets a diagnostic instead
of unsafe pagination. Only the current item's pages are cached. Empty proposals
retain scope and disk figures.

Reader item position is independent of review selection/paging. Back/Escape
retires both caches, preserving the captured command names/file, fingerprint,
package rows, selection/paging, focus, text selection and status. Only item/page
navigation and Back are accepted. Confirm/cancel, reload/edit, new review,
application requests and typing/pasting cannot mutate the proposal or begin
work. Pending partial/complete-before-exit proposals and approved package,
deployment and catalog-refresh workers refuse entry. Existing administrator
approval, frozen apply arguments, successful-exit admission and writer close
guards remain unchanged.

Functional fixtures cover all six operations on both architectures, exact u64
space/generation figures, 4,096-byte Unicode paths/descriptions, argument/package
traversal, runtime licensing/permissions, empty and removal-only plans,
invalid-metadata diagnostics, canonical reconstruction, each native short line
at 180×220 and 320×240, full lines, page keys/bounds and full/compact/tiny anchors.
A maximum proposal visits all 4,096 arguments and 8,192 packages while checking
bounded per-item caches and unchanged review selection. Package and deployment
allocation modes add 1,000 read/item/page/render/resize/ignored-confirm/Back/
cancel/cache-retirement cycles, including all five package operations and
normal/removal-only deployments. The shared Details path remains covered.

This is host UI qualification. Service/protocol/authorization, dependency
resolution and transaction behavior are unchanged. Whole-service/spawned-worker
allocation freedom, guest graphical acceptance and broader roadmap 14 release
completion are outside these checks.


## Recorded results, 2026-10-16

All twenty final focused compile/run checks passed: full Software functional
assertions, eleven affected allocation modes, ASan/UBSan functional plus package,
deployment and shared Details allocation modes, and native font metrics. Both
full desktop architecture typechecks passed. Package/deployment plan modes
retain zero tracked bytes across 1,000 read/item/page/render/resize/ignored-
confirm/Back/cancel/cache-retirement cycles; shared Details remains flat in
native and sanitizer allocation modes. Sanitizer leak detection was disabled;
whole-service/spawned-worker allocation freedom is outside these checks.

Six operations on both architectures, maximum Unicode fields/u64 figures,
all 4,096 arguments and 8,192 rows, bounded caches, empty/removal-only plans,
invalid-metadata diagnostics, native lines, resize/item/page behavior and frozen
confirmation checks passed in both functional builds. Two initial UI compiles
rejected new fixture code for immutable protocol rows and implicit array
aliasing. The fixture now transfers ownership through a cloned row container;
both initial logs/sources are retained and pinned. No assertion or protocol
mutability was relaxed.

The unchanged maintained staging list needs no new filenames and was not rerun.
Frozen compiler, Software/protocol/UI inputs, staged copies, binaries, generated
C, helper sources and logs are pinned. Cache, fallback and automatic compiler
error reporting were disabled. Service authorization, protocol, apply arguments,
successful-exit admission and approved-write close guards are unchanged. No
new guest graphical or broader roadmap release acceptance is claimed.


The initial package allocation run terminated with empty output after its
functional suite passed. Generated C showed a leaked intermediate page-label
string from the conditional total expression. Hoisting that selection before
concatenation removed the allocation. Pre-fix binary, generated C, logs and
Details source are retained and pinned; final native and sanitizer functional
and allocation checks passed.

- [focused checks](results/2026-10-16/software-plan-reader-host.json)
- [summary](results/2026-10-16/software-plan-reader-host.txt)
- [functional assertions](results/2026-10-16/software-plan-reader-ui.txt)
- [allocation checks](results/2026-10-16/software-plan-reader-memory.txt)
- [sanitizers](results/2026-10-16/software-plan-reader-asan.txt)
- [desktop architecture checks](results/2026-10-16/software-plan-reader-desktop.txt)
- [execution notes](results/2026-10-16/software-plan-reader-attempts.txt)
- [compiler/source/artifact ledger](results/2026-10-16/software-plan-reader-toolchain.json)
