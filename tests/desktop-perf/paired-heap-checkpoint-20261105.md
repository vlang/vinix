# Paired heap runtime checkpoint, 2026-11-05

The frame baseline completed all six scenarios. Its unchanged strict heap
checker refused backing-page flatness. The atomic run then stopped at the
native free-space floor; atomic runtime qualification and Section 14 remain
open. This report records a blocked checkpoint.

Subsequent post-run checks and complete failed-bundle preservation are recorded
in [the evidence closure report](failed-runtime-bundle-check-20261105.md).

Artifacts remain outside Git. Let `C` be
`/Users/alex/Library/Caches/vinix-codex/section14`,
`R=C/perf-six-x86-20261105-01`, and
`S=C/perf-runtime-host-20261105-01`.
Runtime source worktree `/Users/alex/code/vinix/build/package-perf-runtime-worktree`
remains at `984fdc1897c7da4b166e2d93baa548cbe8c48e2d` with unchanged source.
The source/adapter qualification is documented in
[full-observer-adapter-check.md](full-observer-adapter-check.md).
The separate diagnostic consumer is committed as
`ba9ec21b3bbdf156164fe4187f18b7548fc9c66b`; it always records
`qualification=false`.

Both preparations used the same base, desktop, compiler, strict Clang/musl
closure and explicit MacOSX26.5 SDK. Actual observer/init ELF bytes and generated
V C were identical between images; combined C changed only its legacy include
path. Independent C/ELF review passed. The workload fixes one round of
`ops,churn,cache,idle,apps,drag`, settle 3 seconds, measure 5 seconds,
3072 MiB, two CPUs, TCG and no network. Adapter/owner deadlines remain
2400/2520 seconds, log cap 32 MiB, inclusive dual-size ceiling 4.5 GiB,
admission/continuation free floors 2/1 GiB. All failed attempts remain charged.

The completed frame owner and adapter both returned actual status 0, with
exact guest DONE and equal complete input maps. Its 1,917 child/cleanup samples
had maximum start gap 1.028972042 seconds and complete window 0.393152375 seconds.
The post-run original full kernel audit passed with unchanged inputs/manifest
and original group absence/ECHILD. Legacy completeness/emitted-delta gate
returned 0; the unchanged full gate returned 1 for a nonzero exact backing-page
delta. The independent normal/production observation outputs matched: 44
measurements, 40 pairs, 80 snapshots, 640 canonical deltas and 560 class rows.
All object/large-page deltas and both corruption counters were zero; all four
churn pairs were flat. Nine size-256 page changes remained, each with live
objects 4555 to 4555:

| Cohort | Class pages before/after | Total reported pages before/after |
| --- | --- | --- |
| proc_read /tmp | 305 / 306 | 1903 / 1904 |
| memfd /tmp | 307 / 308 | 1910 / 1911 |
| rename_over /tmp | 308 / 307 | 1913 / 1912 |
| mkdir /tmp | 307 / 308 | 1913 / 1914 |
| unix_connect /tmp | 307 / 308 | 1913 / 1914 |
| rename /root | 308 / 307 | 1919 / 1918 |
| hardlink /root | 307 / 308 | 1918 / 1919 |
| unix_connect /root | 308 / 307 | 1919 / 1918 |
| unix_datagram /root | 308 / 307 | 1919 / 1918 |

These are observations; no cache/fragmentation cause or flatness acceptance is
inferred. Raw performance metrics remain in the serial/report output. Host
conditions differ, so isolated throughput conclusions are not claimed.
`PERF-SHOT` markers were present; the fixed argv requested no screenshot files
or separate JSON report. The printed report is in the owner `command.log`.

Atomic preparation and its pre/post preparation original audits passed, with
equal complete preparation maps. The runtime owner later returned actual
status 1: `actual df below required floor`. Its final raw sample retained
757,640 KiB free, 2,433,073 KiB apparent and 1,810,164 KiB allocated across
charged roots. The 1,078 child/cleanup samples had maximum start gap
1.892540667 seconds and complete window 1.868043208 seconds. Cleanup reports
ECHILD; child status remains explicitly unavailable after observer refusal.
Fresh direct PID/PGID probes confirmed owned QEMU 51656 absent; the frame QEMU
87581 was also independently confirmed absent. Unrelated guests were left
untouched. The after-endpoint files record Debian 23708 only; they do not prove
Android 93372 remained present. The pre-atomic guest regex matched a concurrent
hash command and missed symlink-launched guests. That raw file is preserved as
an incomplete host guest inventory. Direct own-QEMU probes selected exact
PIDs/PGIDs. Host identities, exact argv, executable pins and conditions are in
`R/host-before-{frame,atomic}-01` and `R/host-after-{frame,atomic}-01`.

