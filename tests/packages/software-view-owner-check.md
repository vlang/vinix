# Owned Software catalog observations

`pkgcore.software_view(root, offline)` now returns independently owned headers,
rows, permissions and installed dependency requirements. Call `.close()` after
use; closing the same owner twice is harmless. A response survives retirement of
the source configuration/catalog/state and closing a sibling response. Caller-built
values can borrow metadata and keep their existing caller-managed lifetime.

The reader retires its decoded configuration, authenticated catalog and active
state, including refusal paths. Projection retires maps, sorted IDs, resolver
containers, policy errors and temporary diagnostics. Returned rows clone their
projected strings and nested arrays; diagnostics have one owner. Row limits,
ordering, installed-versus-preview facts and serialized fields are unchanged.
The CLI closes view/search/info/updates responses after use and retains error
text independently of a closing response.

The [core tests](../../tools/packages/pkgcore/view_test.v) verify both metadata
architectures and independent response/source lifetimes. Measured projection
frames cover 1,000 calls each for update, unresolved, revoked, denied, fresh and
65-row cases, plus sixteen 4,097-row refusals. Public reader frames cover 1,000
fresh, malformed-catalog, malformed-configuration and busy-lock calls, and 128
authenticated cached-index reads. Every measured frame must retain zero tracked
bytes. Authentication and installed fields remain checked after source/sibling
retirement; configuration, generation bytes, activation and object inventory
remain unchanged. Fresh reads never initialize package state.

An initial projection check found four retained bytes per call in a cloned map
iteration key. The key is now explicitly retired, and all final measured
projection cases pass. This check measures the complete projection and public
catalog-read boundaries; it does not claim allocation freedom for arbitrary
CLI formatting, publisher operations or all package-service methods.

The [host driver](software-view-owner-check.v) runs tracked core, protocol and
complete headless Software checks normally and under ASan/UBSan, plus the signed
[CLI maintenance suite](distribution-cli.v) against normal and sanitized tools.
Use a reviewed V compiler and staged headless ui2 module:

```sh
v -nocache -o /tmp/software-view-owner tests/packages/software-view-owner-check.v
V=/path/to/reviewed/v VINIX_PACKAGE_TEST_UI2=/path/to/modules \
  /tmp/software-view-owner /build/new-software-view-owner
```

The shared [native controller](software-provenance-runtime-check.v) enables the
tracked core checks on both targets. These checks qualify service/protocol and
host UI-tree lifetimes. Production catalog migration, graphical-session
integration and broader runtime/device acceptance remain open in roadmap 14.

## Recorded results, 2026-10-18

All **21 host checks passed**, including tracked core checks and ASan/UBSan,
the full Software fixture and its catalog/details allocation modes, and signed
CLI maintenance against normal and sanitized executables. Core projection and
public read measurements retained zero tracked bytes in every documented frame.
UI catalog/details measurements each retained zero tracked bytes across 1,000
cycles. Sanitizer leak detection was disabled; allocation claims apply to the
explicit tracked frames, not the entire CLI or test process.

Both native guests passed with tracking enabled: **aarch64 77.9 s** and
**x86_64 86.6 s**. These runs reused pinned prebuilt kernels and the V plain-USTAR
adapter for the older x86_64 boot-media contract. Both complete desktop
architecture typechecks passed with headless ui2 and staged generated
Calculator/translation sources. These qualify types and UI trees rather than
graphical presentation. The compiler is frozen V 0.5.2 `826e96f`, with fallback
and automatic compiler-error reporting disabled.

The [host receipt](results/2026-10-18/software-view-owner-host.json),
[summary](results/2026-10-18/software-view-owner-host.txt) and
[ledger](results/2026-10-18/software-view-owner-ledger.json) retain exact commands
and source/compiler/artifact hashes. Native
[aarch64](results/2026-10-18/software-view-owner-aarch64.txt) and
[x86_64](results/2026-10-18/software-view-owner-x86_64.txt) reports accompany the
raw serial logs. The [retainer](software-view-owner-retain.v) verifies local
inputs and evidence with `--verify` while those files remain available.

## Installed-name search, 2026-10-26

Search now includes the retained installed name alongside the candidate name,
ID and description. A renamed update remains discoverable using its installed
name in All, Installed and Updates. The fixture also checks Unicode folding,
available-name lookalikes, omitted legacy installed metadata, repeated filtering
and compact/full browser resizing without starting package work.

Source revision `ec8638f10c62e67892749ec51208613f3af6f89a` passed focused normal,
production and ASan/UBSan host runs, the historical full normal Software fixture,
and a production control that correctly refuses the original implementation.
The complete evidence directory is
`/Users/alex/Library/Caches/vinix-codex/section14/software-installed-name-20261026-03`.
Its `result.json` SHA-256 is
`66e9c52db6705018376c467786c14155d32c78e63e82745a37d0b41de8f23127`;
the artifact inventory SHA-256 is
`670021ba5e8d8559074482dbc4179e667f5be3c06ad02ffeafc8cc582b653a2c`.
Earlier failed fixture attempts remain separately retained. These are host
UI-tree checks without measured allocation or guest-presentation claims.
Project/UI sources and V/Clang executables are pinned; imported compiler-library,
header, linker and transitive tool inputs are not fully frozen.
