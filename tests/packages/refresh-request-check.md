# Owned complete catalog refresh requests

`Service.refresh()` and explicit `refresh(config, directory)` return catalogs
whose publisher identities and complete nested manifests belong to the reply.
Call `Catalog.close()` when finished; repeated close of the same value is
harmless. Explicit refresh borrows its configuration and directory. Service
refresh retires its freshly loaded configuration and state-directory path after
the reply becomes independent. The CLI `update` command closes its catalog.
Low-level `load_catalog()`/`snapshots_catalog()` and caller-built catalogs keep
their borrowed publisher identities and must not use this close method.

Refresh retires URLs, paths, progress text, fetched metadata, decoded indexes,
history and unsuccessful catalog construction. File-URL slicing and wrapped
copy-source diagnostics also release their intermediate storage. Successful
catalogs transfer already-owned manifests and clone only publisher identities;
there is no extra manifest decode or change to catalog JSON, signatures, replay
checks or publication order. History still publishes before the cached catalog.

Temporary workspace retirement uses the existing captured-directory inventory
and bounded descriptor walk. Only `ENOENT` permits an absent workspace. Aliases,
shared writable roots and filesystem crossings refuse before cleanup; nested
abandoned work retires without traversing foreign files. Cleanup after a request
is best-effort, as before, but uses the workspace identity captured at creation
and retires its errors. It cannot delete a later replacement through that name.

The [fixture](../../tools/packages/pkgcore/refresh_request_test.v) measures 64
complete calls after eight warmups in each of 72 service/explicit cases across
both architecture declarations: **4,608 measured requests**. Tracking starts
after fixture preparation and ends after reply/error retirement. Cases cover
fresh/repeated refresh, legacy history migration, revoked/empty configuration,
malformed cache/history, signature/syntax/schema/expiry/floor/equivocation
and ambiguous-publisher refusal, missing index/signature, offline HTTPS refusal,
writer contention before configuration reads, bad configuration and invalid
roots. Refusals preserve cached catalog and history bytes. Unicode, long
descriptions, dependency ranges, arguments, protocols and 4-GiB payload counters
remain intact in independently retired replies.

Separate probes retire configuration and one reply before reading another;
recover nested abandoned work; and refuse aliased/shared writable workspaces
without changing foreign files or signed metadata. Two 64-call publication
failure scopes each require zero retained tracked bytes after decoded catalog
construction, refusing history and cache replacement independently. These
additional scopes preserve the other persistent document's exact bytes.

The pre-change fixture measures two calls in the same 72 cases, retiring decoded
manifests according to the old borrowed-identity contract. Two fresh service
calls retained 13,784 bytes for the AArch64 declaration and 13,782 for x86_64;
explicit calls retained 5,878 bytes on either declaration. Empty service refresh
retained 10,182/10,180 bytes, and writer contention or malformed configuration
retained 122 bytes. Those are scoped fixture totals, not whole-process rates.
Captured original sources, the baseline executable and its raw output are pinned.

The [host driver](refresh-request-check.v) performs 35 fresh compile/run checks:
request ownership with/without tracking and ASan/UBSan; signed service,
administration, snapshot schemas, copy-output protection, retirement and borrowed
catalog controls normally and under sanitizers; and both real CLI lifecycle
runs. Sanitizer leak detection is disabled; scoped tracked V allocations supply
the retention claim. No whole-process or live HTTPS transport memory claim is
made. Activation/rollback ownership and broader section 14 release/catalog,
graphical-session and foreign-runtime acceptance remain open.

```sh
v -nocache -o /tmp/refresh-request tests/packages/refresh-request-check.v
V=/path/to/reviewed/v /tmp/refresh-request /build/new-refresh-request
```

The [native controller](refresh-request-runtime-check.v) builds request,
independent-lifetime, workspace/publication, service and copy-output programs for
both targets. Each request case runs in its own creator process. The parent
observes file reservation retirement between cases using the existing
[strict counter reader](collectionstress/budget.v): one fixed initial baseline
plus 128 KiB, at most 30 one-second waits after each child, all outside measured
requests. All 76 settling observations and every request/control marker are
required by the [retention helper](refresh-request-retain.v). Kernels are pinned
prebuilt inputs, and the QEMU TCG deadline is 1,200 seconds per target.

Recorded on 2026-10-18 with frozen V 0.5.2 `826e96f`, compiler SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`:

| Check | Result | Elapsed |
| --- | --- | --- |
| Host compilation, normal/sanitized fixtures and CLI lifecycles | All 35 checks passed | 607.745 s total |
| AArch64 native requests, lifetime/publication and service/copy controls | Passed | 985.7 s |
| x86_64 native requests, lifetime/publication and service/copy controls | Passed | 1,026.1 s |

Each tracked host and native request run measured 4,608 complete requests with
zero retained tracked bytes. Both 64-call publication-failure scopes also
retained zero tracked bytes. Both native runs completed all 76 reservation
checks against their fixed 133,120-byte ceiling. The maximum wait was six
polls on each target. Observation and waiting occur outside measured calls.

The [host summary](results/2026-10-18/refresh-request-host.txt) and
[receipt](results/2026-10-18/refresh-request-host.json) retain commands, timings
and compiler/source/artifact hashes. The
[normal request log](results/2026-10-18/refresh-request-request-run.txt) and
[sanitizer log](results/2026-10-18/refresh-request-request-sanitize-run.txt)
record every request and control scope. The
[paired baseline](results/2026-10-18/refresh-request-baseline.txt) preserves
the original two-call measurements.

Native [AArch64](results/2026-10-18/refresh-request-aarch64.txt) and
[x86_64](results/2026-10-18/refresh-request-x86_64.txt) reports have their
raw [AArch64 serial](results/2026-10-18/refresh-request-aarch64.serial.txt) and
[x86_64 serial](results/2026-10-18/refresh-request-x86_64.serial.txt) evidence
and QEMU command logs alongside them. The
[ledger](results/2026-10-18/refresh-request-ledger.json) binds all saved evidence,
original source snapshots, generated C, deployed binaries, prebuilt kernels and
the V-only media adapter. Run the retention helper with `--verify` to check it.