The retired atomic serial contains 34 ops rows, 68 snapshot blocks and 544
delta rows, ending after symlink /root and `QEMU: Terminated`. Eight page-only
rows were emitted: socketpair/tmp size-384 +1; fork/tmp size-96 +1;
memfd/tmp size-256 +1; file/tmp size-256 -1; unlink_open/tmp size-64 +1;
rename_over/tmp size-256 -1; unix_connect/tmp size-256 +1;
unlink_open/root size-256 -1. All emitted object/large-page deltas and
corruption counters were zero. This incomplete transcript supplies no atomic
qualification. No adapter final status receipt or after-input map was produced.
Its transcript gates and post-run original audit remain pending the 2 GiB
admission floor. `R` remains partial; no complete runtime-bundle manifest or
freeze is claimed. ARM preparation/execution remains pending.

Exact retained SHA256 pins:

| Artifact relative to R unless prefixed C/S | SHA256 |
| --- | --- |
| prepared-frame-01/prepared.json | `f302522f841759e2d659c3dcf7a410f9184e9859a62b22833bea3a8acb9299e4` |
| prepared-frame-01/results/serial.log | `df7faf539b3b0e256fb810b48d2ca0a9480d35594d88c7d76eb6613c0e28a4c8` |
| run-owner-frame-01/result.json | `b181472b5c3fa0f41a45e7dd11ad5390201db4fac1a36924e4f0261c9e5e4017` |
| run-owner-frame-01/inputs-before.json and inputs-after.json | `6b7f094bfd8e6bf1215a3861cf48e6be82b849b9dccc8e5d20f8173839ab4f2e` |
| audit-frame-after-run-01/audit.json | `4dbdff0b204d03e2229f9d4e408318d3138a53b4b185018426463bb6aae4f8f0` |
| C/frame-peer-baseline-fresh-20261026-seal-01/complete/inventory.json | `918073b63294c83608ef2d08b7420929c1d5148fc0464df4798a95459d71e8d9` |
| S/observation-host-01/actions/production-retired.stdout | `728de9250ef5f293ba2f6836960f7df8b85f0690b53018740b8add1ffcf60936` |
| prepared-atomic-01/prepared.json | `2ea87e65651a96cf35191850745d5bbddbea0d53409087748ba396174af1b72e` |
| prepare-owner-atomic-01/inputs-before.json and inputs-after.json | `d2e8fea60bfbd960d696418d5bb7c1085438e6e60c98a81a857dfd3c1b21b01b` |
| audit-atomic-before-prepare-01/audit.json | `6cb332f5769e9debc13fe22e94e688d1eea9b8311864f2da4f13bc0384c568be` |
| audit-atomic-after-prepare-01/audit.json | `8f602e83692ffc031a4e50f684ba2025cfc1674f34a7aee5594ac50ca868409e` |
| C/matched-peer-frame-atomic-fresh-20261026-seal-01/complete/inventory.json | `e82671ca13c4d46b18d1d9762d661f4f392be0ee888d0fb20d1de21f540c54f0` |
| prepared-atomic-01/results/serial.log | `82feae53df6df19bd6ad80db72333267444fbef880afa045a4e6c951620df66b` |
| run-owner-atomic-01/inputs-before.json | `1e81b425fa5d17571040df69d743f72a4dffdd2c17aaf77b2d7600626d3920d3` |
| run-owner-atomic-01/supervisor.json | `46ef3d04679002441299b74c919645e29770b371801cdf56b7759ad01bddf722` |
| run-owner-atomic-01-outer.log | `95445a3b3bcd56a6fda35fa10b5284ff206485c99916507b897ede186c737778` |
| host-after-atomic-01/process-status.json | `940ab2a8197ab54820c69e01b975a5c188758696bfef4f4d32d64bfcffae5224` |
