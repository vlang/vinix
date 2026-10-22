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
