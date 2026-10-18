# Owned public package plan previews

`Service.plan()` and `preview_plan()` return independently owned `Plan` values.
Call `.close()` when finished; repeated close of the same value is harmless.
Every root string, publisher identity and manifest field belongs to that reply,
including arguments, permissions, MIME associations, dependency ranges and
payload paths/digests. Replies remain usable after configuration, catalog,
installed state, caller IDs or another preview have retired.

The public request retires decoded state and the existing preparation owner on
success and refusal. `Service.plan()` additionally retires its state-directory
path and freshly loaded configuration. `preview_plan()` borrows its explicit
configuration and directory. Both still acquire the existing reader lock before
reading state/catalog; service locking precedes configuration reads. Removal
and empty deployment retain their revoked-publisher behavior. Resolver
preference, policy, exact repair, trust and architecture checks are unchanged.

The CLI `plan` command closes its reply and output string. Existing deployment
and repair fixtures also close public previews. Plan JSON retains exactly its
existing `requested`/`packages` shape and complete manifest values; there is no
new wire field, approval identity or persistent format. Low-level `resolve()`
and transaction plans continue to borrow manifests. Do **not** use `.close()`
on those borrowed values or ordinary caller-built plans.

The [fixture](../../tools/packages/pkgcore/plan_observation_test.v) publishes a
signed three-package closure and update for both architecture declarations.
After initialization and a warm pass, 48 cases per declaration each make 64
complete calls and retire replies/errors: **6,144 measured public requests**.
All measured scopes require zero retained tracked V bytes. Cases include fresh
and installed previews, retained versus latest versions, repair, removal,
deploy, cached offline use, invalid arguments, dependency blockers, missing
packages, policy refusal, revoked removal/empty deployment, corrupt catalog,
history/state, writer contention before configuration reads and malformed
configuration. Persistent configuration, catalog, trust history, generations,
cache objects and activation pointer retain their bytes.

A separate 33-package input exercises all nested manifest storage, Unicode,
long descriptions, runtime/entrypoint strings and full-width sequence/payload
numbers. Each declaration measures 1,000 complete copies and retirements with
zero retained tracked bytes. Replies encode identically after source owners and
another reply retire. Public previews also preserve exact internal plan JSON
after configuration, state, catalog and caller names have been freed.

The pre-change baseline uses two calls in each of the same 48 public cases.
Two installed service previews retained 87,486 bytes for AArch64 declarations
and 87,468 for x86_64; explicit-configuration previews retained 79,744 and
79,732 bytes. Even fresh repair/empty service plans retained 7,742/7,736 bytes,
and busy/configuration failures retained 140/138 bytes. Baseline executable,
captured original sources and raw output are retained. These are scoped fixture
totals, not whole-process rates. The fixed fixture additionally checks the
nested-copy owner and independent reply lifetime.

This boundary covers complete public plan observations and reply/error
retirement. It does not establish complete activation, refresh, collection or
generic CLI encoder ownership. ASan uses `detect_leaks=0`; scoped tracking starts
after fixture/JSON initialization. Broader section 14 production publisher and
catalog migration, graphical-session and foreign-runtime acceptance remain open.

Run the [host driver](plan-observation-check.v) with a reviewed compiler:

```sh
v -nocache -o /tmp/plan-observation tests/packages/plan-observation-check.v
V=/path/to/reviewed/v /tmp/plan-observation /build/new-plan-observation
```

Its 34 compile/run checks cover six package fixtures normally and under
ASan/UBSan, compilation without heap instrumentation, real CLI behavior and
signed corruption-repair maintenance through both CLI builds. Tracked resolver
preference and complete review requests remain regression controls. The
[native controller](plan-observation-runtime-check.v) checks tracked previews
and resolver preference plus signed service/empty-deployment behavior on both
targets, using pinned prebuilt kernels and a 900-second TCG limit. The
[retention helper](plan-observation-retain.v) saves raw reports and source,
compiler, binary, kernel and evidence hashes; `--verify` checks the ledger.

The initial host attempt ran out of disk space during normal resolver-preference
compilation. After reclaiming superseded, unretained private outputs, a pinned
continuation verified every original input hash before reusing the five already
successful compilation outputs. All fixture runs were repeated and all remaining
compilations/runs proceeded normally. Those five compile records have zero
seconds in the receipt; the continuation source/binary, original input pins and
[disk-space failure log](results/2026-10-18/plan-observation-host-no-space.txt)
are retained. This was a compiler output-file failure, with no source change.

Recorded 2026-10-18 results:

- [All 34 host checks passed](results/2026-10-18/plan-observation-host.txt).
  The [receipt](results/2026-10-18/plan-observation-host.json) retains commands,
  source/compiler hashes, timings and artifacts for previews, borrowed resolver
  behavior, service/review/deployment controls and both real CLI maintenance runs.
- The [normal preview run](results/2026-10-18/plan-observation-plan-run.txt) and
  [ASan/UBSan run](results/2026-10-18/plan-observation-plan-sanitize-run.txt)
  each report zero retained bytes in all 96 public-request scopes and both
  nested-copy scopes. The [baseline](results/2026-10-18/plan-observation-baseline.txt)
  records the original two-call totals above.
- Fresh target fixtures passed on
  [AArch64 in 145.1 seconds](results/2026-10-18/plan-observation-aarch64.txt) and
  [x86_64 in 175.2 seconds](results/2026-10-18/plan-observation-x86_64.txt).
  Both repeat the complete preview/copy scopes and borrowed-resolver, signed
  service and empty-deployment controls; raw serial logs are retained.
- Complete desktop headless typechecks passed for
  [arm64](results/2026-10-18/plan-observation-desktop-arm64.txt) and
  [amd64](results/2026-10-18/plan-observation-desktop-amd64.txt), using current
  desktop sources and staged generated Calculator/translation assets.

The frozen compiler was V `0.5.2 826e96f`, executable SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
The [hash ledger](results/2026-10-18/plan-observation-ledger.json) binds retained
evidence, captured original sources and current source/tool/artifact inputs.
