# G13 microsequence writes without heap copies

The kernel is built with `-gc none`, so a local that V moves to the heap is
never freed. Commit `2f2f7efe2` removed two such copies from the vertex start.
The rest of the per-job microsequence path still leaked on the 13.5 firmware
ABI that base M1 uses: every render job lost five or more small heap blocks
and every compute job three or more.

V moves a local to the heap when it holds a fixed array and its address is
passed where V cannot prove it is only borrowed. `C.memcpy` and `&x` inside an
`unsafe { }` block both count. An `unsafe { &x }` argument does not.

- The six versioned writers (`write_g13_timestamp`, the vertex, fragment and
  compute finalizers, and the fragment and compute starts) built their 13.5
  value and copied `&value` inside an `unsafe` block. They now take the address
  in a separate `unsafe { voidptr(&value) }` statement, as the vertex start
  writer already did.
- `prepare_g13_render_job_with_timestamps` and
  `prepare_g13_compute_job_with_timestamps` built the fragment and compute
  start records inside a large `unsafe` block. Those records and their writer
  calls now sit between two `unsafe` blocks and pass `unsafe { &start }`, like
  the vertex start. The retire-stamp record moved ahead of the vertex block so
  both halves can use it. Values and write order are unchanged.

## Validation

The aarch64 allocation scan drops from 427 to 419 findings: the eight
`g13.v` "fixed array storage may escape" sites, and nothing else changes.
In the generated C, none of the seven writers nor the two preparation
functions calls `memdup` for a microsequence record.

`tests/agx-g13-failure/check-prefix-storage.v` now covers the six writers and
the two real preparation bodies (the `prepare_g13_*_job` entries it already
had are three-line wrappers). Each preparation body may hold exactly one
allocation, its job record; the selftest rejects a missing or extra one. On the
base blob the checker fails at the render preparation's temporary `memdup`, and
without the preparation entries at `write_g13_timestamp`. On the fixed blob
every AGX helper passes. Four entries named functions that no
longer exist and were updated (three removed, one renamed to the free function
`initialize_g13_barriers_locked`). The checker still stops later, at older
sync-file and syncobj expectations that predate this change; those are not
fixed here.

The render-wire, TVB-growth, timestamp-wire and timestamp-input suites pass,
as do 79 G13 contract test files and 122 pinned reference checks. One counter
contract now quotes the `unsafe { &fragment_start }` and `unsafe { &start }`
calls. `tests/agx-command-counter` already failed to compile on the base
revision. Both `PROD` kernels build and the AArch64 kernel boots in QEMU and
passes the mount-lifecycle `descflags` case. No M1 hardware test occurred.

Evidence is under
`/Users/alex/.local/state/vinix/omarchy-m1-microseq-heap-20261119/`.

| Artifact | SHA-256 |
| --- | --- |
| `bundle.tar.gz` | `cb86a341e47478902121e6d0e343024b49688c0e93b3ddfda97ec4468b887025` |
| `bundle.tar.gz` inventory | `9f98a88d99b56f4dc990fc6bf64a88d255c8760827b8cede947f093b3f1f4060` |
