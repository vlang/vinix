# Service lifecycle and terminal observer stage

Validated source snapshots over base revision
`63bf5f005ff5f0dea01ec5c9c60f24bea0f7190d` are retained at
`/Users/alex/.local/state/vinix/android/maps-service-lifecycle-stage-build-2026-10-29-r1`.
`completed-tool-inputs.sha256` records the exact sources and final tools.
The native observer is commit `fc0c44be9`; its limits and numeric markers are
documented in [service-terminal-observer.md](service-terminal-observer.md).

The explicit stage/kernel profile preserves the sealed Binder image
`5140b0afe5ced3c5a17f8566547cd23941d46ae228b75f2ed5ee3ba5cb4f2854`.
It adds one seven-file overlay: JAR, DEX, native DSO, three framework/headless
receipts and the Maps deployment receipt. Exactly 53 complete dependency seals,
six deployment input changes, three deployment top-level changes, 25 inherited
modules and 26 final modules are required. First-inode modes and historical
headless launch/native roles remain pinned; only its JAR role changes.

The original native bundle remains verified against its exact Binder framework
and all 68 original raw consumed classes. The new native bundle verifies against
Service framework `9453286e07d3bd727782355413d4fa8059bd1332e89850748fb4db02680c9488`.
Its manifest is `2c61783de1aab68bbf8177329215b27881e95afaa87d16272f03ba7fda98c401`;
its DSO is `ea8b899971ac96335c1f53a32eb3dee8e5e8f87600c0bcd5b7edaa683b9a8136`.
All 88 source origins remain present; only `nativews/headless.v` changes.
JNI, bindings, exports and builder source remain exact. The complete helper
closure permits only the one-line Service registration and added Service provider;
the native-generator closure remains unchanged. Actual enumeration confirms these two changes.

The old canonical post-DEX inventory equals the successor pre-DEX inventory.
Both complete 2,104-class trees are checked; only Service's three callbacks change.
All 68 native-consumed canonical classes remain byte-identical. The broker-context
raw representation changes from `90fddf01…` to `96f550a8…`, matching canonical
disassembly. This difference is explicitly pinned and reported; no text is normalized
and successor raw equality is not claimed.

Stager compilation, self-test, helper enumeration, complete input audit and all
historical/new kernel-profile self-tests passed. Independent filled-pin review passed.
Original check limits remained 600 MiB aggregate RSS, 300 seconds, 512 MiB observed
shared-volume growth and 1 GiB reserve. The one-shot patcher compile exceeded the
RSS guard at 641,236,992 B; its exit-125/child-137 receipt and complete cleanup are retained.
The supported V `-generate-c-project` path then separated generation from C compilation,
without editing generated C or changing the emitted `-O3`/`-flto` flags.
Generation used 416,137,216 B sampled RSS and C compilation 335,527,936 B.
The generation sampler missed a transient: `/usr/bin/time -l` recorded
659,423,232 B maximum RSS (628.9 MiB), above the nominal 600 MiB limit despite
the guard's passing sampled result. Strict generation-peak compliance is therefore
not established by R1. The C compile's time-reported maximum was 325,337,088 B;
the stager compile's was 549,601,280 B. No resource limit was raised.
Final self-tests passed in 14.541 seconds at 43,171,840 B sampled RSS.
All successful compile phases recorded zero swaps. C sources, include inputs,
emitted command/Makefile and compiler identity are retained; an absent optional
LegacySupport include directory is recorded with its original flag unchanged.

The complete one-root, 591-entry evidence seal and independent fresh-process
readback passed under unchanged 600 MiB/900-second/64 MiB growth/1 GiB reserve limits:
`/Users/alex/.local/state/vinix/android/maps-service-lifecycle-stage-sealed-2026-10-29-r1/sealed/manifest.json`,
SHA-256 `ef82a800e18549ea38c2267343ae7a0c75bac2b316ef7a6cd1c2b33245d6a506`.
These roots are closed.

The fresh serial qualification at
`/Users/alex/.local/state/vinix/android/maps-service-lifecycle-patcher-serial-2026-10-29-r1`
adds only V's supported `-no-parallel` frontend option. Generated C differs in
fixed-string typedef declaration ordering; its raw diff is retained without
normalization. The emitted production flags remain unchanged. Relevant C sources
and include directories compare exactly to the original retained inputs.
A fresh C compile and all historical/new self-tests passed independently.
Time-reported maxima were 361,644,032 B (generation), 326,221,824 B (C compile),
and 37,142,528 B (self-test), all below 600 MiB, with zero swaps. Sampled peaks
were 332,939,264 B, 341,229,568 B and 45,580,288 B. Resource limits stayed unchanged.
The fresh binary happens to be byte-identical to R1; its proof was not reused.
R1's complete 591-entry readback passed again, confirming it stayed unchanged.

Serial qualification seal and fresh-process readback passed: one root, 20 entries,
`/Users/alex/.local/state/vinix/android/maps-service-lifecycle-patcher-serial-sealed-2026-10-29-r1/sealed/manifest.json`,
SHA-256 `7b7f706af2271fe962d61276fad37a8cd4b7922bac83b653f38ad3e2373dfcf5`.
Both serial qualification roots are closed; the same original seal/readback limits apply.

Final tools below the build root:

- `tools/maps-service-lifecycle-stage`: `dc26639be7683f0ba0450d0ae38e06708b78378013a1236b56433faf80f6ba38`
- Final patcher: `/Users/alex/.local/state/vinix/android/maps-service-lifecycle-patcher-serial-2026-10-29-r1/project/patch-kernel`, `0374c3757e0a386819a7336f7b28f09085a237b881e6911bf917fafe311f31ae`

Use `maps-service-lifecycle-stage --prepare FRESH_EXTERNAL_OUTPUT`, then clone the
complete sealed image before `patch-kernel --maps-service-lifecycle FRESH_CLONE
FROZEN_KERNEL_BUILD BUILD_JSON_SHA256`. Keep the original preparation/clone/kernel
600 MiB/900-second/4 GiB growth plus 1 GiB reserve guards and 8 GiB file-size limit.
This validation task prepared no image or VM. ART/Maps execution, the earlier exit's
sole cause, successful sign-in and tile rendering require separate runtime evidence.
