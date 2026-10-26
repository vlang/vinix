# Allocation allowance calibration

The maintained V runner `allowance-check.v` compiled and passed 23 explicit
host controls, including 20 refusal cases. Clean baseline
`9acefa77bee69247c837e97987a2377536aa41cc` and the frame-page/cast worktree
each completed both architecture warning scans with compiler exit zero.
**Both global allowance checks failed** against the unchanged `allowed.txt`.
The file/kind counts are byte-identical: 209 groups, 450 unique sites across
the architecture union, with zero count delta. This does not pass the global
allowance policy or measure runtime allocations.

The selected ff75 compiler reports allocation kinds/sites absent from the
existing table even on the clean baseline. Each run retains its full
`NEW:` failure list and has no `qualification.json`. No allowances were
updated. AArch64 reports 382 distinct sites; x86_64 reports 278. The clean
source closures contain 716/715 V files respectively; the changed closures
contain 717/716, including the shared frame helper.

The changed V source set is exactly `kernel/alloctrack/frame_page.v`,
`kernel/alloctrack/track_d_alloc_track.v`, `kernel/file/locks.v`, and
`kernel/memory/slab.v`, pinned in the retained input maps. Kernel changes
remain separately held for required guest qualification. The runner source
SHA256 is `883aa8776ead41dba82249913b727b3492954388db0ed54f69111f38f7406b67`.
This report and runner are independent of that held production change.

Complete original state, including bootstrap sources, kept generated C,
host helper binaries, commands, process statuses, copied source closures,
logs, input maps, calibration assembly and both failures, is retained at:

`/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-allowance-20261026`

The complete typed inventory is retained separately at
`/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-allowance-20261026-seal-01/inventory.json`,
SHA256 `eb713bfc299ed3e8403af02e4dfbd193f2b36e617e8044ed1647b4c4ed23d098`.
The reviewed frame-page sealer made two complete scans and a subsequent
check passed. This is an inventory of the retained original directory,
not an archive; external dependency-link referents are pinned by scan input
maps but are not copied into this complete-state inventory.

Bootstrap compile/selfcheck receipt SHA256:
`b860eefd2020be2a34c5e58630afb4cae0ae8f4b2057e1bb8e07ef432d41a992`.
Supplemental comparison receipt SHA256:
`672e54356de7175cb33188f065ed154cb643508ff4fb41fa68817b379f8c11c1`.
Both `counts.json` SHA256s:
`4355c9c449cdc49d9c64c0f54ede615351236338686e749f61f761250a5488fd`.
Both allowance-file SHA256s:
`0ae5baa578fa92d3ee82c16d834fc3ea414db344529d2fef4bbc264d2409cc12`.
Every original/copied before/after input map matched. Each make/compiler
leader was reaped, its original group was absent, and `waitpid` returned
`ECHILD`. Independent source review found no blocker.

Reproduce by compiling the maintained runner with the pinned
`build/package-https-runtime-work/toolchain/v`, canonical LLVM23 clang,
`-nocache -gc none -manualfree`, and module path
`@vlib|REPOSITORY/tests/kernel-allocs`. The retained
`bootstrap-01/build.argv.json` and `selfcheck.argv.json` contain literal argv.
Run `allowance-check selfcheck`, then
`allowance-check check REPOSITORY NEW-ABSOLUTE-OUT`. The latter retains
literal make/V argv for both architectures. It uses the existing maintained
`copycore` closure builder and matches `run.sh`'s unique
file:line:column-plus-kind union followed by per-file/kind maxima.

The runner clears ambient environment selectors, supplies private modules,
cache and temporary directories, and uses `-nocache`. It pins the entire
selected V tool tree, source/dependency closure, declared host tools and
environment before/after. Host tools and SDK execute in place; the result
is not hermetic. Warning scans use ordinary non-`ALLOC_TRACK` defaults,
not the separately built tracked kernels. No image or VM was started.

The enforced scan budget was actual `df -k` >=2GiB admission and >=1GiB
floor, with sampled worktree-plus-state usage <=512MiB. Final observed
combined frame/calibration worktrees, state and seal were below 120MiB.
One tiny supplemental comparison compilation incorrectly proceeded after
observing only 1,594,336KiB free; its admission failure, literal invocation
and observed output are recorded in
`supplemental-comparison-execution.md`. It does not invalidate or replace
the earlier scans' enforced gates. No further compiler was started.

Disk limits are observations rather than quotas. Inventory entry/depth and
120-second checks are cooperative; synchronous host filesystem/tool calls
can block. Dependency symlinks intentionally resolve outside the selected
root and are hashed, so this is trusted-source staging rather than hostile
namespace isolation. Cleanup assumes trusted numeric PID/PGID identities
and does not cover descendants escaping their group.
