# Protected storage Maps startup diagnostic

`protected-storage-map-stage.v` stages a credential-free startup retry over the
immutable `maps-account-r5` deployment. Its separate
`vinix-protected-storage-maps-diagnostic-v1` receipt records the retained launcher
and role provenance. It does not establish Google account login and does not
relax the production deployment checker or account/browser isolation rules.

The stager verifies complete original bundles, the new framework/native pair,
retained launcher service ABI and all seven original FAT modules. Existing
API 29/signature gates retain their original APK and role identities. It
APFS-clones only the original boot media and firmware
variables, appends `protected-storage-diagnostic.tar`, and reads back both the
overlay and Limine configuration. All seven original modules must retain their
hashes afterward; all complete input bundles are then rechecked.

The overlay has exactly nine regular files: framework JAR and DEX, native JNI
library, headless guest input pins and four framework/native receipts, and the
Maps deployment receipt. The headless receipt changes exactly two existing
pins. The deployment receipt changes exactly eight existing input pins and
three top-level values (`inputs_sha256`, `framework_manifest_sha256`,
`native_manifest_sha256`). Other decoded values and key sets remain equal.
Directory entries are restricted to ancestors, and every original TAR
occurrence is checked for unsafe ancestors or modes; first-inode modes are
preserved, including executable JNI mode.

Build and run from the repository with one compiler at a time:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/protected-storage-map-stage \
  tests/native-android-ws/protected-storage-map-stage.v
/absolute/external/protected-storage-map-stage --self-test
/absolute/external/protected-storage-map-stage --prepare /absolute/external/fresh-output
```

The complete input roots and seals are pinned in the source. The original
protected-storage diagnostic used base seal
`9a8bf61bd526d7ec020d45920367d45e90a2ef4692c6d8fa8b87de801a14c5ca`,
protected framework seal
`67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938`,
and protected native seal
`894c9657077cdd913a2c66c1cf78358daaccc4da8b0739ed77bb2a3dbea1b4ee`.
Source implementation: `df1592ccf63c4d4fd029f4fcf46ed418cdf802a6`, with
receipt-directory fix `3e0291c128a18795c9cab0746f88385ac62b973e`.

The bundle retains thirteen embedded source files, executable and tool hashes,
copied media tools, command receipts, payload/overlay inventories, inode modes,
configuration readbacks, media hashes, and the final complete file manifest.
Media and large files are hashed with a 1 MiB streaming buffer. Host build uses
Boehm GC for repeated decoded inventory maps. This is a retained audit closure,
not a hermetic V/C toolchain: V libraries, C compiler/SDK, host dynamic
libraries, Perl dependencies and operating system remain environmental inputs.

On 2026-10-27, source revision
`3e0291c128a18795c9cab0746f88385ac62b973e` passed the following measured checks:

| Check | Exit | Wall seconds | Maximum RSS bytes |
| --- | ---: | ---: | ---: |
| Boehm host compile | 0 | 25.89 | 419299328 |
| Positive and rejection self-tests | 0 | 2.25 | 7356416 |
| Complete prepare and media readbacks | 0 | 158.52 | 76447744 |

All three recorded zero swaps. The pinned compiler SHA-256 is
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`;
the resulting external `protected-storage-map-stage-r3` executable SHA-256 is
`3cf841191259e6cee5bd3de7620197a5a164d0cf863fdd067fc820fd547b810d`.

The successful immutable bundle is
`/Users/alex/.local/state/vinix/android/maps-storage-r2`, with complete
`sha256.json` SHA-256
`9d99d57603b86e1408980a8cf982bb0f3dabfcef789eef58e5c012c986472562`.
Its 6,594,560-byte overlay SHA-256 is
`4ce8aa55466dc36700f9ff66970001d41d53df1c3c3cc40752d29f932c705e17`.
The media are APFS clones: a 4 GiB logical boot image and 64 MiB firmware file.
`du -sk` reports 4,208,560 KiB including shared media extents. Filesystem free
space was 25,318,584 KiB before and 24,776,324 KiB after; other sessions were
active, so that difference is not a unique allocation measurement.

Measured logs remain beside the bundle under
`/Users/alex/.local/state/vinix/android/`:

| Log | SHA-256 |
| --- | --- |
| `protected-storage-map-stage-compile-r3.log` | `89c43f6b6fd44d4bc48508c6c8347578511c20077aeee3e7395e2732f3ac951b` |
| `protected-storage-map-stage-selftest-r3.log` | `74e030ba6fd89c329448e0566de90da17c159f51d5fd77fb4ff6ab4d0c4ed320` |
| `protected-storage-map-stage-prepare-r2.log` | `a703be16b5f0fd4781009426a0cd69389309c4c08b78efaa527799d72ffd7f2e` |

The earlier `maps-storage-r1` is an incomplete, unsealed failed attempt. It
stopped before media cloning because a generated receipt parent was absent;
the committed directory fix above is included in r2. Use only the sealed r2
bundle for that original native profile. Guest execution and account login
remain separate validation.

## Binding deadline diagnostic

