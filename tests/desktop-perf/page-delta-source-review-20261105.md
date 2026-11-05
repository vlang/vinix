# Baseline backing-page delta source review — 2026-11-05

Source review does not resolve the baseline's strict flatness failure. The
unchanged complete checker returned status 1 (`nonzero exact class object or
backing-page delta`). The legacy checker returned 0 for its narrower emitted-row
contract; that result does not override the complete check. No checker, kernel,
probe or retained evidence was changed for this review, and no new workload was
started.

The retained run root is
`/Users/alex/Library/Caches/vinix-codex/section14/perf-six-x86-20261105-01` (`R`).
`R/prepared-frame-01/results/serial.log` has SHA-256
`df7faf539b3b0e256fb810b48d2ca0a9480d35594d88c7d76eb6613c0e28a4c8`.
`R/frame-gates-01/status.json` has SHA-256
`a04c258a808de7468109d737b16e523257b562fb705b88573d4914e92a11e035`;
the separate `nonzero-deltas.txt` has SHA-256
`cfa43ba30488a9d91e73946da1d63eb13f24af810130f91f14ab71c8d44ec9bb`.
These receipts retain nine size-256 backing-page changes of +1 or -1, each with
zero object delta. For example, serial lines 493–538 record `proc_read /tmp`
changing from 4,555 objects/305 pages to 4,555 objects/306 pages. The four churn
rows retain zero physical bytes and zero complete slab deltas. Neither those
observations nor a net page delta establishes flatness of every measured pair.

## Frozen source bindings

The kernel build root is
`/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026/build-01`
(`K`). Its recorded kernel source revision is
`9acefa77bee69247c837e97987a2377536aa41cc`, with frame patch SHA-256
`bbf47e280990b368fdd38a8917770de3024df078254a13aa116372e421fd7e25`.
The complete original `K/inputs-before.json` has SHA-256
`67af25011f2f0ab9853add9b4c296396ba0115009382a661f9ea698e482b3738`.

| Reviewed input | SHA-256 |
| --- | --- |
| `K/x86_64/obj/blob.c` | `1c7dc1b491c9e8f7debcb8bf68978614d5ca54f923c0c77ca19788fc556c920e` |
| `K/source/kernel/memory/slab.v` | `5c476a01dab2e01d8b13bcddce5be7fa6505f4e98f51875219bb360ce35a1aa4` |
| Original `kernel/memory/slab_shards.v` input | `ba0a5e867dc18aac1417bed44767130513bc858d0d9c3d5b6b5a028790f2b6a6` |
| Original `kernel/fs/procfs.v` input | `d6c9bddf457cc46c9b588749768e9e4bdce43a51ac540d52b696a6447298d1b1` |
| `R/prepared-frame-01/guest/measure-v.c` | `3fc651696919d5ba483e6ebeeb0328928b8870b7bc1a95f150a970294fec6226` |
| Captured `tests/desktop-perf/measure-v/main.v` | `5eb6c82ab849050c94e21e3e2956cbc5003e40bd229b2f9135336678aa6a8acb` |
| Captured `tests/desktop-perf/perfheap/core.v` | `7279728b67114929706a0a7deeb6842a35aa387a121e0139def583db0896758a` |

The last two sources are under `R/prepared-frame-01/source/`. The original
slab-shards and procfs inputs remain in
`/Users/alex/code/vinix/build/package-peer-login-frame-fresh-worktree/kernel/`;
their reviewed hashes match the original input map. The slab copy and that
worktree's slab source also match. Conclusions below use these bound bytes and
the retained generated C, not current-main similarity. This review did not repeat
the complete original bundle audit.

## What the source establishes

- `memory/slab.v:136` (`grow`) increments `pages`. `sfree`, starting at line
  308, retains the first empty page as `spare` without decrementing `pages`;
  another empty page is detached and decrements the counter. `take`, starting
  at line 172, prefers partial pages and consumes the spare only when no partial
  page exists. This allocator does not compact occupied pages. Consequently,
  live-object totals alone do not determine backing-page or spare state.
  `K/x86_64/obj/blob.c:116327`, `116384` and `116455` confirm these paths.
- `memory/slab_shards.v:34` captures each slab's `live/pages` tuple under that
  slab's lock; generated C at line 116807 preserves the lock and value copy.
  `memory/slab.v:397` and generated C at line 117151 sum the original slab and
  CPU shards after separately releasing their locks. With multiple active
  shards, the aggregate has no common sampling instant. This is a possible
  observation limitation, not evidence that it caused these nine changes.
  The configured two QEMU CPUs and `LIMINE_MP=0` build argument do not by
  themselves establish the online shard count.
- `fs/procfs.v:915` regenerates slabinfo for each read; slabinfo is absent from
  the per-open `snapshot_read` selection. Its formatter starts at line 1239,
  corresponding to generated C at line 88451. Here every admitted raw body is
  346–349 bytes and fits in the reader's first 4,096-byte read. The subsequent
  EOF probe alone does not splice those recorded rows. The measurement's
  captured source at line 162 and generated C at line 5917 take both measured
  snapshots before printing either proof body. This does not establish that
  opening or reading procfs has no allocator effects.
- The frozen procfs allocation-site dump passes `min_count=50` at source line
  670 and generated C line 72381. Recorded `PERF-SITE live 9–15` totals therefore
  provide no call sites identifying a page transition. Absence of printed sites
  is not proof of absence of allocation or fragmentation.

These paths explain how equal live counts can accompany unequal page counts.
They do not identify the actual transition, responsible allocation, page
occupancy or concurrent activity in this run. No cache cause, leak absence or
snapshot-incoherence diagnosis is established.

## Minimal follow-up

Keep the failed strict result and existing checkers. In a separate admitted
diagnostic, first retain repeated full snapshots with no operation cohort, then
repeat the selected `proc_read` cohort with the same warmup and grace. Capture
the samples before printing them; do not replace per-pair checks with net deltas.
If movement repeats, a separate diagnostic kernel can record per-shard live,
pages, spare/occupied-page state and grow/release counters under the slab locks
into fixed storage before formatting. Record online shards and bracket the
capture to distinguish allocator transitions from cross-shard sampling. That
measurement, its build, and any proposed fix remain pending.
