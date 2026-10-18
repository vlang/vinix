# Owned complete package review requests

`Service.review()` and `Service.review_deployment()` now retire their complete
request preparation on success and refusal. The request owns its state-directory
path, loaded configuration, decoded active/rollback states, deployment document,
authenticated catalog and solver buffers. The returned `pkgprotocol.Review`
continues to own every presentation field independently; callers use `.close()`.
The configuration-taking `review_operation()` borrows its configuration and
retires the state/catalog/plan preparation it creates.

An internal preparation owner distinguishes solver buffers from repair's
borrowed state buffers, and authenticated catalogs from removal's borrowed
installed manifests. It retires containers before the manifests and retires
all preparation before configuration/state owners. Empty deployment and removal
remain available after publisher revocation. Rollback validation releases
temporary paths and a refused decoded target; a successful target transfers to
its caller. All existing trust, policy, locking, exact-pin, disk and stale-review
checks remain in place. Approval identities and wire/persistent formats do not
change.

The [fixture](../../tools/packages/pkgcore/review_request_test.v) publishes a
signed three-package closure and an update on both architecture declarations.
After initialization and a warm pass, each of 43 scopes makes 64 complete public
calls and closes the returned review or error. All 5,504 measured calls require
zero retained tracked V bytes. The scopes cover:

- Fresh install/repair and unavailable rollback; installed install, upgrade,
  repair, rollback, removal, deployment and offline cached reviews.
- Legacy, exact, older-version and empty deployment documents; changed pins,
  surplus closure and malformed documents.
- Missing packages, dependent removal, invalid maintenance arguments, current
  policy refusals, revoked rollback and still-available removal/empty deployment.
- Damaged old payload/registration, damaged current repair, corrupt catalog,
  trust history or state, and late generation-counter refusal.
- Writer contention before malformed configuration/document reads, and
  malformed configuration after lock release.

Replies validate after preparation has retired. A separate check frees caller
names before validating, encoding and double-closing a reply. Configuration,
catalog, trust history, generation metadata, cache objects and activation pointer
retain their bytes through reviews; deliberately damaged inputs are restored
and checked again. Existing signed service, construction, review, deployment,
repair and CLI fixtures check freshness, identities and maintenance behavior.

The pre-change baseline uses two measured calls per scope across 33 cases per
architecture. On AArch64 declarations two installed install reviews retained
86,664 bytes, two rollback reviews 91,122 bytes and two exact deployment reviews
89,434 bytes. Even busy/configuration refusals retained 136 bytes. The x86_64
declaration totals were 86,646, 91,092, 89,410 and 134 bytes respectively. These
are bounded fixture totals, not whole-process memory rates. The fixed fixture
adds ten refusal scopes and increases every measured loop to 64 calls.
The initial `v run` wrapper retired the temporary baseline executable. A rebuild
from the captured original sources reproduces its complete output byte for byte;
the ledger includes that reference executable, rebuild helper and both logs.

This boundary covers ordinary and deployment **review requests**. Legacy Plan
and activation APIs still return borrowed manifests and retain their existing
storage lifetime; other complete service/CLI operations remain separate work.
ASan runs with `detect_leaks=0`, while UBSan stops on errors. Scoped tracking
measures the public calls and reply/error retirement, after fixture construction
and JSON initialization; it does not claim whole-process allocation freedom.
Section 14's production publisher/catalog migration, graphical-session and
foreign-runtime release gates remain open.

Run the [host driver](review-request-check.v) with a reviewed compiler:

```sh
v -nocache -o /tmp/review-request tests/packages/review-request-check.v
V=/path/to/reviewed/v /tmp/review-request /build/new-review-request
```

Its 31 compile/run checks cover six package fixtures normally and under
ASan/UBSan, the request fixture without heap instrumentation, and the real CLI.
The [native controller](review-request-runtime-check.v)
runs tracked request, construction and signed review fixtures plus deployments
on each target, with a 900-second TCG limit. Native userland checks use pinned
prebuilt kernels. The [retention helper](review-request-retain.v) binds source,
compiler, binaries, kernels and retained evidence; `--verify` rechecks the ledger.

Recorded 2026-10-18 results:

- [All 31 host checks passed](results/2026-10-18/review-request-host.txt).
  The [receipt](results/2026-10-18/review-request-host.json) retains commands,
  source/compiler hashes, timings and artifacts, including signed service
  freshness, construction identities, maintenance and real CLI controls.
- The [normal request run](results/2026-10-18/review-request-request-run.txt)
  and [ASan/UBSan run](results/2026-10-18/review-request-request-sanitize-run.txt)
  each report zero retained bytes in all 86 measured scopes. The
  [pre-change baseline](results/2026-10-18/review-request-baseline.txt) retains
  the original bounded totals described above.
- Fresh target fixtures passed on
  [AArch64 in 171.6 seconds](results/2026-10-18/review-request-aarch64.txt) and
  [x86_64 in 168.1 seconds](results/2026-10-18/review-request-x86_64.txt), using
  pinned prebuilt kernels and TCG. Both repeat the full request scope and
  construction/fingerprint, signed review and deployment controls; raw serial
  logs are retained beside the controller reports.
- Complete desktop headless typechecks passed for
  [arm64](results/2026-10-18/review-request-desktop-arm64.txt) and
  [amd64](results/2026-10-18/review-request-desktop-amd64.txt), using current
  desktop sources and staged generated Calculator/translation assets.

The frozen compiler was V `0.5.2 826e96f`, executable SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
The [hash ledger](results/2026-10-18/review-request-ledger.json) binds retained
evidence, original measured sources and current source/tool/artifact inputs.
