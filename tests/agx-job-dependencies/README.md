# Captured scheduler dependencies

G13 copies input records once, then keeps the greatest unsigned sequence for
each ordered 64-bit fence context. Independent G13 fences reduce only when
the exact same fence appears again. Nil records disappear, and equal-sequence
ties keep their first record. Both ABIs use the reduced private copy. The scan
costs O(records × distinct dependency groups), like Linux's xarray scan.
The [native fence regression](../../docs/m1-agx-independent-fences.md) covers
reverse retirement through both ABIs.

```sh
v run tests/agx-job-dependencies/run.v host /external/fresh-host
v run tests/agx-job-dependencies/run.v negative /external/fresh-negatives
v run tests/agx-job-dependencies/run.v measure /external/fresh-measure
v run tests/agx-job-dependencies/run.v trace /external/fresh-trace
v run tests/agx-job-dependencies/reference.v /reference/linux /external/fresh-trace/host /external/fresh-reference
```

ASan/UBSan exercises 4,096 selections, private-source preservation, dynamic lists
through 1,025 records, OOM, nil-only dynamic results and 32 legacy/modern pending
lifecycle cases. It checks latest/tied/context ordering, captured snapshots,
foreign waits, independent storage and cleanup. Full existing async, modern,
timeline and queue regressions run too. Four compiled mutants must fail designated
integration, latest/tie selection and copy-ownership assertions.

The ordinary malloc probe measures nine warmed 1,000-operation batches across
4/65/1,025 input records. The initial address-based implementation leaked a V
header box; direct field writes remove it. Final generated C must reject hidden
allocations. This qualifies copy/release retention, not published metadata or
whole-kernel/native slab rates.

The reference runner compiles unchanged pinned scheduler dependency insertion,
generic dependency-callback readiness and comparator bodies. Xarray/refcount/
callback plumbing is modeled; the comparator's 64-bit branch is selected. Its
4,096 outputs must match exactly. Asahi exports scheduler finished fences with
init32 sequences; Vinix currently uses 64-bit timestamp sequences. Wraparound
equivalence and complete scheduler behavior remain unqualified.

The historical native and evidence runners below use the
`f183daa00` checkout. Native preparation pins
`4755d6b55c6459658fe48fc25b7fbcc0ebf71abb` plus two owned
kernel overlays. Create `/external/state`, then run V's
`native.v prepare|aarch64|x86_64|contracts|allocations /external/state`, building
architectures sequentially. Existing allowance failures are expected; every
file/kind count must still match the preceding complete bundle.
`check.v PRIOR_COMPLETE_BUNDLE STATE` verifies stack storage, no new allocation,
matching host/measurement/trace C, the single caller change and unchanged owners.

`evidence.v validate|seal|bind|cleanup STATE [COMMIT]` retains selected complete
evidence outside Git, checks the preceding full bundle, verifies archive
restoration and both named roots, then binds committed feature bytes. Cleanup
removes only this task's pinned build worktree. Earlier failing evidence stays
outside Git. No command here boots a guest or accesses GPU hardware.
