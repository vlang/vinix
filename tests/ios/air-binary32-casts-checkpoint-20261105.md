# Numeric binary32 conversions checkpoint — 2026-11-05

`90ef1b1b1fd79694175c930a075e6495fc3c65ab` adds flag-free `uitofp`, `sitofp`,
`fptoui` and `fptosi` between binary32 and every i1..i64 width. Fortnite remains
at **4/8 observed launch gates**, last seen at the
[GPU requirements alert](controller-discovery-checkpoint-20261104.md). No game
frame, menu, login or playable match is verified. The gate count is not an
engineering completion percentage.

Integer-to-float uses unsigned magnitudes and software nearest/ties-to-even
rounding. Float-to-integer truncates toward zero before range checks; NaNs,
infinities and out-of-range results produce poison. Fractional negative values
near zero can convert to unsigned zero, and signed i8 -128.5 becomes -128.
Poison operands propagate; selected undef and nonzero conversion flags reject.
There is no host FP cast, new execution array or LLVM dependency in production.
Valid IR/matching immutable indexes remain preconditions; the integer-only API
and existing budget/ownership contract remain unchanged. See
[BINARY32-CASTS.md](../../compat/ios/airbitcode/BINARY32-CASTS.md).

Normal and ASan/UBSan conversion units pass 22 exact integer-to-float patterns,
34 float-to-integer patterns, width guards and **262,140 exhaustive exact
signed/unsigned i1..i16 round trips**. Mixed interpreter units pass ten groups,
including result kinds/widths/steps, range and operand poison, undef and flags.
Existing 1,397,052 narrow integer flag comparisons and 28 i64 limits also pass.

Both normal and sanitized runs pass **1,064,960 defined-reference comparisons**:

| Integer widths | Comparisons | Defined values | Poison tags |
| --- | ---: | ---: | ---: |
| 1–16 | 266,240 | 201,012 | 65,228 |
| 17–32 | 266,240 | 207,219 | 59,021 |
| 33–48 | 266,240 | 214,048 | 52,192 |
| 49–64 | 266,240 | 220,763 | 45,477 |
| Total | **1,064,960** | **843,042** | **221,918** |

Vinix executes 256 original cast functions with 4,160 edge/boundary/mixed-bit
inputs each. Native integer-to-float references use ordinary LLVM casts, which
are defined for all inputs. Float-to-integer values use defined saturating i64
intrinsics and masking; an independent poison reference truncates in floating
point first, then checks exact power-of-two bounds and NaNs. This avoids imprecisely
rounded integer bounds and preserves valid fractional boundary cases. No
potentially invalid ordinary native float-to-integer function is called. Vinix
does not execute the reference's intrinsics. Exact defined bits, poison, kinds,
widths and steps compare. All 24 corrupted-result controls reject, including
lost poison tags. Two distinguishing upward/downward rounding controls retain
software RNE results; native calls use only the default environment.

Sanitized regressions pass all 517,120 float comparisons (4,257 arithmetic
NaN-class cases; all others bit-exact) and 17,280 integer comparisons with their
controls. The old unsupported numeric-cast guard now checks unsupported precision
conversion. Arithmetic rounding controls now distinguish RNE in both host modes.
Original historical source/evidence remain archived. LLVM/native machine code
is not sanitizer-instrumented. Leak detection is disabled; leaks were not measured.

The mixed unit program cross-compiles and links as a static little-endian
AArch64 Linux ELF and passes header inspection. It has not run in a guest.
No native AIR corpus scan, AIR shader, iOS app, GPU work or new Fortnite probe
ran. The [default Metal device](../../compat/ios/runner/metal_device.c.v) still
returns nil. Vectors, precision conversion, memory, intrinsics, resources,
pipelines, command submission and presentation remain unfinished.

Complete evidence is retained outside Git at:

`/Users/alex/Library/Caches/vinix-ios/air-binary32-casts-validation-20261105-r1/`

All retained builds/runs use the committed implementation and have empty build
diagnostic logs. The bundle contains source, generated IR/bitcode, assembler
status, JIT/fenv identity, every comparison, binaries, target C, logs, installed
identities and reproduction notes. Compiler/SDK/fenv/LLVM/JIT/sanitizer dependency
closures are not sealed.

The unchanged complete inventory checker passes. A fresh full restore under
`air-binary32-casts-restoration-20261105-r1/` matches every recorded path, byte,
size, type and permission. Restored units and sanitized conversion reference
pass again, including all comparisons and controls. Sibling logs preserve the
receipts. Installed identities and archive/inventory hashes pass recheck.

| Artifact beside/inside the bundle | SHA-256 |
| --- | --- |
| `air-binary32-casts-validation-20261105-r1.inventory.json` | `4a2c383f4c4378ae77a3ca8b0d0eb73113193546b73097a645b27203fc813212` |
| `air-binary32-casts-validation-20261105-r1.tar.zst` | `d0fcabe93d006fab9345ccb023acdef88808bc0e8bfe1cf933ea59c71af37252` |
| `source.tar`, revision `90ef1b1b1` | `02060f5b24b90d2a2609e235c4724a41f4ac4a123826182235964a65173a888f` |
| `scalar-aarch64` | `7a0827ffff45a82f093eac4daf7b01c27d9c73b2c955ac39279a094a899dea06` |

This qualifies the supported numeric scalar conversions only. The prior game
capture and historical auditor rejection are unchanged; no new launch gate is claimed.
