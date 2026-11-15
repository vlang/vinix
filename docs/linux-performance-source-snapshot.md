# Compact performance source snapshots

The fixed performance adapters can now build from a verified source snapshot
instead of charging and repeatedly scanning an unrelated full checkout.
`stage-source.v` stages the declared source directories and helper scripts,
expands their internal relative module-link targets and records every included
file hash, size, mode and literal/resolved link target. It verifies both source
selection and destination contents before publishing a fresh external receipt.
The receipt verifier rejects missing, added or changed staged entries, modified
source inputs, overlapping roots and a changed fixed seed selection.

The selection includes V, C/header, shell, Markdown, JSON/text and assembler
source files plus module/license files; explicitly selected helper files and
link targets are included regardless of extension. Git metadata, results and
unselected build outputs are excluded. Absolute, escaping and dangling links
are refused. Source files, aggregate bytes, nesting and entry count are bounded.
This is a source closure for the fixed adapters, not a complete repository copy
or a replacement for their existing prepared-input inventories.

The execution snapshot has 294 typed entries and occupies 2.7 MiB, compared with
roughly 509 MiB for the preceding checkout. It uses the frozen `fe3f4f6cb` sampler
source from the retained warmup evidence. The final staging implementation
reproduces every executed source entry, hash, mode and literal link target.
Normal/production source controls cover internal directory cycles, alias seeds,
forced file-link targets, read-only directory and nondefault link modes, source
and destination changes/additions, overlap/freshness, escaping/dangling links
and oversized source refusals. Both slab profiles run these controls in the
public heap build gate.

Unmodified owner and ARM adapter sources build from the snapshot and pass their
existing normal/production qualification: 86 owner controls, 16 ARM owner controls
and 18 adapter controls per mode. The selected production executables are copied
with their qualification hashes. No old large source tree is needed by their
runtime input inventory. Complete compiler trees, literal SDK inventories,
kernel/desktop/base hashes and all active runtime outputs remain covered by the
unchanged preparation and runtime checks.

The kernel is the same production, tracking-enabled ARM ELF used by the earlier
run: isolated source `cab44e91988c37aae1bab7af0fe7183dcd5ddd8a` plus the qualified
procfs builder fix. The host frontend is frozen `cbfc1be` with tracked source at
`7a51d7a21849d86d09280dbc168f8fffe7c1dbca`; the sampler compiler remains
`53debcfe66952ba952d64b2b94dbb2408bed6992453d1ac6bad5889e4bd1ec7e`.
No kernel, sampler, C probe, operation count, grace wait, scenario or guest
configuration changes here. The three-second command limit, five-second sample
bound, disk floors and 4.5 GiB working-state ceiling are unchanged. Tool builds
and host controls run outside the active charged roots.

Supervised preparation and the complete fixed ARM run pass input-integrity,
deadline, resource and `ECHILD` cleanup checks. All six scenarios, 44 measurements,
40 cohorts, 80 raw snapshots, 720 class pairs, 800 delta rows and 40 warmup proofs
are present. All live-object and large-page deltas and corruption counters are
zero. All four churn programs complete 300 measured runs with zero reported
retained physical bytes. The 1,095 runtime samples retain a maximum apparent
charge of 1,651,646 KiB, minimum free disk of 45,488,220 KiB, maximum sample
window of 0.531 seconds and maximum sample-start gap of 1.030 seconds.

Strict flatness still rejects five backing-page rows, independently with both
the preceding complete checker and the warm-proof consumer:

| Cohort | Class | Objects before/after | Pages before/after |
| --- | ---: | ---: | ---: |
| Hardlink, `/tmp` | 256 | 8709 / 8709 | 142 / 143 |
| Hardlink, `/tmp` | 512 | 7026 / 7026 | 230 / 231 |
| File, `/root` | 256 | 8709 / 8709 | 143 / 144 |
| Rename, `/root` | 256 | 8709 / 8709 | 144 / 143 |
| UNIX connect, `/root` | 1536 | 35 / 35 | 6 / 7 |

This resolves the host scan-time blocker; it does not establish why each guest
page changed or qualify those changes as flatness. No full x86 performance run,
broader application/ABI acceptance or allocation-allowance change is qualified
here. The diagnostic observation output remains `qualification=false`.

Evidence is retained at `/Users/alex/.cache/vx-si-1115-evidence`, archived as
`/Users/alex/.cache/vx-si-1115-evidence.tar.gz` with SHA-256
`95ab138eeccba52b0f6c05ab10f4f79578738613a6b0422b6892f1918234e4be`.
The unchanged archive checker passes the complete named-root comparison of
logical bytes, paths, types, modes and literal links, including nondefault
symlink modes from the source controls. Original roots are retained. The bundle
contains source receipts, exact replay, historical and final control sources,
normal/production qualification, prepared media, generated C, executed binaries,
full serial/input/cleanup/resource evidence and both strict refusals.
`dependencies.json` rechecks the preceding compiler, kernel and warmup archives.
The retired serial hash is
`380bc0bb1d6ec47fa0cee318852f0a55f42be5b5fd22f5011df03d915d27dc86`.
