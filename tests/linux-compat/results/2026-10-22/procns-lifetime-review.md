# Independent procfs lifetime review

Reviewer: Codex subagent `/root/lifetime_review`, read-only; no implementation edits.
Checked commit: `cf6426cf16657a6db8d5be8062ef82f170c6b48b`.
Reviewed on 2026-10-22, before running the new qualification guests.

Result: no blocker found in the procfs reclamation change.

Reviewed the procfs resource constructor, unref, refresh guards and recursive pruning; namespace-link construction; VFS open/readlink/listing paths; the complete removed-node reaper; resource retain dispatch; Handle.unref; cwd/root ownership scans and release timestamps. Generated C from the previous exact-change tracking build (`procns-20261016/after-arm-track/blob.c`) was also inspected for implicit resource boxing and refcount dispatch.

The constructor creates one backend and one shared resource interface box. Retain dispatch increments the backend refcount. The last resource release separately defers backend and interface-box freeing. Per-handle snapshots and resource text are freed under the existing resource synchronization. Recursive retirement removes non-dot children before their parents; each orphan holds its parent until it is reaped. Remaining dot-entry maps are released when the directory node is finally freed. Namespace resources remain owned by the node until that point.

Persistent references are covered by node handles, parent_refs, cwd/root owner scans and release timestamps, executable/overlay references, and existing mount pins. Opening establishes the node handle before retaining the resource; closing releases the resource before dropping the node handle. Refresh guards prevent detached process directories from being lazily populated again. Readlink uses the disappearance-aware procfs error helper: a vanished process returns ENOENT and a live inaccessible process returns EACCES.

Limits: this is a source/generated-C lifetime review, not a formal concurrency proof. Transient lockless borrowers inherit the existing five-second timed grace rather than a quiescence-based RCU guarantee. Mount pins intentionally retain their existing permanent lifetime. The prior generated C was checked; the new build is independently pinned by the qualification evidence. Guest test outcomes belong in their separate logs and do not change the scope of this review.

## Current generated-C supplement

Independently checked the new exact-change ARM and x86 tracking generated C on 2026-10-22. The constructor, unref, recursive prune, removed guards, orphan/parent hold, node free and reaper operations preserve the reviewed lifetimes. Both generated unref definitions decrement the backend refcount and defer the shared box and backend separately; constructor interface `_object` points to the single backend. Child arrays and maps are explicitly freed. The reaper checks mount pins, handles, parent_refs, cwd/root usage and directory-release grace before node free. Handle release orders resource unref before node handle release. No additional blocker found.

Exact input SHA-256 values:

```text
f11fea4af9a9d01cd7fd7d652524f2109b60cc84beb205b9191785db026d4930  /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/arm-track/blob.c
97d4b64ae123d6b3f8c762847c61847b8e7b8f962c238be5de354c0a7d35e532  /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/x86-track/blob.c
5515b47a413f57ee7e69b943f153def6359b68378dd3a8b8b8d404685cecbb90  /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/arm-track/kernel/bin/vinix
5f191bb7355f00bc99e1cd04d1d3b6de570815c8517a9077469d35844f7e6b13  /Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/x86-track/kernel/bin/vinix
```

Thirteen function bodies from each architecture are retained in generated-review-{arm,x86}-excerpts.c; generated-review-comparison.log records comparisons after normalizing generated string IDs. Architecture-specific interface dispatch lists differ; the relevant procfs backend and lifetime branches were inspected explicitly. The earlier timed-grace and source-review limits still apply.
