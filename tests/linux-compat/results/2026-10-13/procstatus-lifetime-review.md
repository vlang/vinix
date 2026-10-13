Independent task-status identity lifetime review: PASS

Read-only review by `/root/procself_lifetime_review`, as required by AGENTS.md.
The selected process and task stay under the existing process-table lock through
identity reads and text construction. New `tid_in` and `target.ns_tid` reads
introduce no escaping pointer or allocation. Generated C evaluates `ns_tid`
only for a validated nonzero selected TID. Text ownership and freeing do not
change. A misplaced draft declaration was corrected before candidate builds.

The namespace helper's NamespaceWorker stays on the stack and is joined before
its result is read or its inner directory is closed. A failed join calls
`_exit(1)` before unwinding. Inherited descriptions remain live through both
forks; process exit releases copied descriptors. All post-open status failures
close their description. Actual fixture C matches both previews, with no hidden
allocation or promoted state and only the original three bounded alloca objects.

Both final captures pass leader/worker IDs in root and own PID views. Live
slabs and large pages stay exact after 200 cycles: 63/63 ARM and 160/160 x86 in
both credential groups. This does not qualify repeated namespace creation,
overmount/unmount or concurrent task teardown.

| Final artifact | SHA256 |
| --- | --- |
| kernel/proc/proc.v | a08e3f91dbe769e4448edf17cd5fd6dce60bdd37a708b496e3124a3bd76a1223 |
| tests/linux-compat/procselffixture/core.v | f1f5f2cc3f00447700a39b9037cb6fb72d711b909c3ac054d7d1b888d4d8faa5 |
| preview-arm.c | 080825dab16139a287a37131bc0d657e10c6b6670e2fedb9cadcf833c42204c4 |
| preview-x86.c | 080825dab16139a287a37131bc0d657e10c6b6670e2fedb9cadcf833c42204c4 |
| kernel-arm/kernel/obj/blob.c | 17ea1f7b7f6e0e4b82727e8542234eefbf09081fbaccae189c9facf245af0a24 |
| kernel-x86/kernel/obj/blob.c | 6508b94131929455c749aad33d709851482e330c6436d7ed046f9a147c2750f6 |
| after-arm/procself/serial.log | 7962161fa9dfae857d4167ef72a8f41a84bf2aad683732c711d9e1e5e5410cb5 |
| after-x86/procself/serial.log | b6e8eb671f0ca9717a55d5d157ea5d24af4aa17b60f11c0430e62349664d76ab |

Both actual after-guest fixture C hashes equal their preview above.
