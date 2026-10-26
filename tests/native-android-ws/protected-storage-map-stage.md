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

The complete input roots and seals are pinned in the source. This diagnostic
uses base seal
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
bundle for subsequent guest diagnostics. Guest execution and account login
remain separate validation.
