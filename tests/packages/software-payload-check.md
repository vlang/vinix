# Installed payload disclosure in Software

Software's **Details → License** now shows the installed generation's license,
proprietary/firmware flags and runtime ID alongside the displayed candidate's
declarations. Both versions are labelled. Installed facts survive update
previews, catalog failures, publisher revocation and policy changes. Generation
activation or rollback changes the installed disclosure with the active state.
No facts are invented for an uninstalled candidate or an older service.

The additive SDK-1 quartet `installed_license`, `installed_proprietary`,
`installed_firmware`, `installed_runtime` is either complete or omitted. An
empty license, false flags and empty runtime mean unavailable. Nonempty facts
require an installed version, a bounded printable license and a valid optional
runtime ID; known foreign application kinds require a runtime. Partial groups,
duplicate/escaped keys, wrong types, invalid Unicode and oversized values refuse
the whole view. Strings are owned and retired on replacement and refusal.
Existing readers ignore these additive fields.

Full and compact details retain complete values, including long Unicode license
text and runtime IDs. Overview points to the License inspector. Older services
show explicit unavailability. Review details retain their reviewed-target scope;
inspection cannot confirm an operation or change policy or package state.
Historical declarations grant no license acceptance or firmware authorization.

The [core suite](../../tools/packages/pkgcore/view_test.v) checks both host
architecture declarations, opposite flag transitions, runtime removal, preview,
policy/trust/catalog failures and activated/restored generations. The
[protocol suite](../../tools/packages/pkgprotocol/view_reader_test.v) checks
all 16 quartet presence masks, Unicode/type/length/identity bounds, escaped
duplicates, explicit false/empty facts and uninstalled-row refusal.
The [Software reader](software_view_fixture.v) checks asynchronous refusal with
the previous catalog/selection retained. The [details fixture](software_details_fixture.v)
checks complete full/compact pages, legacy disclosure, review scope and owned
page retirement. These extend the shared presentation qualification:

```sh
v -nocache -o /tmp/software-view-check tests/packages/software-provenance-check.v
V=/path/to/reviewed/v VINIX_PACKAGE_TEST_UI2=/path/to/modules \
  /tmp/software-view-check /build/new-software-payload
```

The shared [native controller](software-provenance-runtime-check.v) runs the core
and protocol suites on both targets. Host UI tests inspect generated trees;
native checks exercise service/protocol code without graphical presentation.
Production publisher/catalog migration, graphical login/presentation and wider
runtime/device acceptance remain open under roadmap section 14.

## Recorded results, 2026-10-18

All **16 host checks passed**, including ASan/UBSan. The normal and sanitized
catalog/details modes each retained zero tracked bytes across 1,000 measured
cycles. These measurements cover reload, partial refusal, legacy replies,
full/compact page construction, navigation and retirement. Sanitizer leak
detection was disabled; allocation claims apply to these explicit scopes.
Both complete desktop architecture typechecks passed using headless ui2 and
staged generated Calculator/translation sources.

Both native guests passed: **aarch64 9.4 s**, **x86_64 9.1 s**. They reused the
pinned prebuilt kernels and V plain-USTAR adapter for the older x86_64 boot-media
contract. Initial media preparation ran out of host disk space before either
guest booted; disposable old package boot media was removed and both runs were
repeated successfully. Retained results describe the successful reruns. The
compiler is frozen V 0.5.2 `826e96f`, with fallback and automatic compiler-error
reporting disabled.

The [host receipt](results/2026-10-18/software-payload-host.json),
[summary](results/2026-10-18/software-payload-host.txt) and
[ledger](results/2026-10-18/software-payload-ledger.json) retain commands and
source/compiler/artifact hashes. Native [aarch64](results/2026-10-18/software-payload-aarch64.txt)
and [x86_64](results/2026-10-18/software-payload-x86_64.txt) reports accompany
the raw serial logs. The [retainer](software-payload-retain.v) verifies all
local inputs, artifacts and evidence with `--verify` while those files remain
available. These are host UI-tree and native service/protocol checks; they do
not qualify a graphical session or the remaining section-14 release gates.
