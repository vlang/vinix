# ImageView maximum dimensions, 2026-10-30

Google account layout inflation reached `gjgi.<init>` and failed because
`ImageView.getMaxHeight()` was missing. Its result supplies the header layout
height, so an arbitrary getter result would not preserve the layout's input.

The provider adds private maximum width/height state, initializes both to
`Integer.MAX_VALUE`, reads the existing styled `maxWidth`/`maxHeight` dimensions,
and exposes the two getters. Existing setters retain the exact signed argument.
Constructor XML initialization calls the setters virtually, width then height.
This follows the checked [AOSP ImageView implementation](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/widget/ImageView.java),
blob `f292c610f842a659e79599e80cf3bd1d455e40ad`: maximum setters store values without
requesting layout. Native measurement and `adjustViewBounds` remain unchanged.

Validation used working sources over revision
`729816525b1e44a4e3211fdc05083e2d1e744912`. The complete host controls and both
failed/final source-check attempts are retained at
`/Users/alex/.local/state/vinix/android/image-bounds-source-checks-2026-10-30-r1`.
The first source run intentionally refused the unfilled constructor checksum;
the final run pins the complete normalized retained constructor and passes.

The isolated production-provider checker verifies exactly three changed methods,
two added getters and two fields, with every other member and class metadata
preserved. Fourteen malformed or repeated inputs fail without modifying the
input. Baseline/patched API-28 DEX assembly and roundtrip preserve all unrelated
methods and the three native declarations. Independent review checked register
allocation, constructor callbacks, initialization order and fixture coverage.

The signed fixture is retained at
`/Users/alex/.local/state/vinix/android/image-bounds-fixture-2026-10-30-r1`.
It exercises all constructor forms, exact signed setter boundary values,
inheritance, axis/instance isolation, direct XML dimensions, styles, XML overrides
and `defStyleRes`. Subclass sentinels verify initialized defaults, virtual setter
order/count and absence of a layout request from the maximum setters. Both
fixture classes pass canonical DEX roundtrip, and the APK passes v3 signature,
package and launch-activity checks. Guest execution remains pending.

| Check | Seconds | Sampled RSS bytes | Time maximum bytes |
| --- | ---: | ---: | ---: |
| Checker compile | 3.826 | 323977216 | 343048192 |
| Final provider/source/DEX check | 16.494 | 247840768 | 185843712 |
| Fixture generator compile | 4.380 | 316637184 | 340475904 |
| Signed fixture production | 13.071 | 103333888 | 97910784 |

Each guard and child exited zero with complete cleanup, under 600 MiB aggregate
RSS, 300 seconds, 512 MiB observed growth and 1 GiB reserve. Time reports record
zero swaps. These are host checks and do not establish a Google login form,
authentication, map imagery or maximum-dimension measurement behavior.

| Artifact | SHA-256 |
| --- | --- |
| Provider source | `225b41a530a4f3bf1d7d627ecc7adfae67bb62e11823405d0abba92292943f46` |
| Final source receipt | `3ec84fcb0fcfbb1dbefa1321022d37e1e6ece8904651569670f7c535ed7024d4` |
| Fixture generator source | `5ac00bd62ee3000d3d5754f5916eb8f655659fb82174d294fd16f13f2a5a179a` |
| Fixture `build.json` | `8ba3fb8080b520eac644281cefeb3d30fba9f8d7070d827c0df66da7a6fb2fb2` |
| Signed `probe.apk` | `7d11a0e6d71b6c556a57f84fd5f27610157f0a49735282f0bb31aaac0ff00a62` |

The fixture marker is
`IMAGE-BOUNDS-PASS defaults setters axis-isolation instance-isolation styled-dimensions`.
Retain both complete external roots; these receipt pins do not replace them.
