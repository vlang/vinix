# Class-based framework JNI loading: host qualification

Core `09182301f` replaces the guarded `Runtime.load(String, ClassLoader)` call
with `Runtime.load0(Class, String)`, passing View.class and the existing absolute
library path. Pinned libcore rejects the old overload above target SDK 24;
VMRuntime's Java default is 10000. The replacement retains absolute-path
validation and the defining loader without changing target-SDK state.
It addresses the [ARM bootstrap failure](maps-framework-boot-runtime-2026-11-04.md);
another ARM run remains required.

The focused checker passed its first compile/run: 91 native origins, 90
unchanged sources, 92 inputs, one changed function and 27 refusal controls.
It pins original Runtime.java/ART sources and the complete new VMRuntime.java
fetch from the deployed ART commit. Historical audits remain unchanged.
Runtime source is `c733da77a56ad5c9c4740de5fc8791921e74089aaf494d749e562a5774cfedc0`;
checker source is `cb1b678f4cebd8d0d41a6779595c8e8ccb753e4f69a330be57fe53255fb6a3bf`.

Paths use `S=/Users/alex/.local/state/vinix/android`. New native bundle:
`S/current-native-build-2026-11-04-framework-jni-load-r1`. The unchanged
producer/bootstrap built against the unchanged framework-boot SDK manifest
`af23c13d90f557c4f7f208ae75c39ad8bcf0efd86fc88fddfe399fe2e66a4e91`.

| Native artifact | SHA-256 |
| --- | --- |
| Manifest | `2d9c97030ab7367b487b4a7b3a6b4ed27b1cf4e68cf6567054c7ea03cc667fa0` |
| Build receipt | `16cb572c43e56af969757b9c3296637c5007bf46bab842291fadfe746dc99318` |
| DSO | `13cf020729373ad8d20cfa4c5588c0878eee4be4fdf85700f2cf911ded08e81e` |
| Generated C | `6a5f5a0dd13a56041aa9d6edac05cf18fc4fb40e8b5c439088993d2bf1c46e04` |

The [new full readback](framework-jni-load-native-readback.v) passed 16 refusal
controls and complete old/new/SDK rechecks. Only the reviewed V function and
its generated C function differ. All 70 consumed SDK classes, 721 exports,
bindings, 58 normalized C/header inputs except generated C, 340/660 helper
closures, compiler inputs, normalized cross argv and ELF dependencies match.
Production passed in 43,940 ms at 566,411,264 sampled RSS bytes and 394,698,752
bytes growth under original 600 MiB/300-second/1 GiB growth limits. Full
readback passed in 3,849 ms at 48,414,720 RSS bytes and 3,973,120 bytes growth
under its original 900-second/512 MiB growth limits. A first attempt with a
stricter 64 MiB growth cap stopped at 116,498,432 bytes shared growth; it is
retained. No functional check was relaxed. Positive guards/children exited
zero, cleanup complete; reserve/output/file limits remain unchanged.

Complete evidence roots are the native bundle, matching
`framework-jni-load-native-controls-2026-11-04-r1`, source-tools, source-controls,
source-check and primary roots named `framework-jni-load-*-2026-11-04-r1`.
Their six-root, 1,975-entry seal is
`S/framework-jni-load-pair-sealed-2026-11-04-r1/sealed/manifest.json`, SHA-256
`9c7b5ae301a374031e51e52ef2c5302362aa8cfb5813ec931b13d7db0536d03a`.
Seal and fresh readback passed in 417/232 ms under the original 64 MiB cap.
Complete originals and historical auditors remain required. Delivery, image
preparation and ARM execution are separate steps.
