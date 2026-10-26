# Maps r5 evidence memory validation

The macOS streaming sealer built successfully with V `-new-compiler -prod
-gc boehm -nocache`. It replaces the full-tree manifest allocation for this new
audit, without changing historical checkers or permitting missing evidence.
The source base was `8fa48d6081fbc1fa95e3e335b0c1e04bf288bc97`; `main.v` SHA-256 is
`148932aee91df125c2fe56f1631b4c89275868232498c6b92c3530f5415b3a6c`.

Mutation tests passed for bytes, modes, symlinks, missing/extra entries, output
bytes/extras, manifest mode/pin, empty directories, special objects and
overlapping roots/output. A 64 MiB sparse file matched an independent streaming
digest. Self-test peak RSS was 12,369,920 bytes.

The stopped r5/r5-retry1 run was sealed across 64 roots and 4,426 typed entries,
including both VM trees, final collection, clone/build/runner receipts and
startup screenshots. The seal's internal full check and a separate check passed.
`/usr/bin/time -l` measured peak RSS of 19,103,744 bytes for sealing and
22,052,864 bytes for the separate check, below the 512 MiB acceptance bound.
These are measured results for this root list, not a universal memory ceiling.

External state is `/Users/alex/.local/state/vinix/android/`:

- `maps-account-r5-runtime-sealed-2026-10-27-r1`: complete streamed inventories;
  manifest SHA-256
  `f7da25f9394998d280ffbeeb92d774d225cf4984526a4968b926810f5030831b`.
- `maps-account-r5-stream-plan-2026-10-27-r1`: root list, producer references,
  quiescence guard, exact driver/sealer, build and self-test receipts.
- `maps-account-r5-stream-execution.json`: execution/log/metric pins; SHA-256
  `32fc4fb08522f52d9760fee3031439fb37f6f1ed53aa65aa47e450c873452f0a`.

The seal contains 1,353,410 regular-file bytes and the plan 825,867 bytes.
Images and SDKs were read in place; none were copied. Producer manifests remain
pinned references to the original complete bundles, which their unchanged
historical checkers still require. The sealer uses 1 MiB native SHA buffers and
bounded directory enumeration; it never reads an entire image into memory.

The separately reviewed daemon runner closure is retained at
`maps-account-daemon-runner-closure-2026-10-27`, with complete 20-file manifest
SHA-256 `711c05cc23e68cf81039e37ea0d3d5a92fb52bed8ab083cedaef79cf6153de2f`.
Its used and rebuilt runner bytes match. Compiler/SDK/system-library closure
is explicitly non-hermetic.

This inventory establishes integrity on a quiescent trusted host. It establishes
neither Google authentication nor the cause of the earlier r5 host exit, and
does not qualify deletion of any original bundle. No VM signals were sent by
the sealing driver.
