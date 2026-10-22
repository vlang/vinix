# Deferred-reclaimer queue drain review

Reviewer: `/root/lifetime_review`, 2026-10-22. Source base: `cf6426cf16657a6db8d5be8062ef82f170c6b48b`. Candidate is the isolated `source-x86.diff` / identical `source-arm.diff`; no shared checkout or original cf642 artifacts were changed.

The original queue has `.noslices` growth, which frees old buffers, but its generated `array__delete_many` takes the unsliced fast path: it shifts and zeroes removed elements and decreases `len` while retaining `cap` and `data`. Thus an empty queue retains its historical largest buffer. The frozen x86 C layout of `RetiredItem` is 200 bytes (Charge32, four pointers32, string24, two Array48, bool/padding8, timestamp8). Growth from capacity1024 to2048 changes50 payload pages to100; the one metadata page is unchanged. That arithmetic matches a50-page difference but is not attribution without measuring the actual queue capacity/data and allocation metadata.

No source-level lifetime blocker was found in the proposed whole-array drain transfer:

- Searches find queue access only in `retire` and `reap_removed`, both under `removed_lock`. The initial due scan stores no element pointer beyond the scan.
- A full drain transfers the complete array header to the local `items`; resetting the global must only replace its header. It must not free or clone the old data. Existing item ownership, including strings and nested array headers, stays in that local batch.
- The global reset occurs before unlocking, so concurrent retire calls and callbacks that requeue nodes append to a separate new queue. Each `retire` sets `.noslices` before appending.
- Processing and final `items.free()` remain outside `removed_lock`. Only the backing buffer is freed at the existing final free; each owned resource/string/nested array follows its existing callback path. No additional grace period is required for a queue buffer that has no lockless borrowers.
- The partial-drain path preserves the original shallow memcpy and `delete_many`, so still-pending entries retain their original times and ownership. Zero-due returns before either branch.
- The empty-array initializer is allocation-free in the pinned compiler's generated runtime wrapper. Generated candidate C must independently confirm shallow header assignment, global reset without free, no clone, and the final single buffer free after callbacks.

Allocation tradeoff: a drained queue regrows for a later burst instead of caching the largest previous buffer. Full drains avoid the former due-sized scratch allocation and copy, while callbacks may temporarily grow a new queue before the old batch buffer is freed. Persistent backlog or persistent requeued references still legitimately retain queue storage; this patch does not change their grace or ownership rules. It does not prove the observed x86 growth came from this queue.

Guest validation, allocation attribution, and independent parent review remain required before committing or claiming retention fixed.

## Confirmed attribution and final annotation revision

Update 2026-10-22: live QMP inspection measured the original queue growing from capacity1024 to2048 and remaining empty at capacity2048 after the strict native measurement. The managed allocation metadata reports409631 requested bytes,101 payload pages and one metadata page; the former capacity1024 buffer takes52 total pages. This accounts for the exact50-page persistent increase with all14 slab classes flat. The original diagnostic and initial failed qualification remain preserved.

The runtime change was committed in the isolated source as `ec5631d664a8148c063b1ef9ac3f9657a3a0386a`. Its first allocation inventory exposed a missing `@[freed]` annotation on the relocated partial-drain assignment. Final commit `bd9aa1bc1d04eac1ce31e02ce8914969294566ff` adds only that assignment annotation. Both private trees are clean at this final revision; the aggregate diff from `cf6426cf16657a6db8d5be8062ef82f170c6b48b` changes only `kernel/fs/removed.v`. All first-revision profile artifacts, build logs, source records and the initial allocation failure are frozen under `q1-ec5631d664a8`, with an archive digest manifest.

The final complete allocation scans report713 ARM source files/384 sites and712 x86 source files/276 sites on both base and candidate, compiler exit0. Both allowance checks still exit1 for identical pre-existing excesses; the independent comparison exits0 with no new allocation group. The annotation does not change the ownership transfer.

Reviewer `/root/lifetime_review` also implemented the isolated queue patch, so this document is the implementer's lifetime analysis. Parent `/root` independently reviewed the full-drain source and x86 generated-C transfer/reset/final-free sequence before Q1 was committed, and reviewed the annotation-only Q2 difference before integration. Final build/profile checks and guest qualifications are reported separately; they must be consulted for observed results.

Parent `/root` subsequently independently reviewed the exact Q2 ARM tracking generated C and approved both final tracking ownership paths: shallow header transfer and empty reset under the lock, unchanged partial memcpy/delete_many, unlock before callbacks/requeues, and batch/nodes/running frees after traversal. The reviewer found no new lifetime blocker. All four final profile builds and generated-C checks exited0; native retention and performance outcomes remain separate evidence.
