# Installed dependency inspection in Software

An installed runtime previously had only the generic **Dependency/runtime**
role. Software's **Details → Diagnostics** now discloses the installed package's
direct requirements, inclusive minimum and exclusive upper version bounds, and
each dependency's installed version. Overview points to these facts. The
displayed update candidate cannot replace this history before activation.

The inspector also names one requested package that requires the selection,
directly or transitively. A reverse graph walk visits each installed node and
edge at most once, handles cycles/shared dependencies, and chooses the lexical
requested-package ID independently of row order. The selected package itself
does not count as another requiring application. This is one witness, rather
than an exhaustive dependent list or authorization to remove a package.
Reviewed uninstall remains authoritative and removes unused dependencies.

The additive SDK-1 `installed_dependencies_known`/`installed_dependencies` pair
distinguishes an explicitly empty requirement list from unavailable history.
Partial pairs, unknown nonempty lists, noninstalled known facts, duplicate IDs,
invalid/empty ranges and malformed, coerced or oversized records refuse the
entire view. Each record requires all three strings, including empty bounds;
there are at most 128 records per row. Legacy replies remain accepted, with
explicit unavailability and a warning when usage information is incomplete.
Old readers continue to ignore the additive fields.

Complete and compact details retain requirement IDs and bounds across page
boundaries. Review inspectors retain their reviewed-target scope. Inspection
does not start workers, request approval or modify package state. Invalid
asynchronous replies retain the previous valid catalog and selection.

The [core suite](../../tools/packages/pkgcore/view_test.v) checks both host
architecture declarations through update previews, dependency removals,
revocation, activation and restored generations. Its signed on-disk
install/refresh regression encodes the actual service response through the
public decoder. The [protocol suite](../../tools/packages/pkgprotocol/view_reader_test.v)
checks complete/legacy groups, explicit emptiness, nested escaped duplicates,
type/range/bounds refusal and the 128-record limit.

The maintained [graph fixture](software_dependencies_fixture.v) checks shared
and cyclic graphs, row reordering, a 4,096-node chain and tracked graph cleanup.
The [view fixture](software_view_fixture.v) checks asynchronous refusal and
legacy fallback. The [details fixture](software_details_fixture.v) checks
complete/compact rendering, maximum-length IDs/version bounds, frozen reviews
and 1,000 measured page preparation/retirement cycles. The catalog-reload mode
also measures 1,000 cycles with owned dependency arrays and strings.

Run the shared [presentation qualification driver](software-provenance-check.v)
with the reviewed compiler and staged headless ui2 module:

```sh
v -nocache -o /tmp/software-view-check tests/packages/software-provenance-check.v
V=/path/to/reviewed/v VINIX_PACKAGE_TEST_UI2=/path/to/modules \
  /tmp/software-view-check /build/new-software-dependencies
```

Its existing provenance suite includes these dependency regressions: core and
protocol normally/under ASan+UBSan, the full Software functional fixture in both
modes, and catalog/details allocation modes on each UI binary. The shared
[native controller](software-provenance-runtime-check.v) runs those core and
protocol tests on both targets through the standard hardware harness. These
are native service/protocol checks and host UI-tree checks; graphical login,
presentation, production catalog migration and broader runtime acceptance
remain open under roadmap section 14.

## Recorded results, 2026-10-18

All **16 host checks passed**, including ASan/UBSan. Each catalog and details
allocation mode retained zero tracked bytes across 1,000 measured cycles on
both UI binaries; 1,000 graph queries also retained zero tracked bytes. Both
full desktop architecture typechecks passed with staged Calculator/translation
sources and headless ui2. These checks cover types and UI trees, rather than
graphical presentation. Sanitizer leak detection was disabled; allocation
claims apply to the explicit measured scopes above.

Both native guests passed: **aarch64 21.0 s**, **x86_64 29.8 s**. They reused
the pinned prebuilt kernels and existing V plain-USTAR adapter for the x86_64
legacy boot-media contract. The frozen compiler is V 0.5.2 `826e96f`, with
compiler fallback and automatic compiler error reporting disabled.

The retained [host receipt](results/2026-10-18/software-dependencies-host.json),
[summary](results/2026-10-18/software-dependencies-host.txt) and
[ledger](results/2026-10-18/software-dependencies-ledger.json) record the exact
commands, inputs and artifacts. Native [aarch64](results/2026-10-18/software-dependencies-aarch64.txt)
and [x86_64](results/2026-10-18/software-dependencies-x86_64.txt) reports retain
their raw serial logs. The [retainer](software-dependencies-retain.v) verifies
local source/compiler/artifact/evidence hashes while those files remain available.
