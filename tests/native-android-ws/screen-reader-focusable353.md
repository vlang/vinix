# View screen reader focus state

Fix revision `2ee9c8d64dcb5fd9c93a1e4c3625606011c9cd47` adds
`View.setScreenReaderFocusable(boolean)` and `isScreenReaderFocusable()` with
independent per-view state, initially false. The public `screenReaderFocusable`
attribute uses ID `0x01010574`. Constructors resolve compiled XML, theme and
default styles, calling the virtual setter once when the attribute is present
and skipping it when absent. The TypedArray is recycled on success or failure.
This property leaves keyboard focus unchanged. Accessibility node and service
delivery are outside this change.

One signed four-class fixture APK runs on actual native ART with the old and
fixed frameworks. The old runtime rejects the isolated initial setter call
exactly once with `java.lang.NoSuchMethodError: No virtual method
setScreenReaderFocusable(Z)V in class Landroid/view/View; or its super classes`,
before any success marker, and exits during startup. The fixed runtime passes
every ordered stage and remains alive for the full 35-second observation with
no failure markers. Both semantic checks pass again during qualification.

The fixture checks all four public constructors' default false state, toggles,
repeated sets, independent state across three views and independence from the
boolean keyboard-focus setter. Compiled binary XML covers absent attributes,
true/false literals, boolean resource references and styles. Theme and both
default-style arguments exercise precedence, including XML overriding a theme.
A subclass records constructor virtual setter calls, proving present-only
dispatch. This qualification covers the framework property; Maps replay is
separate.

The runner reuses qualified351's complete frozen compiler, V/C inputs, assets,
base tar, launcher and native runtime. Its frozen V closure adds only the new
provider and fixture; all other inputs match the retained baseline, with the
registry's one added call checked exactly. The same APK and all runtime files
except the framework JAR are identical between the two guests. Complete source
and DEX comparison retains 2073 classes, changes only View and public R$attr,
and leaves the other 2071 disassembled classes identical. Duplicate provider
application fails without mutation.

Complete artifacts are retained at
`/Users/alex/.local/state/vinix/android/screen-reader-focusable353-2026-10-25`:

| Artifact | SHA-256 |
| --- | --- |
| Baseline351 framework JAR | `91c5c7da4f3460fa899ee06134fa1e380643eb176ce3f2fe887769f113fd5428` |
| Fixed353 framework JAR | `1e5467f57ac9a3a51a9f29f7c73bf4896b47dc1ea055f59d07db1e1d281cfa83` |
| Unchanged Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Same signed fixture APK | `ab4202d808bb285d6fb080a90d6e2a109a83cc26aa77b390be3054e81245608d` |
| Executed checked runner | `fb6bd0aa7ffcfe1c2a94ab2ee0b8003164e3bdf951c82ceb322d6203d28ee10f` |
| Executed frozen runner source | `f83101eeb7c86c3e8dbc299291d7154a38f7631566ed72ba3506981887385813` |
| Old raw serial | `bacca680fec8a9a4e607c695efc754ed43937680ecbd6e2033ac34ad56688131` |
| Fixed raw serial | `476d29f6d39f68b0150b2cffb80b3d3c9c51119199d4f29f1cc0f03337b96517` |

The complete bundle contains 7,938 files. Its `sha256.json` manifest SHA-256 is
`22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f`.
The retained qualified351 manifest is
`c11c55d6204acc7af998e5e52fcc8c66e8af698b61d01928483005f59fd47654`.
Own, root and independent peer complete readbacks passed every file hash and
the exact file set. Their adjacent receipts are
`screen-reader-focusable353-own-readback-2026-10-25.json`,
`screen-reader-focusable353-root-readback-2026-10-25.json` and
`screen-reader-focusable353-contract-readback-2026-10-25.json`.

A complete APFS clone is retained for the replay wrapper at
`/Users/alex/.local/state/vinix/android/screen-reader-focusable353-framework-build-2026-10-25`.
It preserves the same manifest and all 7,938 files. Fresh own and independent
peer complete readbacks also passed this clone, with adjacent receipts
`screen-reader-focusable353-framework-build-own-readback-2026-10-25.json` and
`screen-reader-focusable353-framework-build-contract-readback-2026-10-25.json`.
