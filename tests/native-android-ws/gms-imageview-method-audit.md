# GMS account-header ImageView caller, 2026-10-30

The fresh platform Fragment runtime retry (`maps-platform-fragments-vm-r2` under
the external state directory below) reached account-layout inflation and reported
a missing `ImageView.getMaxHeight()`
in `gjgi.<init>`. This static follow-up disassembles exactly that class from the
unchanged root GMS APK; no app, authentication or trust behavior was patched.

The constructor calls `getMaxHeight()I` at DEX offset `0x8c`, `.line 141`.
When its existing TypedArray boolean is true, the result becomes the header's
`LayoutParams.height`; it then calls `setLayoutParams` and selects `FIT_CENTER`.
Its other ImageView calls are the existing `getLayoutParams`, `getScaleType`,
`setLayoutParams` and `setScaleType`. The complete `gjgi` class contains no
`getMaxWidth` or `getAdjustViewBounds` call. These findings support preserving
XML max-height values as well as adding the missing getter. They do not establish
that account layout or sign-in succeeds after that repair.

Let `S=/Users/alex/.local/state/vinix/android`:

- Extraction: `S/gms-imageview-method-2026-10-30-r1/selected-gjgi/gjgi.smali`,
  SHA-256 `905d0980f05618aa5c039e7616a6a45f1a60288cd7e0bb99e1ee4a89bf37deac`.
- Controls: `S/gms-imageview-method-controls-2026-10-30-r1`.
- Complete five-root, 689-entry seal and fresh-process readback:
  `S/gms-imageview-method-evidence-2026-10-30-r1/sealed/manifest.json`,
  SHA-256 `7cbd86a3f00cf398426739c2f97336f54901ecccd2124dc27b965f873598c473`.

The unchanged [GMS lifecycle auditor](gms-lifecycle-class-audit.md) passed its
complete input readback. The previous report-fragment evidence seal also passed
again, binding all fifteen retained class-definition listings. They identify
exactly one owner for `gjgi`: `classes12.dex`, SHA-256
`800e00e6d6dcab23de8d6fcdfa48c13c684806ab06b9b744e0d907a69b3e7f30`.
The root APK remains pinned in that complete original bundle. Recorded checkout
base was `37a18e8dee81b64f8057f940cde441dd47e489c0`; extraction used its retained
tools, rather than concurrently edited framework code.

Java identity `236c86402d47923ebc974f8237175038eedfcb3b8a7594b2a2dd8113249b99ea`
matches the prior audit. Baksmali used a 256 MiB heap, two active processors,
two jobs, code offsets and one `--classes` selector. Full input readback and
selected extraction passed 600 MiB RSS, 300-second, 512 MiB observed-growth and
1 GiB-reserve guards. Extraction took 0.594 seconds with 109,445,120 bytes peak
sampled RSS; both guard/child exited zero with complete cleanup. Sealing and
separate readback also passed, retaining the stricter 64 MiB growth cap. Keep the
complete original bundles; the selected output alone does not replace them.
