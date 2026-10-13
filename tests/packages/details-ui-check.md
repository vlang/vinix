# Complete package details in Software

Software's fixed catalog/review labels can clip long descriptions, identities,
licenses and diagnostics. **Package details…** opens a read-only inspector for
the selected catalog, installed, update or reviewed package. Overview,
Description, Publisher, Permissions, License and Diagnostics sections expose
complete values through bounded UTF-8 pages.

Catalog/update details separate the displayed version's permissions from the
installed launch declaration. Missing installed fields from an older service
are reported as unavailable. Review details include operation, action, role,
generations, exact disk byte counts and literal deployment/export paths.
Proprietary and firmware flags remain explicit. ASCII control bytes are shown
as `\xHH`; invalid UTF-8 or oversized text refuses the inspector.

While inspecting, only section selection, paging, Back and Escape are active.
Hidden confirmation, cancellation, launch, selection, reload and input events
are ignored. Returning preserves the catalog selection or the pending review
snapshot, selected row and scroll. Cached text owns its buffers and is released
on return, reload, review retirement and normal close.

[The actual-source V fixture](software_details_fixture.v) checks:

- Complete reconstruction of long multibyte descriptions, repository/key,
  license and package/catalog/update diagnostics across page boundaries.
- Installed versus displayed permissions, legacy unavailable fields, explicit
  licensing flags, invalid UTF-8, text bounds and window-protocol bounds.
- Minimum-window layout, section/page boundaries, hidden-action refusal,
  unchanged install/remove/upgrade/deploy/rollback/mirror reviews, long Unicode
  deployment paths, Escape, retirement and an asynchronous catalog reload.
- 1,000 catalog and review open/redraw/navigate/back/retire cycles, after warmup,
  with more than 32 cached pages to force buffer growth: zero tracked bytes
  retained under `-gc none -manualfree`.

Run the Software suite with the pinned compiler and a staged headless ui2 module:

```sh
V_MACOS_V3_NO_FALLBACK=1 V=/path/to/pinned/v CPATH="$PWD/desktop" \
VINIX_PACKAGE_TEST_UI2=/path/to/staged/modules \
/path/to/pinned/v -no-skip-unused run tests/packages/distribution-check.v \
  --software-only --direct-tests
```

This qualification covers host UI presentation and lifetimes. Both Linux target
frontends are checked; it adds no guest service or package-format change and
claims no new QEMU receipt. Ordinary graphical login/display integration, real
publisher enrollment and complete native/Linux/Wine/Apple runtime catalogs
remain separate release gates.

The retained host run uses V 0.5.2 at
`826e96f56ca12fcb8fd02dfd6edf1551008e62a8` with fallback disabled and declaration
pruning disabled. The complete Software functional suite and all six manualfree
allocation fixtures passed. The same functional suite passed clang ASan/UBSan
with `ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1`; allocation
retention is measured separately by the tracked-heap fixture. Both Linux target
frontends and the fifteen existing full-desktop package-launcher assertions
passed with exit status zero.

The full-desktop test stage applies a missing upstream headless control-state
guard and the existing workflowbuild generated-C compatibility fixes, then
links the original pinned OS/sync helper implementations omitted from emitted C.
These are test-stage adaptations; production dependencies were not changed.
The first details fixture omitted buffers initialized by the real constructor
and failed with `tos(): nil string`; correcting its setup preceded the final
passing runs. An initial driver invocation also lacked the staged ui2 location.

- [Host results](results/2026-10-13/details-ui-host.txt).
- [Initial attempt and corrections](results/2026-10-13/details-ui-attempts.txt).
- [Source, toolchain and retained-artifact hashes](results/2026-10-13/details-ui-toolchain.json).
