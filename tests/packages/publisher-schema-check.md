# Publisher recipe schema qualification

Prepared-root templates, pinned catalogs and catalog composition now enforce
strict JSON types, decoded key uniqueness and known fields. Catalog envelopes,
imports, recipes, selectors and manifest/dependency/payload records require every
declaration. The legacy omitted `window_protocol` still means zero. Templates
retain their documented manifest defaults and optional format-1 default.

The baseline reproducer accepts `"permissions": null` in a catalog and silently
normalizes it to an empty permission list. Catalog admission now rejects it;
duplicate and unknown fields in prepared-root recipes also fail before source
access or workspace creation. Rejected fully decoded records retire their owned
package, selector and architecture buffers. Required-field checks replace the
previous second partial JSON decode.

`tools/packages/pkgcore/publisher_schema_test.v` covers:

- Every required field at all seven catalog record levels, plus null collections,
  wrong scalar types, numeric bounds and nested/escaped duplicate or unknown keys.
- Unchanged canonical output for complete locks, escaped field names, whitespace
  and omitted/explicit-zero native window protocols.
- Prepared-root template defaults, rejection before any workspace appears, an
  unchanged source, and a successful retry after restoring valid input.
- Preserved existing publisher workspaces and absent composition output on
  invalid input, with no staging directory after refusal.
- Ownership of key sets and required-field lists across 1,000 prevalidated valid,
  null, missing, unknown and duplicate scanner cycles for both schemas.

The allocation fixture measures schema scanning, excluding generic typed JSON
failures and full publisher lifetimes. These checks qualify metadata admission
and publisher filesystem behavior; release key enrollment, upstream payload
authentication, application migration and graphical/runtime qualification remain
separate work.

```sh
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused -gc none -manualfree \
  -o /tmp/publisher-schema tools/packages/pkgcore/publisher_schema_test.v
/tmp/publisher-schema
V_MACOS_V3_NO_FALLBACK=1 /path/to/v -no-skip-unused -gc none -manualfree \
  -d track_heap -o /tmp/publisher-schema-memory tools/packages/pkgcore/publisher_schema_test.v
/tmp/publisher-schema-memory
```

All nine affected core runners, signed CLI contracts and both sanitizer runners passed. Both recipe scanners retained **zero tracked bytes** over 1,000 cycles. The package service built as a static ELF for AArch64 and x86_64, with target-machine checks. These are build checks; this change adds no new guest-runtime qualification.

- [Host checks and build results](results/2026-10-14/publisher-schema-host.txt).
- [Pre-change regression](results/2026-10-14/publisher-schema-baseline.txt).
- [Source/compiler/artifact ledger](results/2026-10-14/publisher-schema-toolchain.json).
