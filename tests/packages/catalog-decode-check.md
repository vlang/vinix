# Bounded pinned catalog decoding

Pinned catalog locks now use bounded stored-metadata primitives after their
existing schema scan. `decode_catalog_recipe` returns an independently owned
envelope, architecture list and complete import records. Each import owns its
source, recipe selectors and nested manifest. `close_decoded_catalog` retires the
result; partial import/selector/manifest failures retire their storage.

The baseline probe extracts the previous `catalog_recipe` JSON/schema admission
before normalization, using the same original decoder, scanner and cleanup. After
retiring returned values/errors, ten warmed reads retained **10 bytes for one
import**, **363,640 bytes for 64 imports**, and **7,030 bytes for truncated-input
refusals**. The same three probes retain zero with bounded decoding. Original
publisher sources, probe source, executables, generated C and output are pinned.
No compiler, allocator or standard-library change is involved.

Catalog format, architectures, import sources/recipes, recipe format/manifest/
entries and complete manifest/dependency/payload fields remain required. Only
legacy `window_protocol` is optional at zero. The shared prepared-root reader
keeps a distinct template mode, retaining omitted format and manifest defaults.
Templates with omitted nested fields cannot enter pinned catalog locks. Whitespace
and escaped valid keys produce unchanged canonical writer bytes.

Admission bounds are 8 MiB, two 16-byte architecture strings, 4,096 imports and
1,024-byte import sources, with 1,024 selectors and the existing manifest field/
count bounds per import. Limits apply while decoding. Unknown/escaped duplicate
keys, missing declarations, null/type errors, invalid UTF-8/Unicode escapes,
noncanonical/overflowing numbers, incomplete JSON and trailing data refuse.
Bounded-reader diagnostics replace generic decoder messages.

Typed admission remains separate from catalog normalization and semantic checks.
`catalog_recipe` still checks supported/distinct architectures, source paths,
manifest and selector validity, duplicate identities, target coverage and complete
dependency closures before any workspace is created. It keeps canonical ordering,
license/firmware disclosures and release bytes. Structural decode fixtures may
repeat identities to exercise collection bounds; construction still refuses them.

Both metadata architectures qualify one and 64 imports over 1,000 tracked
read/retire cycles, including independent results, retired input buffers and exact
writer reproduction. Legacy/default separation, every truncated prefix and 26
refusal categories retire their storage; each refusal category runs 1,000 tracked
cycles. Late failures exercise cleanup after earlier imports and selector fields
were admitted. A full 1,024-selector import requires zero retained bytes.

The 4,096-import and 16,384-payload cases exceed the allocation tracker's
16,384-live-record table, so they run once with one live owner outside tracking.
Streamed fixtures run natively, under ASan/UBSan and in fresh guest workers.
Ordinary functional one/64-import and refusal runners use 64 cycles. Exact
8 MiB and limit-minus-one pass; one byte over and each nested overflow refuse.
The sanitizer run uses those functional cycles; native allocation tracking
qualifies the separate 1,000-cycle lifetime checks.

Invalid catalog input preserves source bytes, existing workspaces and absent
pack/composition destinations. Restored complete and explicit-zero legacy
protocol locks publish identical canonical catalog bytes. Regressions cover
prepared-root defaults/admission, all three fixed profiles, signed release,
catalog construction/composition, installation/removal and signed CLI behavior.
Dedicated guests run all decoder groups, publisher-schema, catalog and
composition fixtures against copied frozen kernels. Receipts pin the kernel,
init, four fixtures and serial log and require clean QMP shutdown.

The first expanded fixture used a comma after `sdk` when removing it, but the
writer omits zero `window_protocol`, leaving `sdk` last. The unchanged malformed
fixture failed its refusal assertions. Removing the preceding comma and testing
explicit-zero protocol input corrected the fixture; the production reader did
not change. Initial failure output and fixture source remain pinned.
An obsolete sanitizer run with tracking was stopped after the corrected native
checks passed and replaced by the functional sanitizer run; its partial output
is retained and does not count as qualification.

The allocation scope is decoder/schema admission after returned values/errors
are retired. Complete catalog normalization, dependency search, construction,
composition and other publisher lifetimes remain outside this measurement.
Production publisher enrollment, catalog migration, graphical login/display
integration and wider foreign-runtime acceptance remain open for roadmap 14.

## Recorded results, 2026-10-16

All **40 focused compile/run checks** passed: fourteen core pairs, two tracked-allocation pairs, one ASan/UBSan pair, four signed CLI/driver checks and two guest-tool builds.

Fresh QEMU TCG guests passed with clean shutdown and seven verified artifact hashes each: AArch64 **85.0 seconds**, x86_64 **195.9 seconds**. Deadlines qualify functionality, not performance.

- [before/after catalog probe](results/2026-10-16/catalog-decode-baseline.txt)
- [host results](results/2026-10-16/catalog-decode-host.json)
- [host summary](results/2026-10-16/catalog-decode-host.txt)
- [core assertions](results/2026-10-16/catalog-decode-core.txt)
- [tracked catalogs and templates](results/2026-10-16/catalog-decode-memory.txt)
- [sanitizers](results/2026-10-16/catalog-decode-asan.txt)
- [signed CLI](results/2026-10-16/catalog-decode-cli.txt)
- [initial fixture assertions](results/2026-10-16/catalog-decode-attempts.txt)
- [source/toolchain/artifact ledger](results/2026-10-16/catalog-decode-toolchain.json)
- [aarch64 receipt](results/2026-10-16/catalog-decode-aarch64.json)
- [aarch64 report](results/2026-10-16/catalog-decode-aarch64.txt)
- [aarch64 serial](results/2026-10-16/catalog-decode-aarch64.serial.txt)
- [aarch64 QMP](results/2026-10-16/catalog-decode-aarch64.qmp.txt)
- [x86_64 receipt](results/2026-10-16/catalog-decode-x86_64.json)
- [x86_64 report](results/2026-10-16/catalog-decode-x86_64.txt)
- [x86_64 serial](results/2026-10-16/catalog-decode-x86_64.serial.txt)
- [x86_64 QMP](results/2026-10-16/catalog-decode-x86_64.qmp.txt)
