# Timeline lookup at UINT64_MAX

An Asahi timeline input below `UINT64_MAX` previously failed with `EINVAL`
when its nearest submitted successor was `UINT64_MAX`. The native selector
initialized its best value to that maximum and required every candidate to be
strictly smaller, excluding a valid fence.

Candidate presence now comes from the existing nullable fence pointer. Every
nonzero unsigned point can participate, including the maximum; exact matches
still win and the nearest later point is independent of insertion order.
The object lock, retained-fence lifetime and publication policy are unchanged.
No allocation, free, callback or borrowed registration was added.

The packaged
[Asahi input path](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/file.rs)
carries `u64` points into
[Linux's chain finder](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/dma-buf/dma-fence-chain.c).
That finder accepts unsigned 64-bit sequence values, checking the requested
point against the chain root without reserving the maximum as a sentinel.
The audit now requires the exact chain source clean and retains it. This fixes
the unsigned selection boundary in Vinix's point map. Cumulative chain
dependencies and retired-point pruning remain open.

Validation passed:

- 7,913 new ASan/UBSan checks with stack-use-after-return detection. Actual
  native Asahi output publication installs `UINT64_MAX`; native input staging
  then resolves `MAX-1`. Later closer publication, exact maximum, duplicate,
  zero/nil rejection, reset, handle removal/reuse and a stable old error fence
  are covered over 200 cycles.
- An independent sorted oracle covers all sixteen subsets and twenty-four
  insertion permutations of `[1, 2^63, MAX-1, MAX]`, with nine boundary queries
  each. Both direct lookup and actual Asahi staging are checked; failed staging
  returns empty output. Lookups allocate nothing and release the object lock.
- All 114,482 prior synchronization cases, 4,096 borrowed event nodes,
  4,103 geometry probes and 200 capture primitive cycles. The unchanged
  pre-feature syncobj source passes those cases, then fails the first new
  staged input with `EINVAL` (-22). The baseline source and exact adapter,
  applied before existing allocator instrumentation, are retained.
- Async, DRM wire/node and fence sanitizer regressions, 23 V test files,
  selected source/reference gates, strict checks for 85 live ARM C helpers
  and negative allocation selftests. Native lookup, sync-array staging and
  output publication helpers are all included in the C check.
- Isolated ARM and clean x86 builds from
  `c36045242d7b0accddbdf522f971d0c7f401e34c` plus one overlay:
  `kernel/drm/syncobj/syncobj.v`. ELF/C pairs and the overlay were retained
  before switching architecture; x86 excludes AGX. Selected native sources
  and support match the private input. Generated C confirms unsigned scalar
  selection, pointer-presence validity and unlock on every return, with no
  temporary allocation. Existing retained metadata lifetime is unchanged.

The unchanged global allocation allowance audit **still fails** for baseline
and feature: 383 ARM/289 x86 sites and 826 ARM/812 x86 sources. The complete
logs are byte-identical; per-file/per-kind counts match. No auditor or
allowance was changed. Native heap/slab use, leaks and multi-CPU behavior were
not measured.

Fresh Omarchy `4bf10ed28342b597009dcf573ffc0d70b94b31e3` and packages
`4d076593b26175ccb483f8e86255d8185c342e28` match checked remote heads. Pins
remain Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c`, and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`. Selected source gates pass;
the full verdict remains `not_equivalent` (exit 1).

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-timeline-boundary-20261116/`.
The canonical `bundle/` retains sources/references, kernels/C, test binaries,
logs and the unchanged complete typed inventory checker. Canonical and fully
restored archive inventories pass. `completion.txt` binds nine source paths
and two reports to the feature commit.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `0b5e321e6e77c7719ca691b33f709bbf57f21eacda1adcf9b9ce17a9f05d9949` |
| `bundle.tar.gz` | `3eed4fb13a82bcc2ed844329541fcabd3b25e8eeda35f45f2b4d80f17cdb75dd` |
| `bundle/vinix-aarch64` | `336c4f814a8472507d1a24793ed674b2e077b77c741907e8a0a9fac6849403ad` |
| `bundle/vinix-x86_64` | `0a5d9c275d4c9ea5e5b24099e0eddb477f2f9797614fa61b9cd0b1e7c03d1c36` |

Full chain semantics, generic timeline waits, merge, scheduler wrappers,
descriptor reservation/error precedence, modern ABI/Mesa integration,
reclamation and hardware behavior remain open. No Vinix boot, GPU/firmware
execution, hardware test, reboot, SSH or deployment occurred.
