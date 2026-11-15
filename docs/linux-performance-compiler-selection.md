# Performance payload compiler selection

Both retained performance adapters now accept an optional
`VINIX_PERF_SAMPLER_V` canonical absolute executable. They keep the selected `V`
for the maintained initializer frontend and pin both compiler executables.
An absent override preserves the original single-compiler behavior; an explicit
empty, relative, missing, nonexecutable, directory or symlink selection is refused
without fallback. Initializer generation overrides `V`, `VINIX_V_COMPILER` and
`VEXE` together and retains `init-v.env.json` in the prepared input hashes.
The public host gate includes eight selection controls. A local module link
lets these controls import the same maintained `hwhost` implementation.

The first ARM staging attempt failed because the qualified sampler compiler
does not implement the `version` command required by `find-v.sh`. Setting only
`VINIX_V_COMPILER` also allowed an inherited `V` to take precedence. The corrected
staging uses frozen host V 0.5.2 `cbfc1be` for initializer generation and the
previously qualified target compiler, SHA-256
`53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`,
for the sampler. Its unchanged-parent/derived-source audit passes. The current
compiler's separate production printf precision issue remains documented in
the [sampler report](linux-performance-sampler-builds.md); no generated C or
diagnostic policy is patched here.

Both host adapters compile and pass 18 ARM / 37 x86 controls. The real initializer
frontend passes on both architectures with all three inherited compiler variables
deliberately pointing at a missing executable. Its resulting initializers link
with strict format and pointer diagnostics on both targets. The final public
host suite passes, including both slab profiles in normal and production modes,
cross-profile refusals and 100 PTY owners with flat descriptors. Earlier attempts
remain visible: the first failed the PTY assertion, and two subsequent attempts
failed with ENOSPC or an unsuccessful fixture copy. The first PTY failure's cause
is unresolved; its surviving fixture and all attempt logs are retained.

ARM preparation completes with the fixed six-scenario configuration, strict
initializer/sampler links, ELF inspections, ordered base/overlay FAT media,
private firmware variables and the ext2 workload disk. Private regular copies
preserve the mtools/readelf dispatch names. The selected kernel remains the
previously qualified isolated `vx-ec-1115/fixed-build-arm` kernel. Prepared receipt
SHA-256 is `4d2a19738b97e73d8407b1c52b34f6f142a04b1f65a6ff2a908686f387b433a0`;
a final check confirms all 336 input hashes unchanged.

No guest is launched in this qualification. The recorded shared-volume reading
is 130,096 KiB available, below the existing 2 GiB admission and 1 GiB live disk
floors. This is a direct staging diagnostic; a current supervised preparation
profile, including explicit support for the compiler pair, remains pending.
Actual PCI firmware boot, ops/churn/cache, idle/apps/drag, allocation-site results,
the cached x86 root's missing curl and broader section 15 application acceptance
remain open. No kernel allocation or lifetime code changes in this fix.

Source baseline is `6595e335b2cdda9e84c3eb78c31a2e4df8d36025`, plus the captured
feature sources; concurrent unrelated commits are outside this change. Complete
available build/staging evidence, failed attempts, selected file inputs, ARM
sysroot, sources and public test outputs remain at
`/Users/alex/.cache/vx-six-1115/bundle`. Installed compiler/loader dependencies are
not claimed hermetic. Originals and earlier audit bundles remain intact.

The maintained `tests/packages/wine-workspace-archive.v` records and separately
checks the retained workspace's complete logical bytes, sizes, types, modes and
literal links without another compressed copy on the constrained volume. Its
sparse/archive and inventory refusal selftests pass. Inventory receipt
`/Users/alex/.cache/vx-six-1115-inventory.json` has SHA-256
`f43421a1ddc51bb7c0bf4deedbb2a37b26009bb7f802dc09ed4b14a97b078a2d`.
This records evidence integrity; it does not replace a launch audit or qualify
the six-scenario guest workload.
