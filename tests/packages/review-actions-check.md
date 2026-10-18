# Package review action and version agreement

A review could previously label an existing-package action with an empty
installed version, or retain/remove a package while displaying a different
version. Permission readers could then treat unavailable history as an empty
previous set and report a new install's additions.

Both supported review formats now require:

- `install` and `export`: no installed version.
- `update`: an installed version. Same-version repairs/provenance changes and
  rollback to a lower version remain valid.
- `keep` and `remove`: displayed and installed versions agree.
- Remove operations contain only keep/remove rows; repair retains its existing
  version/action restrictions. Mirror exports retain export-only restrictions.

These checks apply to direct V validation, bounded review decoding and both
nested offline-export envelopes. Optional permission history remains compatible:
complete/omitted false/empty pairs still mean unavailable for installed packages.
Software's permission renderer also treats an existing-package action without
history conservatively, even when called directly with an unvalidated value.
It never labels that unknown set as not installed, counts invented additions or
reports no changes. Only an admitted new-install action compares with no prior
declarations. Export still explains that it changes no installed permissions.

Software clears a contradictory response and any previous proposal. Full and
compact screens expose no Confirm action; directly dispatching Confirm starts
neither an administrator prompt nor a maintenance worker. Service output, review
fingerprints, package state and package/launch formats are unchanged. Legitimate
legacy replies remain readable; old contradictory replies must be regenerated.

The [protocol cases](../../tools/packages/pkgprotocol/review_actions_test.v)
cover seventeen legitimate cases and sixteen contradictions on both architecture
declarations and both formats. Each case is tested with the optional permission
pair present and omitted. Nested mirror and deployment-mirror controls cover
exports with and without an installed version. A measured 1,000-cycle
decode/close/refusal scope per format/architecture requires zero tracked bytes.

The [Software assertions](software_review_actions_fixture.v) exercise refusal
after an already-ready proposal, direct-renderer uncertainty, legitimate legacy
updates and new installs. A measured 1,000-cycle mode alternates both formats'
malformed updates/keeps/removals, full/compact rendering, blocked confirmation,
new installs, permission inspection and retirement. Existing fixtures now use
the service's actual action/version combinations, including removal-only
deployments, offline exports and the maximum 8,192-row plan.

Run the [host driver](review-actions-check.v) with a reviewed V compiler and the
headless ui2 module:

```sh
v -nocache -o /tmp/review-actions tests/packages/review-actions-check.v
V=/path/to/reviewed/v VINIX_PACKAGE_TEST_UI2=/path/to/modules \
  /tmp/review-actions /build/new-review-actions
```

The 29 checks cover signed service controls, action decoding, original review
schema checks, complete Software interactions, focused action/permission/metadata
allocation modes and the real CLI, normally and under ASan/UBSan. The
[native controller](review-actions-runtime-check.v) runs the signed service and
action protocol tests on each architecture. The
[retention helper](review-actions-retain.v) saves reports and source/artifact
hashes; `--verify` checks the retained ledger.

Recorded 2026-10-18 results:

- [All 29 host checks passed](results/2026-10-18/review-actions-host.txt),
  with [commands, source hashes and artifacts](results/2026-10-18/review-actions-host.json).
  Signed maintenance, complete Software interactions, action/version admission
  and CLI controls passed normally and under ASan/UBSan.
- The [old-validator control](results/2026-10-18/review-actions-baseline.txt)
  fails on `upgrade/update/` with an empty installed version, establishing that
  the new assertion detects the original defect.
- The [normal](results/2026-10-18/review-actions-ui-review-actions-memory.txt)
  and [sanitized](results/2026-10-18/review-actions-ui-sanitize-review-actions-memory.txt)
  1,000-cycle Software scopes retained zero tracked bytes. Protocol decoding,
  existing permission readers and metadata refusal scopes also stayed flat.
  ASan used `detect_leaks=0`; UBSan stopped on undefined behavior. These are
  explicit allocation scopes, not a whole-service allocation guarantee.
- Fresh service/action fixtures passed on
  [AArch64 in 138.0 seconds](results/2026-10-18/review-actions-aarch64.txt) and
  [x86_64 in 507.5 seconds](results/2026-10-18/review-actions-x86_64.txt).
  Both used pinned prebuilt kernels and TCG with `--timeout 900`; the larger
  x86_64 decoding loop exceeds the controller's default 300-second scenario
  timeout on this host. Raw serial logs are retained beside the reports.
- Complete desktop headless typechecks passed for
  [arm64](results/2026-10-18/review-actions-desktop-arm64.txt) and
  [amd64](results/2026-10-18/review-actions-desktop-amd64.txt), using the current
  desktop and staged generated Calculator/translation assets. The maintained
  distribution driver also typechecked.

The frozen compiler was V `0.5.2 826e96f`, executable SHA-256
`d88f743f74a74289a5ae6d151df4b056f09bf6ccd21e8f28137017891d2cb0af`.
The [hash ledger](results/2026-10-18/review-actions-ledger.json) binds retained
evidence and the reviewed source/tool/artifact inputs.

This closes a review-admission/presentation defect. Production publisher/catalog
migration, real graphical-session presentation, broader Wine/Apple runtime
qualification and the remaining section 14 release gates stay open.