Source revision `7ed2682b7ce9cf9c08ccbfe9f594ff5aaa341d6a` selects
`current-native-build-2026-10-27-binding-r2`, manifest SHA-256
`bd0e3902130f74877abaf269301377c7b5d2cbfe9e7732508838d84ec863d19d`,
and JNI SHA-256
`8508d4acb9a96c15eddd3a4afd075855270e2dae48006a9675a86ead0b2f6f19`.
The r5 base, protected framework and complete original role bundles remain
unchanged. Prior producers and stages remain immutable.

This exact native profile changes the sealed service source to add the opt-in
numeric binding deadline record and portable printf casts. The stager retains
source equality acceptance and additionally accepts only this ordered pair:

| Sealed source | SHA-256 |
| --- | --- |
| Retained launcher `abi/headless.v` | `c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57` |
| Binding JNI `native/atlframework/headless.v` | `e0f72ab74ccf89d91dd66c23ae35823079e9ead4552e965ab198b3b91057c489` |

The unequal pair also requires the exact native manifest and library above.
Independent review compared the complete sealed source diff and verified the
unchanged exported `vinix_android_native_service_main` entry and seven-argument
signature. The retained native-entry source and new implementation bytes are
rehashed against their complete manifests before the existing launch builder's
declaration and call checks run. Native export command/source receipts and
the original launch receipt remain fully checked. Positive and rejection
self-tests cover equality, the audited pair, reversed/unknown source pairs,
unrelated native profiles and changed declarations, calls or signatures.
Production deployment checks remain unchanged.

The initial constants-only attempt correctly failed the source equality gate
before creating an output directory or cloning media. Its retained log is
`protected-storage-map-stage-prepare-binding-r1.log`, SHA-256
`6fafbb0f4ae678560ef20e2d20b1be17a47e8314a33a13b9c9314676d33ad3c1`;
exit 1, 19.96 seconds, maximum RSS 48,037,888 bytes, zero swaps.

The revised stager source SHA-256 is
`5eb327b195a11294706c07cb89ee7b54ab4cc3e5f34c13df7002e95963822c28`.
The retained `protected-storage-map-stage-r5` executable SHA-256 is
`13a0255bc8e8a085cc1c5a17757afc7f4ec7826c6ce0b7c7962a3d235ea0ea33`.
The same pinned V compiler and Boehm build command above were used.

| Check | Exit | Wall seconds | Maximum RSS bytes |
| --- | ---: | ---: | ---: |
| Boehm host compile | 0 | 10.36 | 428261376 |
| Expanded positive and rejection self-tests | 0 | 1.94 | 7372800 |
| Complete prepare and media readbacks | 0 | 94.43 | 62373888 |

All recorded zero swaps. Adjacent logs are
`protected-storage-map-stage-compile-r5.log` (SHA-256
`9826f51481f76976d04b36b6b7768d58064ac8e04adfbf896de1687b59923411`)
and `protected-storage-map-stage-selftest-r5.log` (SHA-256
`63b80c47e6803fa3edb5da2d32a7d3f69ee73536a297e3da42bbfd9e726816d1`).
The successful prepare log is
`protected-storage-map-stage-prepare-binding-r2.log`, SHA-256
`4fa3b36a5ec8169fe4d3a02dbf3c4f08c7e1acfa57699d98ac3554ecc97e409b`.

The new immutable bundle is
`/Users/alex/.local/state/vinix/android/maps-binding-r1`, with complete
`sha256.json` SHA-256
`ae6ba098eaddb61f5edf895fd831075c0c1a23bbf37ad0ebca3c1d81dcec91fc`.
Its recorded checkout revision is
`aa8c5debcc534751af17c6d7601bd97f61970abb`, which includes the implementation
commit above; the embedded source hashes also match the checkout. The exactly
nine-file overlay is 6,604,800 bytes, SHA-256
`f7f2ff6cda52025b339437938f4df7decee4cb480790c6d5c631ba66c69d6ef0`.
The staged boot image SHA-256 is
`9a3206317893de5de54a18886d60e4671cbce62387a9780f8b46905de45a0e65`.
The unchanged firmware SHA-256 is
`d3b3f7afddb44de7020b8544270a67791fca44a48864dcd550cefee633463cbf`;
Limine SHA-256 is
`3f4e6f9056ac36958a236ef0ed53211f5c3ecc65cbd44d9e98cb0ffbbe075194`.
All seven original modules and complete input bundles passed rechecks.

Only the 4 GiB logical boot image and 64 MiB firmware file were APFS-cloned;
no SDK or runtime copy was made. `du -sk` reports 4,208,576 KiB including shared
media extents. Filesystem free space was 70,605,204 KiB before and 69,334,620 KiB
after; other sessions were active, so this is not a unique allocation measure.

The JNI producer's strict AArch64 build passed in 222.41 seconds with maximum
RSS 582,860,800 bytes. Its independent complete 1,197-file check passed in
9.28 seconds with maximum RSS 1,291,485,184 bytes; both recorded zero swaps.
Their adjacent evidence remains in the external state directory:

