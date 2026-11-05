# Full V slab observer

Host controls, both strict static target links and independent generated-C
reviews passed; see [the qualification report](heap-qualification.md). Native
measurements and architecture-adapter qualification remain separate gates.

`measure-v/main.v` owns the ops/churn observer. `perfproducer` generates its C
and includes the unchanged, hash-pinned `measure.c` under an entry-point rename.
All operation probes and legacy non-heap modes retain their original C bytes.
Architecture-adapter integration is qualified separately.
The compile-only `heap-producer-source.v` front creates no boot/root media.

`perfheap` reads successful, complete snapshots into fixed storage. It requires
the exact header, all 14 ordered classes with matching class-name/size columns,
one large-allocation row, the written-after-free footer and final EOF. Empty,
failed, truncated, extra, reordered, duplicate, mismatching and overflowing data
refuses admission. Both targets must report 4096-byte pages. The module records
the frozen kernel revision and procfs source hash defining this schema.

The guest preserves the 200-operation warmup/cohort and both 13-second grace
periods, and all four 300-child churn warmups/cohorts with seven-second waits.
It retains complete original before/after snapshot bytes inside bound
`PERF-HEAP-BEGIN/END` records. `PERF-HEAP-DELTA` includes all 14 exact object AND
backing-page deltas, large pages, and both original written-after-free counters
plus their signed change. Legacy summary and allocation-site lines remain.
Churn program names are quoted in raw-record identities to preserve spaces.

Observation and qualification are separate. The parser accepts positive footer
counters as valid data. `qualify_flatness` requires every exact object/page and
large-page delta zero, and BOTH footer counters zero. It refuses newly detected
or increasing corruption and exposes preexisting nonzero counts as unclean;
a decreasing counter cannot hide the earlier finding. The observer keeps
measuring nonzero deltas so the whole cohort can be investigated. Qualification
must apply this policy to every one of the 40 complete snapshot pairs, together
with maintained transcript completeness and actual process/input receipts.

Physical retention still uses the existing C process-snapshot helper, with
checked physical header/subtraction and preserved snapshot ordering. This does
not certify that helper's full process-table validation. The cache workload and
its expected page-cache growth remain separate from slab flatness. Allocation
site reading retains the unchanged C helper's existing limits.

`heap-selfcheck.v` exercises production-active parser, real reader, truncation,
class identity, exact arithmetic, hidden/cancelling deltas and footer-policy
controls. Reader cases use ordinary files and already-closed pipe writers.
The generated success paths still require inspection for unintended V heap
promotion. Static-symbol visibility, virtual C globals, LP64 printf types,
fixed pre-fork char-pointer vectors and signal-handler types require strict
two-target compilation before any new prepared performance image is admitted.

The earlier `flatness-check.v` remains an emitted-delta checker with its original
limited scope; it does not replace full-snapshot qualification. No current-main
kernel integration, ARM paired baseline, native performance or full memory
qualification is claimed by these sources.

The qualification recipe uses fresh external state, the selected independent
compiler derivation, clang23 and a coherent private compiler environment. Compile normal and
production host parser/reader and full-transcript consumers, then run their
explicit controls and CLI refusals. Next generate both target observers through
the maintained V helper and statically link with pointer and format diagnostics
as errors. Retain the original probe copy, generated V/combined C, exact argv,
source/tool input maps, ELF headers/segments/symbols and actual statuses.
Inspect repeated success paths for V heap promotion and verify virtual C
globals, signal types, fixed char-pointer argv and LP64 formats before booting.
Changed architecture adapters need their source-bound host controls before
new preparation profiles can select them; unchanged workload/owner controls
retain their existing scope. The report identifies the completed host and
compile-only checks; no new image or guest measurement has run.
