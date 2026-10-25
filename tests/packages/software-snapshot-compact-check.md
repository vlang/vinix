# Software compact deployment save qualification

The compact deployment snapshot form exposes an editable absolute filename and
Save at 320×240 and 400×300. Idle forms retain Back and optional failure details;
writers retain their path and status while navigation, input and close stay
blocked. Below either 320 pixels wide or 240 pixels high, a bounded fallback
asks the user to enlarge the window. Its Back, failure and waiting states fit
the window manager's 180×96 minimum; editing and Save require enlargement.

The maintained [V driver](software-snapshot-compact-check.v) stages the actual
Software source with the [focused fixture](software_snapshot_compact_fixture.v).
Only the historical fixture's entry point receives a private dispatch adapter.
Every focused condition and every child barrier uses explicit checked code, so
production builds execute the same functional checks.

The shared [hosted boundary fixture](software_hosted_fixture.v) supplies the
unexercised graphical backend's types and panics on every backend operation.
The staged UI module applies the existing `launcher-check.v` headless exclusion
to native mounted-control helpers; original and adapted UI sources are retained
and hashed separately. No application behavior is replaced by these adapters.
Host Clang permits the existing package-admin socket pointer conversion with
`-Wno-error=incompatible-pointer-types`; sanitizer diagnostics remain fatal.

The five host variants are normal, production, tracked normal, tracked
production and ASan/UBSan. Each verifies:

- Draft, active writer, failure and ready geometry at 320×240, 400×300,
  180×96, 319×239, 319×240 and 320×239, including positive dimensions,
  containment, nonoverlap and the expected controls and status.
- Empty filename refusal and invalid paste preserving filename, focus and
  selection; a Unicode filename containing spaces, a semicolon and `$literal`
  reaches a real child as one literal argument.
- Three real child barriers: a partial receipt, a complete receipt from a
  still-running writer, and a complete receipt followed by failure. Navigation,
  input and close stay blocked until the child exits; a late failure never
  becomes a successful receipt.
- A fresh audit uses the successfully captured destination after the form's
  current filename changes, and catalog selection remains unchanged.

Tracked variants first check positive allocation and balanced free controls,
then warm and measure 1,000 steady render cycles over draft, ready and failure
at all six sizes: 18,000 real build/free trees per variant. Active writer
geometry is checked at the real barriers; active writer rendering is outside
the allocation measurement. The historical full Software fixture also runs
once in the normal build, including the updated compact Save expectation.

Run the driver as a production executable, passing the V compiler, UI module
directory and a fresh external evidence directory:

```sh
/path/to/v -prod -cc /path/to/clang -o /external/compact-check tests/packages/software-snapshot-compact-check.v
/external/compact-check /path/to/v /path/to/vmodules /external/new-compact-evidence
```

The driver freezes and rechecks project and UI sources, its own embedded
source, staged fixture files, and V/Clang executable hashes. The complete
external bundle contains source inventories, exact command vectors, logs,
binaries and generated C. Imported V library and third-party sources, system
headers, linker and transitive tools are not frozen: this is a bounded host
qualification, not a hermetic or reproducible build claim. ASan leak detection
is disabled; V retention is measured separately by the allocation tracker.

Execution record: 2026-10-26, macOS arm64: all five focused modes passed, as did
the supplementary historical normal Software suite. Both tracked modes retained
zero V bytes and zero records across their 18,000 render trees. Source and
compiler rechecks passed. The isolated worktree baseline was
`dd31da9f42764c7c8113a9c72673ddff5513decf`, with the compact implementation
still uncommitted during execution. Tested `desktop/software_snapshot.v` SHA-256:
`0c1283a83eb2e1361ddb62ba59ec57a1042cf233b734b42f375293c86198f805`.
The complete frozen project inventory, including the working edits, is
`sources.json`, SHA-256:
`27bb6bc5e40aec4dafc9d1bd0f8cf002abf791efa99254c57672adbd9c90fe4b`.

The retained evidence directory is
`/Users/alex/Library/Caches/vinix-codex/section14/software-snapshot-compact-20261026-05`.
Its `result.json` SHA-256 is
`543b906c52a0d8f278906e621a9cc24b2bf5393bf7a35ed076c37f7ed4b30ea4`.
That result binds the original and adapted UI inventories, staged source,
execution artifacts and compiler executable hashes. Generated evidence remains
outside Git.

This is headless host validation. It does not establish target guest execution,
compositor appearance, real package snapshot persistence, or completion of all
roadmap section 14 features.
