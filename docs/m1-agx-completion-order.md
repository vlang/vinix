# G13 completion before deferred cleanup

Render and compute now publish the cached hardware result before disposing of
command backing. A failed or delayed invalidation retains the graph in quarantine
without changing successfully completed work into a failed command. Render
results are read once; cleanup retries consume no callback and preserve the
original result. Hardware and protocol errors keep their existing failure paths.

This follows packaged Asahi's
[workqueue completion](https://github.com/omacom/linux-aurora/blob/bed544bdf93a496ebf70ba180923bab12b6e01cf/drivers/gpu/drm/asahi/workqueue.rs):
`signal()` completes commands before enqueueing their deferred destruction.
Stamp proof, independent render-stage retirement and event accounting precede
the callback. Physical backing and event tickets remain owned until cleanup.

The file worker may release submission pins after the callback. Queue teardown
takes the manager lock and refuses unreleased jobs; retained queue ownership
also preserves the VM. Immediate cleanup runs under the same manager lock.
Callback pointers/data are cleared before invocation, and cleanup uses only
job-owned backing. Independent lifetime review found no blocker.

Offline validation on 2026-11-16/17 passed:

- ASan/UBSan executes both actual reapers, completion helpers and the production
  queue-release guard with injected physical disposal services. Forty compute
  ring/stamp-wrap and cleanup-refusal cases, eighty render-stage masks, partial
  errors, reverse retirement and prepared ownership remain covered. Real heap
  callback state is freed on first invocation. Successful completion survives
  cleanup refusal; three hardware error statuses per engine remain failures.
  Queue release is refused after submission pins end while backing remains,
  then succeeds after cleanup retries. Render result reads stay one-shot.
- Nine compiled completion counterexamples fail designated assertions: late
  callbacks, false failures, lost hardware errors and missing queue ownership
  guards for both engines, plus render result rereading. Eleven existing render,
  five compute-credit, seven event-credit and four native error counterexamples
  also pass with fresh fixture builds.
- Fresh isolated ARM/x86 kernels build. The committed generated-C checker proves
  both reapers reduce exactly to baseline after restoring callback ordering and
  the render cache guard. Eight owning/event/timestamp declarations, ten event
  methods, twelve preparation/cleanup/queue/stop bodies and file/pending
  ownership/error functions match baseline. One native overlay matches both
  snapshots; x86 C matches after normalizing compiler path hashes.
- All 55 focused V test files, 150 native storage guards and three checker
  selftests pass. Eight pending/timestamp helpers reject 24 allocation mutations
  on host/native C. Native ARM errno-width probes pass. Existing wait, wire,
  fence, close, async, CPU-cache, VM, sanitized TLB, layout, render, packet and
  source-derived wire fixtures pass, including 584 stage timestamp cases and
  10,240 event completions.

Allocation counts remain 381 ARM / 289 x86 across 833 / 813 source files. The
feature audit is fresh; the preceding complete baseline report is reused after
checksum and full typed-inventory verification. The existing allowance-check
failure remains unchanged. Native heap rates and hardware behavior are unmeasured.

Fresh heads are Omarchy `3b36b9e19ea00a6c21492098308a7f44a8091564` and packages
`f6aa8149e940fa8dfa1cae89c10c1b38a24fc0bb`. Selected package definitions remain
unchanged: Linux `bed544bdf93a496ebf70ba180923bab12b6e01cf`, Mesa
`b7b03c5b3b8abe1e040d6056dc62c01b02d3639c` and m1n1
`b4654b32941d51afdb77579d63e7cb1aa6c03ecc`.

The whole-driver audit remains **not_equivalent**. Modern UAPI/Mesa integration,
timestamp publication/units, remaining stage backing/event destruction,
manager/UAT replacement, safe firmware teardown, reservation fences, timelines,
remaining wire/default coverage, topology and power/reset behavior remain open.

Evidence: `/Users/alex/.local/state/vinix/omarchy-m1-completion-order-20261116/`.
Baseline is `71e7dc12d2b399f56a9c4d08e1b9b6f5b4df3cd3` plus thirteen retained
source paths, including one native overlay. Ten independent unchanged runner
binaries and three event/counterexample runners are reused after source/binary
checksum checks; dependent fixtures and kernels are fresh. The unchanged
historical inventory checker verifies the preceding complete bundle, the new
complete bundle and its full archive restoration. `completion.txt` binds sources
and reports to the commit. Generated evidence stays outside Git. Disk-space
reclamation removed only clean disposable upstream clones from eight completed
tasks after checking their original bundles and archive checksums; canonical
bundles and archives remain intact.

| Artifact | SHA-256 |
| --- | --- |
| `inventory.json` | `074b0ac25fabc794dfb55f01e801be3293942433b3cd085b555274bbb80635c3` |
| `bundle.tar.gz` | `30e5a85af9a5b3860e3c0f270b1a90ccda05573c89cf28b5cfbf9f53a86c79f7` |
| `bundle/vinix-aarch64` | `7f78a7a770551d5a146074e70849551aca3a2ef95bf423b2ffba2bb02794b78b` |
| `bundle/vinix-x86_64` | `574add5b5c23fd0200245ba0c7934c5133c92c50f86875b0b9a09af0c7271a71` |
| `bundle/blob-aarch64.c` | `93b34f4e9437b517f48481f6dd14ba9bf7159897f071ee10008c6e460178fef6` |

No GPU workload, firmware interaction, Vinix/QEMU boot, reboot, SSH or deployment occurred.
