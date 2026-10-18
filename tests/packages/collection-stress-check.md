# Full native collection repetition

The earlier [collection ownership qualification](collection-request-check.md)
measured 64 calls per case on the host, but bounded native repetition to eight
after file creation and directory enumeration returned `ENOMEM`. The native
stress runner now measures **64 calls in all 48 cases: 3,072 requests per target**.
It also runs every existing retirement test, including the 128-generation batch,
64-level tree, 1,024 long-name files, changed root/parent/lease inventories and
128 successful/128 refused removal-helper allocation probes.

The failure was a creator reservation limit. A reproducer's
`/proc/kernel-resources` reported an owner limit of 59,759,616 bytes, a denied
100,608-byte file reservation and 59,725,956 bytes already reserved for that
owner. File reservations accounted for 51,480,252 bytes, while `/proc/meminfo`
still reported more than 800 MiB free. Reservations include conservative object
and capacity estimates, so they are different from slab RSS and free RAM.

Repeating the failure with quiescence showed file reservations falling to
921,390 bytes after six seconds and 884,448 after twelve. The filesystem retains
removed names and their charges across its five-second grace period, protecting
concurrent readers. The original fixture constructed and removed thousands of
files during its 64-call warm pass before measuring another 64 calls. The full
retirement suite likewise accumulated several large fixtures in one creator
process. Their retained reservations reached the admission limit before reaping.

The new `collection_request_stress` fixture mode uses eight warm calls before
**64 measured calls**. JSON metadata and success/refusal paths initialize in
that warm pass. Each native case has a separate creator process. After each
child exits, the parent observes the kernel file reservation counter until it
falls below one fixed baseline plus 128 KiB. It polls once per second and refuses
after 30 seconds; the allowance does not accumulate between cases. Observation
and settling happen outside the measured request scopes. Every retirement test
also runs in a separate child, followed by the same reservation check.

This qualifies consecutive 64-call batches with explicit quiescence between
independent filesystem fixtures. It does not establish unrestricted creation
throughput. The existing eight-call native mode and normal host warm-up remain
available. Section 14 production/catalog migration, complete graphical sessions,
foreign-runtime acceptance and other service ownership boundaries remain open.

The [counter reader](collectionstress/budget.v) rejects missing/duplicate records,
signed/coerced numbers and unsigned overflow, and bounds the fixed ceiling.
Its [host checks](collectionstress/budget_test.v) include full-width values and
malformed records, so invalid observations cannot become a false zero.

Run the [host driver](collection-stress-check.v) in a new workspace:

```sh
v -nocache -o /tmp/collection-stress tests/packages/collection-stress-check.v
V=/path/to/reviewed/v /tmp/collection-stress /build/new-collection-stress
```

All 14 compilations/runs are fresh. They cover normal and ASan/UBSan request
fixtures with the original and shorter warm-up, compilation without tracking,
and normal/sanitized counter checks. Each of the four tracked request runs
measures 3,072 calls with zero retained tracked V bytes. ASan uses
`detect_leaks=0`; claims concern those explicit scopes, not whole-process storage.
The previous full host retirement/CLI checks remain separate regression evidence.

The [native controller](collection-stress-runtime-check.v) builds nine fresh
programs and init for each architecture. It requires all 48 zero-retention
request scopes, all six retirement controls, 128-generation collection under
`RLIMIT_NOFILE=32`, signed service maintenance and all 56 settling observations.
Prebuilt kernels are pinned inputs; the TCG deadline is 900 seconds. The
[retention helper](collection-stress-retain.v) records commands, timings and
source/compiler/kernel/binary/report hashes; `--verify` checks the saved ledger.

Recorded on 2026-10-18 with frozen V 0.5.2 `826e96f` (compiler SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`):

| Check | Result | Elapsed |
| --- | --- | --- |
| Host compilation, request scopes and counter checks, including ASan/UBSan | All 14 checks passed | 180.517 s total |
| AArch64 native collection stress and retirement controls | Passed | 488.2 s |
| x86_64 native collection stress and retirement controls | Passed | 418.0 s |

Both native runs measured 3,072 calls with zero retained tracked bytes. Each
completed all 56 reservation checks against the fixed 133,120-byte ceiling;
the longest waits were six polls on AArch64 and nine on x86_64. The largest
observed initial file reservation total was 50,336,618 bytes. No wait occurs
inside a measured request or between its 64 calls.

The [host summary](results/2026-10-18/collection-stress-host.txt) and
[receipt](results/2026-10-18/collection-stress-host.json) preserve all host
commands and timings. Native [AArch64](results/2026-10-18/collection-stress-aarch64.txt)
and [x86_64](results/2026-10-18/collection-stress-x86_64.txt) summaries have their
raw [AArch64 serial](results/2026-10-18/collection-stress-aarch64.serial.txt) and
[x86_64 serial](results/2026-10-18/collection-stress-x86_64.serial.txt) logs and
QEMU command logs alongside them. The expected failing
[reservation-limit reproducer](results/2026-10-18/collection-stress-budget-denial.serial.txt)
and [drain observation](results/2026-10-18/collection-stress-budget-drain.serial.txt)
are retained separately from passing results. Their remaining named files
account for the residual file reservations after the failed fixture.
The [ledger](results/2026-10-18/collection-stress-ledger.json) pins the evidence
and the deployed binaries/generated C, including the diagnostic snapshots and
the V-only native media adapter.
