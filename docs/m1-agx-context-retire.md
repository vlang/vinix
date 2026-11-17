# G13 context acknowledgement before queue teardown

Normal queue destruction now sends the firmware's DestroyContext command and
waits for acknowledgement before invalidating queue mappings or releasing their
backing. The command copies firmware-written context bytes 0, 1, 4 and 0x23,
uses the versioned packed pointer offsets for 12.3 and partial 13.5, and leaves
the remaining bytes zero. Byte stores avoid unaligned native pointer stores.

The queue owns a scalar retirement phase. Publication marks it pending before
the fallible doorbell. A published failure retains the context, queue and VM
ownership and cannot replay potentially recycled firmware IDs. Even a later
acknowledgement leaves that queue quarantined until stopped-firmware teardown.
Successful acknowledgement marks it complete and collects only the private
and GPU-read-only garbage counts captured before sending, including counts
below the ordinary GC threshold. A subsequent UAT-cleanup retry skips command
publication, context reads and collection. Unpublished/stopped cleanup keeps
its existing bypass. Independent review found no lifetime, locking or ABI blocker.

Offline validation passed:

- ASan/UBSan with `-gc none -manualfree` and fake-stack detection passes 3,672
  production queue/heap/channel cases, 24 complete 48-byte ABI comparisons and
  69 invalid-input cases. Live pins and releases after the snapshot survive.
  Poisoned context storage detects reads after successful retirement; repeated
  teardown releases backing once. Timer, doorbell, UAT and PMM are host services.
- Eleven compiled baseline/mutated counterexamples fail their intended ABI,
  ownership or retry assertions. Seven generated-C mutations are rejected.
  All 71 focused test files pass. Existing sanitized G13 failure handling,
  512 teardown cases, 256 threshold boundaries and 528 real heap-GC cases pass.
- Isolated ARM and x86 kernel builds pass. ARM C confirms stack-only new
  helpers and the exact context-before-UAT gate. The queue layout adds one
  scalar field, and its constructor adds that field's default. Fifty-two heap,
  backing, cache, queue-owner, channel and stopped-drain bodies match baseline
  after string-ID resolution and consistent temporary renaming. The unchanged
  strict x86 checker confirms whole-C equality with its existing path-hash
  normalization.
- Allocation sites remain ARM 379 and x86 289, with identical per-file/per-kind
  counts. Adding `g13_context.v` changes the ARM source graph from 834 to 835;
  x86 remains 813 files. Existing allocation-allowance failures remain. No
  allowance or historical evidence checker was edited.

The source-reference gate passes against packaged Asahi
`bed544bdf93a496ebf70ba180923bab12b6e01cf`. This implements its command fields,
acknowledgement and captured-prefix collection rule. Asahi queues dropped
contexts for invalidation on a later allocator borrow; Vinix performs normal
retirement synchronously under the existing manager lock. That scheduling
difference and conservative retention after ambiguous publication remain open.
No native firmware timing, slab-retention rate, object-size class or performance
equivalence is established.

The whole-driver audit remains **not_equivalent**. Modern UAPI/Mesa integration,
allocator backing/accounting, remaining stage backing/event destruction,
firmware/cache lifecycle, timestamps, fences/timelines, wire defaults, topology,
power/reset and native performance remain different or unqualified.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-context-retire-20261117/`.
Baseline `144702f4e8360b28df56d0c4491b7bb3d8de5b7f` plus only
`fw/channels.v`, `gpu/g13.v` and new `gpu/g13_context.v` overlays was built in a
private worktree. Pinned Omarchy/package revisions are
`3b36b9e19ea00a6c21492098308a7f44a8091564` /
`6aa71681da0fa53944f230e2d6b807bf852f2b0b`. The complete bundle retains source
snapshots, C, binaries, inventories, baseline, negative cases, source audit and
lifetime review. Earlier test/checker diagnostics and the successful ARM build
before the helper-file split remain retained. The original inventory checker
verifies the full bundle and archive restoration. `completion.txt` binds
committed feature sources and reports to those bytes. Raw results stay outside Git.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `389bf38f1967e80e0a04b860f5e054a04fc64f5fbc20a8f3613f3373142dd270` |
| `bundle.tar.gz` | `b31accdef0eecd76426874b91ab1312fb7cd4b34bbd1c59a9f5250c44a7ea922` |
| `bundle/vinix-aarch64` | `f7873e6cf3bf7b4bd49298070e904830294fe11685aa767117180d15a00c18df` |
| `bundle/vinix-x86_64` | `472aafda6976c5cce14cee619f9e63f912805d58d2e60d45197e40f5532d38ed` |
| `bundle/blob-aarch64.c` | `0c8b3e3837589708915027edb67a503f40f23710dfb95cbddd65820c34bcb774` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
