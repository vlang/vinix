# Animate View translationZ

Source baseline: `edf5cb5cc27ca67e580110e450ce2a0a3a8103ba`.
The old runtime is the sealed [framework336](layout-parent-dispatch336.md) build.

Maps339 reaches the normal Attractions transition and records a failed future
caused by the missing `ViewPropertyAnimator.translationZ(F)` entry, through
`swy.a → oiq.S → nwi.a → nvv.d`. The actual app constructs finite groups of
two or three VPAs and waits for every nonnull Animator end callback before
committing its state. This observation establishes the missing API on that
execution path; the earlier 335 run did not print the exception.

The [provider](../native-android-tools/androidtools/framework_view_property_animator.v)
adds translationZ through the existing translationY PropertyValuesHolder,
automatic scheduling and listener path. View stores translationZ, invalidates
when it changes and returns elevation plus translationZ from getZ. Elevation
itself remains unchanged. The existing animator implementation is retained.

The [runner](vpa-translation-z-run.v) assembles and disassembles the entire
2,068-class framework. Exactly View and ViewPropertyAnimator differ: three
View method bodies, one stored field and the new VPA method. Every existing
VPA method and every other View method remains identical. Reapplying the
provider is rejected before either file changes. The old and new guest
runtime directories differ only in api-impl.jar.

The same signed two-class [fixture](startupfixture/view_property_animator.v)
runs on actual ART. The old framework fails at the first direct translationZ
call with exactly the missing-method error. The fixed framework passes
detached storage, fluent return, elevation/getZ and positive/negative Z
checks. Finite two- and three-VPA groups deliver their start/end callbacks
on the main Looper with nonnull ObjectAnimators, intermediate Z values,
final Y/Z/alpha values and a shared completion countdown shaped after Maps'
listener. A group whose properties already have their target values completes,
and translationZ alone starts automatically. All five exact PASS markers appear
and the fixed window survives the 45-second observation.

The initial old semantic check incorrectly rejected the launcher's expected
`ANDROID-WS-FAIL start activity` wrapper around the missing-method error.
Its original frozen runner and raw ART output remain intact. The separately
frozen [qualifier](vpa-translation-z-qualify.v) accepts exactly that one wrapper
on the old run and rejects it on the fixed run. Both receipts report
`expected-result-pass`. The committed runner includes this condition.

The build freezes the 634-file compiled V closure, pinned compiler, C helpers,
headers and generated C outside the checkout. Qualified336 provides V support
sources. Current host C/third-party assets and the two nativepolicy embedded
text inputs are separately pinned; the latter were absent from 336 evidence.
Earlier preparation failures are retained as sealed sibling
`vpa-translation-z338-prepare-failedN-2026-10-25` directories. All passed
complete independent readback; sibling receipts are
`vpa338-prepare-failedN-complete-readback-2026-10-25.json`.

| N | Manifest SHA256 |
|---|---|
| 1 | `6a1159f1b4ae07dd5c040f03ab820feeac48e1aae7f6c7026e4edf0f37d52f4b` |
| 2 | `e92b7213db8038582811e937ba32d2631f34d8a84f09264b45f77527a61a9cd8` |
| 3 | `368ee9afc135d6aed970e70e28103d41a616a93402a7280b838d2ddd4a6a3e85` |
| 4 | `70bdfdaf385332e2d30ee89fccae31b29e5d5e7a363b7d88f4daef79db7badb5` |
| 5 | `75f6c8caffd629be6ec08122a9e9111eb7533f11afc2c99dc3d5b615a5dc7374` |
| 6 | `f4455600966655fd97a4175a041975bfa26cab36d0de163d17c5a0b6849e6715` |
| 7 | `84a2dec1913f39e09a7029398c442a9ed856a440afbe7b753725b8cac0a74890` |
| 8 | `312320d1b3d8c3df911da7df820894b3f64459044df75a9ee7024f05cbb3eaf6` |

Attempts 1/2 stopped at a mistaken closure count and absent legacy/include;
only their source and partial trees are retained, without terminal failures.
Attempts 3/4 caught live vlib paths. Attempts 5/6 retained missing module-path
errors. Attempt 7 compiled successfully but used an incorrect CC-log prefix
guard. Attempt 8 retained the lazy embedded-file panic before framework work.

The complete 8,492-file bundle is retained at
`/Users/alex/.local/state/vinix/android/vpa-translation-z338-2026-10-25`,
manifest SHA256
`c8e780dfd7439d8f85a3f8abd70a43f78a53652128d489adbfec5e5079aeaaf2`.
Its framework/api-impl.jar is
`df8601f61867c276559c1799957865ef51a65b4cb8b343b848f2fca6370f16a7`;
the signed APK is
`99bd02a15922d57db1d7e967e866023511cb7d629c75b2d3e913086988f44e15`.
The independent qualifier source is retained under
`qualification/frozen/vroot/source/vpa-translation-z-qualify.v`, SHA256
`e55d52b8138a004be427b3b039d54aaa8965f654740b056bb81ce98b155562be`;
its executable is
`83ce82c4a5d86cb53cc551e918bc2c4152a792a223fb1a1fb88f4bf00dfcae61`.
Root and peer independently verified all 8,492 files with the existing complete
checker. Sibling receipts are
`vpa-translation-z338-root-readback-2026-10-25.json` and
`vpa-translation-z338-peer-readback-2026-10-25.json`.

These checks qualify the API contract; native depth ordering, elevation shadows
and the subsequent real Maps replay are separate checks.
