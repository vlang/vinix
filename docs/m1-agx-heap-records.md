# GPU heap metadata reclamation

GPU heap GC now frees an allocation record after removing its pointer from the
heap's list. Released interior records remain owned until GC can reclaim the
top suffix. Statistics readers take the same heap lock as allocation, release
and GC, preventing them from reading a record while it is destroyed. Both
metadata constructors carry verified-free annotations. No owning layout or
firmware-facing behavior changes.

The complete production allocator, compiled with `-gc none -manualfree`, showed
10,000 additional live malloc blocks / 320,000 bytes after 10,000 warmed
allocate/release/GC cycles, despite its record list being empty. The fixed code
retains **zero blocks / zero bytes** in each of three 10,000-cycle samples.
These are host malloc measurements, not kernel slab-rate measurements.

The measurement uses ordinary Darwin malloc (`MallocNanoZone=0`). Default nano
statistics showed an additional 512-block / 16,384-byte step during churn; that
diagnostic and both allocator controls are retained. The original allocator
still retains exactly 10,000 blocks / 320,000 bytes under ordinary malloc. The
zero-growth assertion was not relaxed.

Packaged Asahi owns heap metadata through
[`HeapAllocation` and its `mm::Node`](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/alloc.rs),
transferring the node to deferred garbage or allowing its owner to drop.
Vinix's record is host metadata containing only a VA, size and live flag; it is
not firmware backing. Its pointer never escapes allocator methods. Independent
lifetime review checked whole-heap copies as well: copies occur only during
empty construction, and live manager/context access uses pointers. No lifetime,
locking or aliasing blocker was found.

Offline validation passed:

- ASan/UBSan checks eight release masks, live interior records, suffix-only
  destruction, repeated GC, allocation-triggered GC and VA reuse. Two readers
  perform 80,000 statistics calls while 10,000 reclaim cycles run concurrently.
- Four complete compiled counterexamples detect original-source retention,
  a missing free, an early free and a double free. Early destruction produces
  an ASan use-after-free; double destruction produces an ASan double-free.
  A generated-C checker rejects five free/locking mutations.
- Fresh isolated ARM/x86 kernels build. Native C differs from baseline GC by
  exactly one unlink-before-free block. Four allocator bodies, ten owning
  declarations, nine GPU lifetime bodies and ten event methods match baseline.
  Host C requires both statistics readers to lock without temporary allocations;
  unused getters are omitted from the native kernel. One overlay matches both
  build snapshots. x86 C matches after normalizing compiler path hashes.
- All 56 focused V test files, 150 native storage guards, three existing checker
  selftests, host/native pending-storage checks and native ARM errno probes pass.
  Existing wait, wire, fence, close, async, CPU-cache, VM, sanitized TLB, layout,
  render, packet and source-derived wire fixtures pass. Nine completion, eleven
  render, five compute-credit, seven event-credit and four native error compiled
  counterexamples pass with fresh dependent fixtures.

The fresh allocation report changes from 381 to 379 ARM sites because exactly
two existing metadata constructors are now verified freed; their native
allocation code is unchanged. x86 stays at 289 sites. Source counts stay
833 / 813, and all other per-file/per-kind counts match the complete verified
baseline. Existing allowance-check failures remain; no allowance was changed.

Fresh heads remain Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`f6aa8149e940fa8dfa1cae89c10c1b38a24fc0bb`. Selected package definitions remain
unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The whole-driver audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining stage backing/event destruction, complete
allocator behavior, manager/UAT replacement, safe firmware teardown, reservation
fences, timelines, remaining wire/default coverage, topology and power/reset
behavior remain open. Native allocator rates and GPU behavior remain unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-heap-records-20261117/`.
Baseline is `76fd350e565e5046117dc614990b61e2eff261a2` plus eleven retained source
paths, including one native overlay. Unchanged runner binaries are reused after
source/binary checksum checks; dependent fixtures and kernels are fresh. The
unchanged historical inventory checker verifies the preceding complete bundle,
this complete bundle and a full archive restoration. The original allocator
source is checked against the baseline commit. The Darwin malloc header is
retained with the measurement inputs. `completion.txt` binds sources and reports
to the commit. Generated evidence stays outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `93ef718cbe355d73a6dee681597e800d1bc0076d6df5766dcef35109f4da2759` |
| `bundle.tar.gz` | `96208653451a5b576af52613698707db39a77c9ed885a8ab907c4aaa5a5adb05` |
| `bundle/vinix-aarch64` | `2c4ba8168a9633c951ae007cb4f37deca31f62671bb6b1c1dc456c5dc04507c0` |
| `bundle/vinix-x86_64` | `eefbad1bf327727df22b595f729b119ac3caf02495d42e48ade466ef59df4a15` |
| `bundle/blob-aarch64.c` | `328e55088bfb262a8ac4c4e2b98d2a83caa1033181f9f12534a1a06ea100b8fb` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
