# Failed G13 queue-constructor metadata

`v run tests/agx-queue-unwind/run.v` extracts the production constructor and
queue-ID allocator and checks 3,640 cases with ASan/UBSan, `-gc none -manualfree`.
Use `ASAN_OPTIONS=detect_stack_use_after_return=1`. All seven channel masks and
four priorities cover allocation, context/notifier initialization, subqueue,
render-buffer and publication failures, successful return and cleanup refusal.
Freed-address poisoning distinguishes safely cleaned unreturned records from
live returned/quarantined records. Backing cleanup and external firmware/VM
services are instrumented; the host queue type is reduced to constructor fields.

`MallocNanoZone=0 v run tests/agx-queue-unwind/run.v --measure` measures retained
malloc blocks/bytes across three 10,000-failure batches. Warmup excludes setup
and stdio costs. The same setting is used for baseline and fixed measurements.
`measure-control.v` directly allocates/frees 144-byte host records. On the tested
macOS nano allocator its statistics show a 102-block / 16,320-byte step even
though every pointer is explicitly freed. With `MallocNanoZone=0`, both the
control and fixed constructor remain flat; the baseline still leaks one block
per failed construction. Preserve both diagnostics and controlled measurements.
These host bytes do not measure native kernel object sizes or slab rates.

`--source G13` selects alternative constructor input. `AGX_UNWIND_C` and
`AGX_UNWIND_BINARY` retain artifacts externally. Temporary fixtures are removed
before exit. `counterexamples.v RUNNER BASELINE_G13 FRESH_OUTPUT` requires five
compiled baseline/mutated cases to reach designated missing-free, retained-owner,
returned-owner or double-free failures; compile failures do not qualify.

`check.v --native CURRENT_ARM_C BASELINE_ARM_C` removes exactly the twelve
lowered cleanup-success free arms and requires the remaining constructor to
match baseline. Thirty-five heap, backing, context, quarantine and ownership
bodies and three owning layouts must remain unchanged. String IDs resolve by
value and numbered temporaries are renamed consistently. `--selftest` rejects
six free, completion, quarantine, publication and lock mutations. Original
x86 whole-C, allocation-allowance and historical evidence checks are unchanged.

`qualify.v STATE` prepares the isolated baseline worktree and one `g13.v` overlay,
with dependency links and a verified native-runner source. `evidence.v --seal
STATE` preserves complete sources/results, checks the preceding full bundle,
records the typed inventory and checks full archive restoration. After commit,
`--bind STATE COMMIT` verifies exact paths/bytes; `--cleanup STATE` removes only
the private build worktree and verified restore. See [the report](../../docs/m1-agx-queue-unwind.md).
