# Authenticator description validation, 2026-10-26

Source base: `9ef93042331894eaec2b981d5a1f1628dad2f415`; this report is
committed with the parser/model/registry change. Resource-table implementation
is `204f33a93`; bounded ZIP regression tests are `ddf99f300`.

Normal host tests passed with the production account compiler
`/Users/alex/code/v-tccbin-bootstrap-20261026/v`, using `-gc none -manualfree`
and `-path '@vlib|build-support/android'`:

- Six description-parser groups, including exact selected service/action/type,
  cross-service rejection, typed resource fields, malformed/truncated XML and
  owned results.
- Five bounded ZIP groups, including stored/deflated members, descriptors,
  repeated selective reads, duplicates, CRC, truncation, output understatements,
  expansion bounds and trailing compressed input.
- Six resource-table groups for dense/sparse/offset16 entries, configuration
  agreement and rejection paths.
- Existing Activity-manifest and authority-registry regression suites.

Description-parser, ZIP and resource-table tests also passed AddressSanitizer
with `ASAN_OPTIONS=detect_leaks=0`. These checks do not establish leak freedom.
New cleanup paths received independent ownership review; generated C confirms
hash buffers, digest state and returned digest comparisons are released.

Both description-parser runs supplied
`VINIX_AUTHENTICATOR_TEST_APK=/Users/alex/code/vinix/build/android-maps/GooglePlayServices.apk`.
That retained APK has SHA-256
`a34d6a3ccea3ceba491369517e8f12e11df3791e86fec38b1cdf693785e35707`.
Its registered Google authenticator resolves metadata resource `0x7f190008`
to `res/G21.xml` and yields the expected attested `com.google` type and
presentation resource IDs. Production values come from the pinned APK, not
from these test assertions.

Retained test binaries and SHA-256 manifest:
`/Users/alex/.local/state/vinix/android/authenticator-metadata-2026-10-26/`.
`SHA256SUMS` has SHA-256
`07d618d94d1832fd0860481871dc94de7330ab09503df04ad50120291337474a`.
The maintained regression sources remain in `accountmanifest`. The parser uses
the system zlib inflater through `zlib.h` and `-lz`; manual guest linking must
admit a matching pinned header/library dependency.

This is host parser/registry evidence. It does not claim completed Google login
or guest UI validation; those require the broker/framework integration and a
real account flow.
