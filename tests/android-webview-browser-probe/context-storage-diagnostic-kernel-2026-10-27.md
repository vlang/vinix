The kernel patcher adds `--maps-context-storage` for the separate Context storage
framework diagnostic. It requires the exact immutable direct-boot stage and
new credential-storage framework producer, preserves all twelve original
modules, and appends only `maps-context-storage-diagnostic.tar`. Historical
profiles and the frozen PIDFD kernel installation path retain their checks.

The new receipt allows six regular files: runtime JAR/DEX, headless framework
build/manifest/input receipts, and Maps build receipt. It requires five
deployment input changes, a headless JAR-only input change and the restricted
top-level deltas. JAR, DEX, framework manifest and framework-build receipt pins
bind the new producer. Generated headless-input and Maps build receipt digests
remain stager declarations; the complete sealed-stage audit checks their
contents, while the patcher checks their inventory and delta consistency.

Focused negatives cover changed/missing identities, required inputs and module
pins, old/new framework path/seal combinations, cross-profile receipts, missing
or extra deltas and unsafe inventory members. Coherent predecessor headless
receipt and mixed predecessor framework payloads are rejected even when their
delta and inventory agree. The additional FAT fixture covers twelve original
modules and thirteen resulting modules, kernel readback, firmware/configuration
preservation and once-only installation.

Independent read-only source review by `printf_path` passed the new profile,
stable stager contract and focused negatives. Historical profile bodies remain
unchanged; their dispatch, CLI and complete self-test list receive additive
entries only.

The exact entry source SHA256 is
`a5da5ad70232fb067062cf7449bd6c1338072bcad0e426acba287c8e19a9328c`.
Source parent observed after checks was `51cdb49274841e78e7d22f90ef02cc209fc670dc`;
frozen entry/dependency copies and compiler hashes matched before/after.
The Boehm host build passed in 5.50 seconds, maximum RSS 497,958,912 bytes;
the complete self-test passed in 5.42 seconds, maximum RSS 28,393,472 bytes.
Both reported zero swaps. All historical profile/FAT/hash checks and the new
focused profile/overlay negatives passed. Independent final pin review matched
the four new producer files, stager constants and inventory declarations.

Artifacts are external under
`/Users/alex/.local/state/vinix/android/maps-context-storage-kernel-patcher-2026-10-27-r1`.
The tool SHA256 is
`68e758ef51b7a6c6c50e1f53149afd5c135d4108ef23cb05951fc25989cc2567`.
Its adjacent `-seal` audit records one root and eleven entries, manifest SHA256
`b27dacfff72cf50ab80f1ca649718515605eca547de180d43ec3dd700254ed4c`.
Creation's internal check and a separate unchanged checker invocation passed;
the adjacent `-seal.log` and `-check.log` retain their commands' output.

Retain the complete `maps-direct-boot-r1` base,
`combined-account-webview-credential-storage-framework-2026-10-27-r1` producer,
all inherited complete inputs, compiler/standard library/SDK and frozen PIDFD
kernel build. This small source/tool audit does not replace those bundles.

This change runs no VM, copies no SDK and rebuilds no kernel. Google account
sign-in and Maps rendering require separate runtime evidence.
