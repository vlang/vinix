# Reclaim G13 queue records at final file-owner removal

Close, detached-queue retirement and orphaned-constructor retirement now free
the queue record after removing its final file-owner row. Backing release keeps
the record alive for retries. Close checks captured queue references before
the manager's already-released fast path and retains nonempty G13 ownership
when the manager is unavailable. All backing and mapping cleanup must succeed
before close destroys logical queues and removes metadata owners.

Independent lifetime review found no blocker. Manager/deferred-list reachability
ends before final disposal. Initial-event and pending-submission users retain
queue references through their final access; released jobs skip queue reads.
Deleting owner rows under the file lock prevents new captures and retry replay.
The disposer has debug assertions for released backing, zero captures and no
deferred link. Production builds omit those assertions; the file-side conditional
guards remain. The constructor allocation is now marked `@[freed]`, after its
failure-only and final-owner paths and native code were verified.

The controlled host close measurement fell from 10,000 retained records /
1,600,000 fixture bytes per 10,000 closes to zero blocks and bytes across three
batches. Both comparisons use `MallocNanoZone=0` and reuse one warmed file.
The initial benchmark created a file per operation; V promoted that test local
to an unreclaimed heap object, adding a separate fixture allocation. Its
diagnostic is retained. The corrected benchmark isolates queue-record retention.
Host queue/manager types and backing services are modeled; native object sizes
and slab rates are unmeasured.

Offline validation passed:

- The full sanitized file-close, VM/mapping, timestamp, namespace and private-BO
  fixture passes in kernel GC mode with fake-stack detection. Its 216 new cases
  cover all three disposal paths, manager absence, captures before VM pins,
  partial cleanup, stopped/released backing and one/three owners. Actual heap
  records become ASan-poisoned only after final disposal; failed mapping cleanup
  retains already-released records. Repeated close does not dispose twice.
- Seven compiled baseline/mutated cases reject missing disposal in each path,
  ignored captures, ignored manager ownership and duplicate-owner disposal.
  Eight native-C mutations are rejected. All 74 focused test files pass.
  Existing sanitized G13 failure handling, 3,640 constructor cases, 3,672 context
  retirement cases and 1,008 deferred-FIFO cases pass.
- Isolated ARM/x86 builds pass. Native C contains one free and exactly three
  final-owner callers; restoring only the close/capture/manager/pop and reaper
  additions gives the baseline bodies. Four owning layouts and 31 backing,
  context, capture, initial-event, pending-submission and heap bodies match after
  string-ID resolution and consistent temporary renaming. The unchanged strict
  x86 checker confirms whole-C equality with its existing path-hash normalization.
  Native and selftest modes also have separately recorded zero exit statuses.
- Marking the verified record removes exactly one ARM diagnostic site:
  379 to 378, with 835 source files. X86 remains 289 / 813. Other per-file/per-kind
  counts match; remaining allowance-check failures persist. No allowance or
  historical evidence checker was changed.

The whole-driver audit remains **not_equivalent** against packaged Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. Logical `WorkQueue` record lifetime
is separate from this GPU-record fix. Allocator backing/accounting, modern
UAPI/Mesa integration, remaining stage backing/event destruction, firmware
lifecycle and native execution/performance remain open or unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-queue-records-20261117/`.
Baseline `8ec593e64572c29ad840e4b6295f480e3a7b4ea6` plus only `gpu/g13.v`
and `file/file.v` overlays was built in a private worktree. Pinned Omarchy/package
revisions remain `3b36b9e19ea00a6c21492098308a7f44a8091564` /
`6aa71681da0fa53944f230e2d6b807bf852f2b0b`. Complete sources, C, kernels,
inventories, baseline, negatives, source audit and review are retained. Initial
fixture compile/scope, retry-bound and negative-assertion diagnostics remain
with passing final runs. The pre-annotation ARM build is also retained; its C
matches the final C, without claiming identical kernels. The original inventory
checker verifies the complete bundle and full archive restoration.
`completion.txt` binds committed feature sources/reports to those bytes.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `7bceddafc88e78ff4fc3b5aa3fc182e14ae5385b87847f506a54a774ba114afe` |
| `bundle.tar.gz` | `e065b66895ada41760b3759056d4fb7a80bd4b5aa95a754732bcd86eb03d7cb4` |
| `bundle/vinix-aarch64` | `025b009bdb83756a358f8b3df6d78664cc50776c8b16bdfdb79874b36bffefb9` |
| `bundle/vinix-x86_64` | `234eeffaf383b8abc9c8b470fd4934696441cb2698bb717ee0aca3a3bb259b2b` |
| `bundle/blob-aarch64.c` | `4cae4c6bfdd6caa7a75081ca0c8a1d6242efba2ae2b6b9b8a9cc7fa99181eb27` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
