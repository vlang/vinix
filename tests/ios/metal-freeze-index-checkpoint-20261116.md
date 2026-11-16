# Freeze buffer indices checkpoint — 2026-11-16

Source revision: `bcd76779e6599d8e4ebd9ba3fdb8481c5f479f29`.

Pure buffer address expressions accept scalar integer freeze over i1..i64.
Defined values are preserved; poison and direct undef choose zero, matching
ordinary execution. Only direct freeze admits undef, checked before cache lookup
to prevent cached frozen constants escaping into ordinary dependencies. Nested
undef arithmetic/selects remain unsupported. Independently checked GEP roots,
immediate arithmetic errors and the conservative poison-division profile errors
retain their refusals before writes.

The POD freeze node reuses the child/height fields. Shared 256-node/32-level
limits include freezes and their sources, including cached subtrees. Fixed
256-word value and 256-bool poison stack arrays, cache/profile ownership and
free paths remain unchanged. Generated C confirms stack storage. No new owned
per-node or execution allocation is added. Retained heap is unmeasured.

ASan/UBSan checks pass on macOS ARM64:

- 259,200 cases cover i1..i64, nine patterns and both conditions: 74,057 native
  exact outputs, 131,580 explicit zero-choice outputs and 53,563 prewrite
  refusals. Cases include direct poison/undef, wrap promises, oversized shifts,
  samesign conditions, selects and nested freezes. Validation, prepared and
  ordinary execution agree and preserve every output byte on refusal. Native
  words are canonical; interpreter words have noisy padding. Defined native
  targets run only for accepted addresses. A defined LLVM oracle independently
  implements the zero policy; native arbitrary choices are never equated with
  zero. Another 128 native self-XOR properties check stable arbitrary choices.
- Twenty-five controls cover independent roots, one-past/beyond bounds, cold
  blocks and unmaskable division errors. Three unsupported controls check cached,
  nested and unchosen undef use outside direct freeze. Cached freeze chains pass
  at 32 levels and reject at 33.
- Twenty existing core programs pass, including arithmetic/bitwise/division/
  comparison/select address matrices, aliases, casts, graph limits and memory/
  layout/vector/intrinsic checks. The existing scalar freeze suite also passes
  its 459,806 comparisons and controls. Previous unsupported defined/poison freeze
  controls become floating-cast/poison-intrinsic controls; eleven guards remain.
  Historical bundles retain original sources.
- The image shader freezes its selected address. Four image sizes retain exact
  RGBA readback and padding in both hashing modes. Fresh processes of the same
  executable pass nine focused modes per hashing mode: builtins, grids,
  multidimensional grids, computed indices, sizes/images, group coordinates,
  indirect dispatch, geometry types and vector/prepared memory.

Evidence: `/Users/alex/Library/Caches/vinix-ios/freeze-index-20261116-r1`.
Archive: `/Users/alex/Library/Caches/vinix-ios/freeze-index-20261116-r1.tar.gz`.
Complete inventory and archive logical-byte/metadata comparisons pass. Originals
remain retained; no restoration replay is claimed.

- Archive SHA-256: `be3320e574da01b38474660fac5692299b3b3c920373a56a7a678f867fecc040`.
- Inventory SHA-256: `2030555e44fd6a6f2bad7addd538e86e51e9579968203ee08cf1d83c2ceacba1`.
- Source archive SHA-256: `84bcc61f895aac57d9b02200a964e10f7196bd3752dda9eb58fbaf020d3ebb8a`.

The bundle retains complete rows, IR/bitcode, generated C, images, binaries,
commands/logs, tool identities, ownership review and source hashes compared with
the feature commit. Reproduce with `tests/ios/air-memory-freeze-index.v LLVM_AS
FRESH_EXTERNAL_DIR` and `tests/ios/metal-software-checks.v FRESH_EXTERNAL_DIR sizes`,
using repository module paths and retained toolchain. Dependencies remain
referenced; this is not hermetic. LLVM JIT code is uninstrumented and leak
detection is disabled. CPU software Metal only is qualified; no full broad
runtime suite, native GPU, guest launch or new Fortnite frame is verified.

The [LLVM freeze specification](https://llvm.org/docs/LangRef.html#freeze-instruction)
permits an arbitrary fixed choice for poison/undef and preserves defined inputs.
