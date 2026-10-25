# TextView size units and native measurement

Fix revision `3ec341752382f5cdfd2138d8b606e9b47836df18` makes
`TextView.setTextSize(float)` dispatch through the virtual two-argument method
with SP units. The latter converts all six `TypedValue` units using the view's
resources, synchronizes the retained `TextPaint` and native view in pixels, and
requests layout and invalidation when the size changes. `getTextSize()` reads
the Paint. Button, EditText, CompoundButton, CheckBox and RadioButton forward
their one-argument overrides through this path. Constructor dimensions already
resolved from XML remain pixels, with no second SP conversion or virtual setter
dispatch. A separately retained synchronized size also repairs the native view
when an application changes the exposed Paint before calling the setter.

One signed five-class fixture APK runs on actual native ART with old and fixed
runtimes. Its private Resources and Theme use density 2, scaledDensity 3 and
xdpi 144, without changing the activity's metrics. The old runtime fails exactly
once with `java.lang.AssertionError: text-size SP readback`, before any success
marker, when 7.5 SP should read back as 22.5 pixels. It exits during startup.
The fixed runtime passes each ordered stage and remains alive for the full
35-second observation with no failure markers. Both semantic checks pass again
during qualification.

The fixture covers PX, DP, SP, PT, IN and MM against independent pixel constants;
one-argument virtual dispatch; Paint identity and pixel readback; native measured
width and height growth using unchanged measure specs; layout requests and
invalidation; native repair after an exposed Paint mutation; and all five widget
subclasses. Actual compiled binary XML tests direct 12sp, textAppearance 12sp,
and an 8sp textAppearance overridden by direct 12sp. Each reads 36 pixels and
avoids the subclass's virtual setter during construction. This qualification
covers text sizing and measurement; Maps replay is separate.

The runner reuses qualified349's complete frozen compiler, V/C inputs, assets,
base tar, launcher and other runtime files. Its 644 V input pins match before
and after compilation. The old framework is qualified349; both native SOs come
from the retained sealed Native351 build, whose old SO is qualified332's frozen
baseline and whose new SO contains the text-size bridge change. Only the JAR and
this SO differ between the two guest runtimes. Complete source and DEX comparison
keeps 2073 classes, changes only TextView and the five named widget subclasses,
and leaves the other 2067 classes identical after disassembly. Duplicate provider
application fails without mutation.

Complete artifacts are retained at
`/Users/alex/.local/state/vinix/android/text-size351-2026-10-25`:

| Artifact | SHA-256 |
| --- | --- |
| Baseline349 framework JAR | `95aabc17c85a5cda0d643dfa5ef9e618955d422d960ffb3bbc2db74c86a9c37d` |
| Fixed351 framework JAR | `91c5c7da4f3460fa899ee06134fa1e380643eb176ce3f2fe887769f113fd5428` |
| Baseline332 native SO | `2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b` |
| Fixed351 native SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Same signed fixture APK | `96d09bc024e7c3e369e2b8d8bdbd72031c461821cc762cad0d775de6fddbd2d4` |
| Executed checked runner | `3a105997f7c3be058d102a07ed1a6b49422fd35ce731ff3bf9b9693ef8a8784d` |
| Executed frozen runner source | `ad85f437e3bc9b19ad5aa9d096793cc4b6d60d8d373fc518b04fb6563d8b0ce0` |
| Old raw serial | `302b03e94400f774e49919e23aa260a80fb1e7ef6de34da6ac8cdeffb2fc0a7e` |
| Fixed raw serial | `80114f2c75f934ebf59cb5058a224d1a741fdb0ba6c880d14ba964ba31815337` |

The complete bundle contains 10,336 files. Its `sha256.json` manifest SHA-256 is
`c11c55d6204acc7af998e5e52fcc8c66e8af698b61d01928483005f59fd47654`.
The retained qualified349 manifest is
`0700318453dfb6373ea07587c3f42b09fbdb65930dffd35eda0664deddde8f88`.
The complete Native351 build is also retained under `native-build/`, with manifest
`eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9`.
Independent own and root complete readbacks passed all 10,336 file hashes and
the exact file set. Their adjacent receipts are
`text-size351-own-readback-2026-10-25.json` and
`text-size351-root-readback-2026-10-25.json`.
