# Checked GPU heap allocation bounds

GPU allocation now rejects invalid requested alignments before applying the
page minimum. Zero alignment still selects that minimum, and smaller nonzero
powers of two remain valid. Size and address rounding reject overflow. Complete
intervals fit by subtraction, so adding a large size cannot wrap past the end
of a sign-extended firmware range. GC retries use the same checked bounds.

The previous source demonstrably accepted alignment `3` and a wrapping 1 TiB
allocation in the G13 shared range. Both original-source failures are retained.
Successful paths now share one metadata constructor after validation. GC,
release, heap construction, statistics locking and owning layouts are unchanged.

Packaged Asahi's
[`HeapAllocator::alloc_inner`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/alloc.rs)
rejects invalid nonzero alignments before applying its minimum and reserves
through `mm::insert_node_generic`. This increment aligns the requested-alignment
rule and prevents invalid reservations in Vinix's existing allocator. Full
allocator behavior remains an open parity area.

Offline validation passed:

- ASan/UBSan executes the complete allocator against 5,940 cases from an
  independent division/remainder model. Cases cover low and sign-extended
  addresses, `u64` limits, empty/exact-capacity ranges, default and stronger
  alignments, invalid alignments and rounding overflow. Invalid alignments, zero
  sizes and size-rounding overflow preserve retained metadata before GC. Existing suffix ownership,
  allocation-triggered GC, concurrent statistics and one-shot destruction checks
  also pass. Three 10,000-cycle host samples retain zero blocks / zero bytes.
- Five compiled bounds counterexamples detect original-source acceptance,
  missing requested-alignment validation, unchecked rounding, missing interval
  bounds and a different post-GC bound. The original binary also reproduces the
  wrapping interval through its standalone overflow probe. Four heap ownership
  counterexamples and both five-case generated-C checker selftests pass.
- Fresh isolated ARM/x86 kernels build. Generated C requires checked `u64`
  rounding, subtraction bounds, identical pre/post-GC validation and one explicit
  metadata allocation. Both scalar helpers allocate no temporaries. Four heap
  lifetime bodies, ten owning declarations, nine GPU lifetime bodies and ten
  event methods match baseline. One overlay matches both native snapshots;
  x86 C matches after normalizing compiler path hashes. Independent lifetime
  review found no lifetime or aliasing blocker.
- All 57 focused V test files, 150 native storage guards, three existing checker
  selftests, pending-storage checks and native ARM errno probes pass. Existing
  wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, layout, render,
  packet and source-derived wire fixtures pass. Nine completion, eleven render,
  five compute-credit, seven event-credit and four native error compiled
  counterexamples pass with fresh dependent fixtures.

Allocation-site counts remain 379 ARM / 289 x86 across 833 / 813 source files.
The fresh report exactly matches the complete verified baseline report. The
existing allowance-check failures remain; no allowance was changed. Host
retention measurements do not qualify native slab rates.

Fresh heads are Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`31cfb40e4272c811b82f4cd8759ef3d67bd69a32`. Selected package definitions remain
unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The whole-driver audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining stage backing/event destruction, complete
allocator behavior, manager/UAT replacement, safe firmware teardown, reservation
fences, timelines, remaining wire/default coverage, topology and power/reset
behavior remain open. Native GPU behavior remains unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-bounds-20261117/`.
Baseline is `eb72207173f63e8e229bea5a0066aacc7b1e5527` plus ten retained source
paths, including one native overlay. Independent unchanged runners are reused
after source/binary checksum checks; dependent fixtures and kernels are fresh.
The unchanged historical inventory checker verifies the preceding complete
bundle, the new complete bundle and a full archive restoration. Original
allocator source is checked against the baseline commit. Historical native
metadata proof modes and their original complete bundles remain unchanged.
`completion.txt` binds sources and reports to the commit. Generated evidence
stays outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `df8ef32f33c87b1db8d72338d6ca6241378c4891255d34a7fad360c19fae3d1b` |
| `bundle.tar.gz` | `a02a406e19230c0ed1e370a7a21c9f91d5584f4ceea28b8253399fc232758e9e` |
| `bundle/vinix-aarch64` | `97f68d890ce88dd55266f68b35c9168d90b79120631c6b9c4ec82aa61b8b3193` |
| `bundle/vinix-x86_64` | `d6d93219e51a9c09c627f3f1388546b76fadab20cb034302da6131743e8c81fb` |
| `bundle/blob-aarch64.c` | `eb58e6041e0eec76e56a6ac759a4c11a46f954da2fbbd705a7cc90486baae0ce` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
