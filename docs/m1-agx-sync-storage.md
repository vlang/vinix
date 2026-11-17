# Accept modern sync lists beyond 64 records

Modern SUBMIT now accepts more than 64 input or output sync records, matching
the packaged Asahi parser's dynamically allocated list. The combined count is
checked for u32 overflow before copying; allocation remains fallible. Lists
through 64 records stay inline, and the legacy interface retains its original
64-record limit. This changes no wire record or advertised command-count limit.

The syscall owns temporary input/output spans and frees them on every exit.
Pending work receives an independent input copy before backend locks. Failures
free it through the submit caller; successful registration transfers it to the
worker, which releases it after its final dependency read and callback
retirement, before dropping queue/VM ownership. Output publication finishes
before the syscall frees its temporary output span. Existing retained syncobj/
fence metadata preserves pointer lifetime across replacement and name deletion.
Independent lifetime review found no blocker.

The reference is Linux-Aurora `bed544bdf93a496ebf70ba180923bab12b6e01cf`,
`file.rs::SyncItem::parse_array`. Its checked count, fallible KVec capacity and
wire-order per-record reads are compared against pinned source bytes. Rust is
not executed. The isolated Vinix baseline is
`f8d2c9d85bb78c34e97b26bdee880c2ca12656ed`, with six sync-storage kernel
overlays. Concurrent event-manager edits are excluded.

Passed offline checks:

- The complete ASan/UBSan asynchronous suite in kernel GC mode. New tests run
  64 input/output size combinations through 1,025 records per direction,
  checking independent storage, immutable fence snapshots, last-input waits
  and last-output publication after userspace storage is freed.
- 320 allocation/copy/lookup failure cases and 140 prepare/barrier/callback/
  registration failure, stopped-job, detached-name and immediate-completion
  cases. Count overflow performs no user read; huge allocation refusal is
  injected without allocating the requested host buffer.
- Five compiled negative variants fail designated assertions for a restored
  count limit, omitted parser cleanup, a borrowed pending copy, omitted worker
  cleanup and omitted failure cleanup. Compiler failures do not qualify.
- Six warmed batches of 1,000 stage/copy/release calls, with 65 or 1,025 inputs
  and outputs, retain zero host malloc blocks and bytes. This isolates the new
  buffers; it does not claim complete-submission or native slab leak freedom.
- The complete sanitized DRM wait/sharing suite, including its legacy
  timeline-boundary, export-reservation and lookup tests. All 71 source-contract
  test files pass against an isolated source snapshot. Accessor checks retain
  negative controls; the cleanup-site inventory now includes the preceding
  render-SCS rollback, with explicit destruction/disposal order checks.
- Isolated AArch64 MP and x86_64 builds. Seven native bodies have no hidden
  allocation; explicit staging/pending owners have checked cleanup and transfer.
  Thirteen preparation/completion/queue/close/timestamp/poll bodies match the
  baseline after compiler discard-path normalization. The unchanged 18-body
  modern-adapter guard and original strict x86 C comparison pass.
- Allocation diagnostics keep every file/kind count: ARM 377 sites across 840
  sources, including one new source; x86 289 across 813. Existing allowance
  failures remain; the allowance list and historical checkers are unchanged.

Full parity remains incomplete. Native allocation is contiguous and uses
different allocation sizes/counts from Asahi's KVec; combined-invalid OOM/fault
precedence is not equivalent. Cumulative timeline chains, zero-point timeline
outputs, existing metadata reclamation, purge backing and Mesa migration remain
open. No GPU access, firmware execution, Vinix/QEMU boot or reboot occurred.

Evidence is retained at
`/Users/alex/.local/state/vinix/omarchy-m1-sync-storage-20261117/bundle/`.
It contains source snapshots, build V inventories, C/ELFs, test programs and
executables, reference sources, negative cases, diagnostics and review. The
preceding original queue-SCS archive is checked unchanged. Complete restoration
and both named archive roots are checked; a post-commit receipt binds feature
bytes to the bundle.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `feed08607aa5a36a77f0b42f6ee3cf13b6e0ac6967b366a3d8f132ebc9ac0164` |
| `bundle.tar.gz.inventory.txt` | `448b8b0277adf57dd2cea5063628fa7253b4ed419712e045955a639923d6d794` |
