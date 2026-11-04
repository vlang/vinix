# Exact emitted slab-retention transcript gate

`flatness-check.v` adds a separate memory gate to the maintained six-scenario,
one-round `new=` transcript validation. The shared report checker already
requires complete measurements, expected operation/churn counts, one completion
marker and no fatal/error marker. It does not require zero slab retention.

The new checker reads every emitted `PERF-OPS` size-class/large-page count and
`PERF-SLAB` object/page count before checking the derived `bytes_per_op` rate.
Every exact count must be zero. One retained 16-byte object over 200 operations
rounds down to `bytes_per_op=0`; opposite changes in two classes can also cancel.
Both cases are refused. Missing, malformed, duplicate and unknown delta fields
are refused. No baseline is required for this absolute emitted-delta check.

The original four `PERF-CHURN` physical-retention rows and `PERF-CACHE` row are
included verbatim in output for separate interpretation. Page-cache growth after
the 32 MiB cache workload is expected and is not blindly rejected. Zero emitted
slab deltas do not establish zero physical retention or acceptable desktop
performance; those measurements and allocation sites still need review.

The existing measurement producer does not validate its second ops slab read
or prove complete, matching class inventories. This checker cannot establish
that unreported classes were successfully observed. It does not change the
producer or weaken the historical report checker.

Build `flatness-check.v` in normal and production modes with the selected pinned
V and `-path '@vlib|tests/desktop-perf'`. Run both binaries' `selfcheck`, then
`check SERIAL_LOG` against the immutable captured guest transcript. Keep generated
results, pins, commands and actual exits in a fresh external state directory.

The checker reads captured bytes only. Adapter/outer exits, original kernel
audits, immutable input receipts, timeout and process retirement remain separate
mandatory evidence. No guest or current-main kernel qualification is claimed.

## Host checks, 2026-11-04

Source base `5cbb26d56073b43f0fbfefd44da1dc1d9f8a94c4`, plus the three new
V source files in this change. Normal and `-prod` builds each passed the explicit
complete-transcript acceptance controls and all 30 refusals, including one
16-byte object hidden by integer division, cancelling classes, page-only growth,
overflow, duplicate fields/rows, malformed markers and quoted-program spoofing.
Each executable also returned the expected status1 for usage and an absent log.

Raw state, literal commands, the cleared 19-key private environment, generated C,
binaries, source/tool maps and actual statuses remain outside Git at
`/Users/alex/Library/Caches/vinix-codex/section14/perf-flatness-host-20261104-01`.
Its concise `result.json` has SHA256
`95759f962954c8f9ed2d4e2de2801bf94acb7de22790334574e555bbcc9ddb18`.
The successful attempt is `attempt-02`. The first normal bootstrap's actual
status1, source and C are preserved; an explicit `stdlib.h` include supplies the
shared parser's `strtod` prototype without relaxing compiler diagnostics.

The pinned ff75 V and clang23 built both modes with `-nocache`, `-gc none`,
`-manualfree` and incompatible-pointer errors enabled. Direct before/after maps
matched; the original V state checker also verified the unchanged selected
compiler literal tree. Endpoint observations kept the worktree and raw state
below 13 MiB, including the failed attempt, with an 8 MiB margin reserved
inside the 32 MiB ceiling; free space remained above the 2 GiB admission and
1 GiB action floors. These are endpoint observations, not continuous bounds.
The documentation report was added after the tested source capture. No guest,
producer-snapshot, complete host SDK or hermetic-toolchain claim is made.
