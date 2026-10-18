# Installed publisher provenance in Software

Software's catalog/update rows previously disclosed only the displayed
candidate's repository and key. After an explicitly reviewed signing-key
rotation, an update could show the new key while the installed generation still
recorded the old key. The Publisher inspector now shows the installed repository
and signing key separately. Historical provenance stays visible after revocation
or a catalog failure. It does not imply current trust.

The service reads the installed pair from the active generation, including
dependencies pending removal. New, uninstalled candidates have no installed
provenance. Activation and restored generations naturally supply their own
recorded identities. Resolution still prevents one repository ID from taking
over another repository's installed package.

The SDK-1 presentation adds `installed_repository` and `installed_public_key`
as an optional pair, independent of the existing installed-launch groups.
Omitting both, or sending both empty, reports unavailable provenance. Nonempty
values require an installed version, a valid repository ID and a canonical
64-character key. Partial groups, duplicate/escaped duplicate keys, coerced
types, invalid identity/Unicode and oversized fields refuse the entire view.
Older readers ignore the additive columns; newer readers never infer installed
identity from the candidate. Decoded strings are retired on refusal, replacement
and close.

Full and compact Publisher pages retain complete identities across UTF-8 page
boundaries. A legacy service reports **Installed publisher: Unavailable from
this service**. Review inspectors continue to describe the reviewed target
publisher, without presenting candidate identity as installed history. No trust,
approval, launcher or package-state behavior changes.

The [core tests](../../tools/packages/pkgcore/view_test.v) cover both architecture
declarations, key rotation, pending dependency removal, revocation, activation,
restored generations, unavailable catalogs and uninstalled candidates. They
also encode the actual service view through the public protocol decoder. The
existing signed on-disk install/refresh case checks provenance returned from
persistent package state.

The [protocol tests](../../tools/packages/pkgprotocol/view_reader_test.v) check
the paired fields, legacy launch shapes, missing provenance, invalid/duplicate/
partial inputs and uninstalled identity refusal. The maintained Software
[view](software_view_fixture.v) and [details](software_details_fixture.v)
fixtures check asynchronous malformed replies retaining the previous valid view,
complete compact disclosures, legacy unavailability and review scope. Their
1,000-cycle catalog-reload and details-page allocation modes include the new
strings and growing publisher page lists.

Run the [host controller](software-provenance-check.v) with a reviewed V compiler
and staged headless ui2 module:

```sh
v -nocache -o /tmp/software-provenance-check tests/packages/software-provenance-check.v
V=/path/to/reviewed/v VINIX_PACKAGE_TEST_UI2=/path/to/modules \
  /tmp/software-provenance-check /build/new-software-provenance
```

It runs core/protocol suites and the full Software functional fixture, both
normally and with ASan/UBSan, plus the two focused allocation modes for each
UI binary. Sanitizer leak detection is disabled; tracked allocation scopes are
the stated UI loops, not the complete service or spawned workers.

The [native controller](software-provenance-runtime-check.v) boots the core and
protocol tests on aarch64 and x86_64 with the standard
[hardware harness](../hardware-platform/README.md). Both guests run the real
signed on-disk service regression, key-rotation projections and decoder checks;
this is separate from graphical login/compositor/runtime acceptance. Roadmap
section 14 remains open for those release gates and production catalog migration.

## Recorded results, 2026-10-18

All **16 host checks passed**: core/protocol suites and the full Software
functional fixture, normally and under ASan/UBSan, plus both focused UI
allocation modes on each UI binary. Each catalog-reload and details-page mode
retained zero tracked bytes over 1,000 measured cycles. Both full desktop
architecture typechecks passed with staged Calculator/translation sources and
headless ui2; those checks cover types rather than graphical presentation.

| Native target | Result | Guest time | Evidence |
| --- | --- | --- | --- |
| aarch64 | PASS | 17.1 s | [report](results/2026-10-18/software-provenance-aarch64.txt), [serial](results/2026-10-18/software-provenance-aarch64.serial.txt) |
| x86_64 | PASS | 21.4 s | [report](results/2026-10-18/software-provenance-x86_64.txt), [serial](results/2026-10-18/software-provenance-x86_64.serial.txt) |

The [host receipt](results/2026-10-18/software-provenance-host.json) records
commands, timings, source/compiler pins and artifacts; its
[summary](results/2026-10-18/software-provenance-host.txt) lists every check.
The [recorded-run retainer](software-provenance-retain.v) preserves raw logs and
binds **359 local source/compiler/artifact hashes and 18 evidence hashes** in
the [ledger](results/2026-10-18/software-provenance-ledger.json). Its `--verify`
mode rechecks those hashes while the local artifacts remain available.

The frozen compiler is V 0.5.2 `826e96f`, with compiler fallback and automatic
compiler error reporting disabled. Native runs reused the pinned prebuilt
kernels; a V plain-USTAR adapter served the x86_64 kernel's legacy media
contract. Kernel and production boot-media code were unchanged. An early host
fixture staging attempt included the separate Software image program and
refused duplicate declarations; the maintained driver now excludes that
independent entrypoint. The final complete run and retained evidence use the
corrected fixture set.
