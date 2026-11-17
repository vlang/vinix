# GEM private-buffer advice

The modern native ABI registers `GEM_MADVISE` (command `0x4b`, 16-byte read/write
record). Invalid pad/advice precedes file-local handle lookup. Only private,
nonexternal objects accept advice. An owned GEM reference survives file unlock,
handle removal and the object-locked update; every exit drops it. Advice records
WILLNEED/DONTNEED and reports `retained=1`. Contiguous backing remains resident;
purging/repopulation and interruptible reservation locks remain separate work.

```sh
v run tests/agx-gem-advice/run.v host /external/fresh-host
v run tests/agx-gem-advice/run.v negative /external/fresh-negatives
v run tests/agx-gem-advice/run.v measure /external/fresh-measure
v run tests/agx-gem-advice/run.v trace /external/fresh-trace
v run tests/agx-gem-advice/reference.v /reference/linux /external/fresh-trace/host /external/fresh-reference
```

The sanitized production-method fixture tests 96 header/ownership/state cases,
handle removal during object-lock acquisition, resident contents, ABI isolation,
copyin refusal and copyout failure after state commit. The file/VM/queue/PRIME
and modern-transport regressions run too. Four compiled mutants must fail the
designated validation, private-eligibility, reference and state assertions.
The ordinary malloc probe measures three warmed batches of 10,000 advice calls.
These are endpoint measurements, not native slab or whole-kernel leak results.

The V reference runner extracts the unchanged pinned Linux shmem advice body and
UAPI record, compiles them with ASan/UBSan, and compares 2,048 ten-operation
resident sequences (20,480 transitions) plus every record offset. Reservation
locking is stubbed and purged state is excluded. Rust ioctl/private-eligibility
bodies are retained for source comparison, not compiled.

Native preparation pins `5648deb6a83989698af3f42f659511727004a812` plus four owned
kernel overlays. Create `/external/state`, then use V to run
`native.v prepare|aarch64|x86_64|contracts|allocations /external/state`; build
architectures sequentially. Existing allocation-allowance failures are expected,
and evidence validation requires unchanged file/kind counts.
`check.v PRIOR_COMPLETE_BUNDLE STATE` verifies C ownership/order, absence of
hidden advice allocations, matching helper/caller bodies across relevant host
builds, and unchanged backing/lifetime/submission paths. The x86 backend is pruned.

`evidence.v validate|seal|bind|cleanup STATE [COMMIT]` preserves selected complete
evidence outside Git, checks the preceding full bundle, restores the archive and
checks both named roots. Bind verifies committed feature bytes; cleanup removes
only this task's pinned build worktree. Full parity remains incomplete. These
commands never boot a guest or access hardware.
