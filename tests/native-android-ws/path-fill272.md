# Android Path fill rules: attempt 272

Production revision: `e4999db88` (`Android: honor Path fill rules and close filled contours`).
The ARM/JNI fixture passes against framework/native 272 and fails against 270
using the same signed APK. This is a Canvas/Path integration result; Maps was
not launched for this test.

The baseline fails at `Path fill: nested1 pixel=85 actual=-13408615 expected=0`,
the first even-odd hole assertion. The fixed run prints all five markers:
`PATH-FILL-RULES-PASS`, `PATH-CONTOURS-PASS`, `PATH-FILL-STATE-PASS`,
`PATH-FILL-PASS`, and `READY` (each prefixed `BOOTSTRAP-`). It remains alive
for the complete 30-second observation with the native backend ready.
The original classifier remains `startup_failed`, `functional_passed:null`:
its only fixed-run failures are the inherited optional `Lnge;`/`nge`
reflection diagnostics, checked exactly by `path-fill-check.v`.

`path-fill-fixture.v` compares every pixel in 16×16 bitmaps for all four fill
rules, same/opposite winding holes, empty inverse fills, open/multiple contours,
Canvas translation/scaling and open-versus-closed stroke. It also checks Java
fill state and rendered geometry after copy (including source reset), set,
self-set, destination/in-place transform, addPath, reset and rewind; null-copy
and null-fill semantics are asserted.

The frozen inputs are 270's 125 framework sources and 83 native sources. Only
`framework_paths`, `ws_draw_path`, and the single `native_drawPath` binding/JNI
wrapper change; the native call is `native_drawPath(JJJI)V`. Concurrent graphics
and bitmap changes are excluded. Six successful compile/build receipts retain
the actual commands and output hashes. The semantic checker also binds raw
rows, serial and screenshots, and proves equality of 84 staged runtime entries
outside the two framework/native overlays. Its seven negative cases pass.

Artifact SHA-256:

| Artifact | SHA-256 |
| --- | --- |
| Framework JAR | `305f04316f617fa26ca84d74d8a1693f90a0a3ffdada0936f9bb18d3cc5a5f75` |
| ARM native library | `6e92d8d95ae6b0cddf082f34ed33209bf6d49e04463b3af8354b12bb1bf80989` |
| Same signed APK | `6bf5727f53f9d14d2bb67d7f282598890437a79b2ef71d874fde13117d078f4b` |

Retained evidence under `/Users/alex/.local/state/vinix/android/`:

- `compound272-2026-10-24/`: frozen sources/tool closure, build receipts,
  independent prelaunch and completed first attempt. Both initial boots failed
  before APK startup because the APFS provider staging nested the EGL directory.
  These failures remain intact; they provide no JNI pass evidence.
- `compound272-staging2-2026-10-24/`: fresh private-media retry, the exact
  one-expression provider-destination repair, compile/launch receipts and
  independent completed pair. The framework/native/APK bytes are unchanged.
- `path-fill-host272-final-2026-10-24/`: actual production rasterizer host/ASAN
  tests, all six markers passing against the pure frozen 272 native closure.
  `evidence-sha256.txt` SHA-256:
  `77fa261b005f852ed275a859f1a4087ddcb4728e89ca7cc3b73ab9b2258bf753`.

`path-staging-test.v` exercises the maintained APFS transformer against V's
original provider-copy semantics, including symlinks, spaces, existing files,
error paths and rejection of the old nesting bug. A separate comparison of the
actual EGL/Vulkan providers proves identical 22-file inventories and bytes.
The original classifier and observation flow are unchanged.

Completed-tree inventory SHA-256:

| Inventory | SHA-256 |
| --- | --- |
| Initial failed attempt, `compound272-2026-10-24/completed-sha256.json` | `983f22122a7ed3d843d3758d0912d2f90c286b1a962f1d2fd556c75d97b3e31c` |
| Successful retry, `compound272-staging2-2026-10-24/retained-sha256.json` | `9612f3ca63310caa5b057c85352ed96f2c1406f172b538403772a6a431f1a246` |
| Final checker supplement, `compound272-staging2-2026-10-24/final-small-seal.json` | `af095847753410e8d3d55b6c35211b5e86f5a2bf098dcccd9cf647d82c16974a` |

The frozen checker passes against the independent completed trees. Its retained
`checker/runtime-check.json` SHA-256 is
`ffc1f384abb0eb7cb32a97c3d019e7f1bc6cefb4da566169106a37ba1c37c21b`.
The final supplement binds the checker source/binary, compile/run receipts,
negative tests, result and earlier inventory hashes without repeating media hashes.

Recheck the retained pair with an assertion-enabled build of `path-fill-check.v`:

```sh
path-fill-check \
  /Users/alex/.local/state/vinix/android/compound272-staging2-2026-10-24/completed \
  /Users/alex/.local/state/vinix/android/compound272-2026-10-24/completed \
  /Users/alex/.local/state/vinix/android/compound272-staging2-2026-10-24 \
  /tmp/path272-check.json
```

This semantic check does not re-audit firmware media or the complete source/tool
archive. The independent retained inventories cover those evidence bytes.