| Evidence | SHA-256 |
| --- | --- |
| `current-native-build-2026-10-27-binding-r2.log` | `9bf5b7c6b5c10f829641f9b8bc2784b01e071ee3d8334e51cc5f06f081dc8ed9` |
| `current-native-build-2026-10-27-binding-r2-independent-check.log` | `31dde10ec70c7a9e54975973b78f884d64389345dc6411a2d43491bd3d77ba3b` |
| `current-native-build-2026-10-27-binding-r2-independent-check.json` | `5cf10529807d2bf155920d12b04457f4d52e4a20aa7fbd84546079de079bedd3` |

No guest execution or Google login is established by preparation. The subsequent
root-run diagnostic must record its explicit
`VINIX_ANDROID_TRACE_SERVICE_BINDING=1` environment prefix.

## Separate service startup budget

Implementation revision `85cdab8c6ff830ede63e853ef499c39f7d946a2b` selects the
new sealed `current-native-build-2026-10-27-startup-r1` producer, source revision
`302628d15c27306e6f394237010af59fdd63a413`. Its manifest SHA-256 is
`a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20`,
and JNI SHA-256 is
`82e4bdb907a300634b304b37339b2e9a836f6f1a61d01a369d0f5aa707fddca7`.
The retained launch source remains
`c453f9a0a4ab8b5f8ad4ea17d0c932304d61aafb6126d55b9bcc55efe0aa9b57`;
the new JNI service source is
`e2be36f866ac321a7d681112e3514d8b1c8ac06553538758d7c1c220b9f3c72f`.
This exact ordered pair requires the new manifest and JNI hashes. The previous
producer and stages remain immutable; the current profile rejects obsolete
binding-r2 and mixed old/new source or native identities.

Independent read-only review compared the sealed source and export receipts.
Relative to binding-r2, the only source change is the service startup deadline
from five to 45 seconds and its explanatory comments. The existing numeric
diagnostics, seven-argument exported entry, declaration and call remain
unchanged. Account IPC retains its five-second budget. The nine-file payload,
decoded receipt deltas, complete role checks and production checker are
unchanged.

The retained `protected-storage-map-stage-r6` executable SHA-256 is
`a6880d56310a565e655da5559832ab28b75c2b989fdd4bb31fc24cc63970e073`;
its source SHA-256 is
`1085f7065093dc5c4a39ef8a7ee246fac23355352302cfccbf2ca5b02ecc512a`.
The pinned compiler and Boehm command above were reused. Host compilation
passed in 8.20 seconds with maximum RSS 446,513,152 bytes. Expanded positive
and rejection self-tests passed in 1.51 seconds with maximum RSS 7,389,184
bytes. Both recorded zero swaps. The adjacent logs remain external:

| Evidence | SHA-256 |
| --- | --- |
| `protected-storage-map-stage-compile-r6.log` | `e6d3338c0e12734c67077f860fa6cf8b72fa919e30e376cfa7e76a1aec68e12c` |
| `protected-storage-map-stage-selftest-r6.log` | `40253b9784c287372e2dd7a67cacc0c176f26cca2a5081a46a43ae96c4625411` |
| `current-native-build-2026-10-27-startup-r1.log` | `6877dde2809a546d3bc7790101d19ac49ad4a49774ad0c28760ff4b03791599f` |
| `current-native-build-2026-10-27-startup-r1-independent-check.log` | `d19558fb3235ce9f974da5098f6524a807cd18cb995b9cb9ac28fb263af635b7` |
| `current-native-build-2026-10-27-startup-r1-independent-check.json` | `a7101371b781d096f2d7e6332d72ae59bd12edb30ca1bedbc7c5710f905b0331` |

The strict AArch64 native build passed in 46.39 seconds with maximum RSS
604,930,048 bytes. Its independent complete 1,197-file check passed in 2.00
seconds with maximum RSS 1,288,978,432 bytes. Both recorded zero swaps.

Fresh preparation passed in 112.56 seconds with maximum RSS 61,915,136 bytes
and zero swaps. The immutable output is
`/Users/alex/.local/state/vinix/android/maps-startup-r1`, with complete manifest
SHA-256 `f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332`.
Its receipt records the implementation revision above. The prepare log is
`protected-storage-map-stage-prepare-startup-r1.log`, SHA-256
`acdfa85a7817206211aec26fd46aae45d00094c4e36b8e1c64891d22ce58bc81`.
All complete input bundles, seven original modules, overlay and media readbacks
passed. The 6,604,800-byte overlay SHA-256 is
`cb2d855ac82924d6bc0f2221bea0d6cccbf2f9a9d467c455fbf9acba5d594ac3`;
boot image SHA-256 is
`24999d2743f4c86196b39113b68062908a698945864c2ca551dff4f0578677c6`.
Firmware and Limine retain the hashes recorded for the binding stage above.

Only the boot image and firmware were APFS-cloned. `du -sk` reports
4,208,576 KiB including shared media. Filesystem free space was 56,176,044 KiB
before and 51,730,096 KiB after; other sessions were active, so this is not a
unique allocation measure. No guest or Google login result is established by
preparation. The root-run retry must record the explicit diagnostic environment
prefix and preserve this sealed stage by running a fresh clone.
