# Permission changes in package reviews

Software previously showed only each reviewed target's permission declarations.
It now compares them with the active generation's frozen declarations, including
dependencies and removals. The review status and plan reader count known added
and removed declarations and packages whose prior facts are unavailable.
**Package details → Permissions** shows the version-labelled previous set and
each added, removed or unchanged declaration in full and compact readers.

New installs compare with an empty previous set. Uninstall removes that
package's declarations; repair and unchanged packages preserve them. Rollback
compares the restored target with the current generation. Offline export shows
its target declarations and explains that exporting does not change installed
access. Legacy facts remain explicitly unavailable and never inherit a catalog
preview's permissions. Organization policy and runtime isolation still govern
actual access; these comparisons do not grant permissions or alter approval.

The service emits **review format 2**. Its bounded optional
`installed_permissions_known`/`installed_permissions` pair records active-state
facts independently of the target `permissions`. Partial/duplicate groups,
coercions, invalid/repeated/oversized permissions and inconsistent new-install,
keep/removal/repair facts refuse before confirmation. Format-1 reviews remain
readable with unavailable prior declarations; populated prior facts require
format 2. Old strict consumers refuse format 2, so deploy the updated Software
and package tools together. No persistent package/manifest/launch format changes.
The existing fingerprint already binds the complete current state and target
plan, including permission declarations; stale admission remains under the lock.

The [service assertions](../../tools/packages/pkgcore/review_test.v) cover both
architecture declarations through signed install/update/repair/rollback and
removal after revocation. A measured 1,000-cycle row construction/retirement
scope requires independently owned previous and target sets with zero retained
tracked bytes. The [protocol assertions](../../tools/packages/pkgprotocol/review_permissions_test.v)
cover current/legacy/known-empty sets, fifteen malformed groups and 1,000
valid/legacy/refused decoding cycles per architecture declaration.

The [Software fixture](software_review_permissions_fixture.v) checks all seven
review operations, dependencies, removed packages, full/compact paging,
version-labelled comparisons, unknown legacy facts and frozen review/approval
state. A measured 1,000-cycle decode/summary/full/compact/plan-reader/retirement
mode requires zero tracked bytes. The maintained distribution driver stages
the helper/fixture and includes that mode.

Run the [host driver](review-permissions-check.v) with a reviewed V compiler and
the staged headless ui2 module:

```sh
v -nocache -o /tmp/review-permissions tests/packages/review-permissions-check.v
V=/path/to/reviewed/v VINIX_PACKAGE_TEST_UI2=/path/to/modules \
  /tmp/review-permissions /build/new-review-permissions
```

It runs the service, new permission protocol, existing review schema, complete
Software interactions, focused allocation modes and signed CLI maintenance
normally and under ASan/UBSan. The [native controller](review-permissions-runtime-check.v)
runs service/protocol assertions on both targets. Explicit allocation scopes
and headless checks leave complete service allocation freedom, graphical-session
presentation and broader roadmap-14 release/runtime acceptance open.

Recorded 2026-10-18 results:

- [All 29 host compile/run checks passed](results/2026-10-18/review-permissions-host.txt),
  including service assertions, both review schemas, complete Software
  interactions and signed CLI maintenance normally and under ASan/UBSan.
  The [receipt](results/2026-10-18/review-permissions-host.json) retains commands,
  source/compiler hashes and artifact hashes. The unsupported-format fixtures
  now use format 3 because format 2 is supported.
- The [normal](results/2026-10-18/review-permissions-ui-permissions-memory.txt)
  and [sanitized](results/2026-10-18/review-permissions-ui-sanitize-permissions-memory.txt)
  1,000-cycle Software modes retained zero tracked bytes. Row construction and
  valid/legacy/refused decoding scopes also retained zero tracked bytes in both
  modes. ASan used `detect_leaks=0`; UBSan stopped on undefined behavior.
- Fresh native fixtures passed on
  [AArch64 in 28.0 seconds](results/2026-10-18/review-permissions-aarch64.txt) and
  [x86_64 in 35.9 seconds](results/2026-10-18/review-permissions-x86_64.txt),
  using pinned prebuilt kernels. Each guest exercised both architecture
  declarations, signed service maintenance and the row/decoder allocation
  scopes. Raw serial logs are retained beside these reports.
- Full desktop headless typechecks passed for
  [arm64](results/2026-10-18/review-permissions-desktop-arm64.txt) and
  [amd64](results/2026-10-18/review-permissions-desktop-amd64.txt), using current
  desktop sources and the staged generated Calculator/translation assets.
  The maintained distribution driver also typechecked.

The frozen compiler was V `0.5.2 826e96f`, executable SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
The [retention helper](review-permissions-retain.v) verifies inputs/artifacts
before saving evidence. Its `--verify` mode checks the final
[hash ledger](results/2026-10-18/review-permissions-ledger.json).
