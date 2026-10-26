# Browser diagnostic preparation — 2026-10-26 r12

r12 includes the packaged Mesa `llvmpipe` selection from source revision
`76a8df84f2be365825a04a0efaa472d85d3c3fe7`. The session receipt now records
`gallium_driver` and `libgl_always_software`. Preparation and dependency policy
are unchanged. This is build evidence; guest browser execution and Google
authentication require separate receipts.

The complete bundle is retained at
`/Users/alex/.local/state/vinix/android/browser-probe-build-2026-10-26-r12`.
`build.json` SHA-256 is
`33d92e97c5621d092b195551a1c3689b4bfdc5290697495b66a660265593a271`.
The separate complete tree inventory, `browser-probe-build-2026-10-26-r12-sha256.json`,
has SHA-256
`51b5cbf63c744697dcad5dc0d6d799c52df47a680b9032a09c22f5b556221ae3`.
Both inventory creation and a fresh verification passed.

| Executable | SHA-256 |
| --- | --- |
| `bin/browser-probe` | `fbdfdb01d4079e9f351f298c358030423513e633e067fb56744213716125bd46` |
| `bin/browser-session` | `f967b6aff9f29e53acf17ea8d5ef7857d7f043f61a8e3407503d1aa0b2ff4d56` |
| `bin/browser-guest` | `c96e91b90f45c6fe1511618f6e68fbbe810a6ec9a0e3fd82abba35ea9b5a5a3b` |

The unchanged standard `prepare.v` was built using pinned V
`0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe`,
with `-prod -cc clang -path '@vlib|build-support'`. Its retained executable is
`/Users/alex/.local/state/vinix/android/browser-prepare-r12`, SHA-256
`24b28a53ffcc1d92f418b62a04bd6e2c270f4d777fe7aa7179a3ed693a7aa093`.
Its existing self-tests passed, followed by all three standard cross-compiles.

The exact preparation arguments were the fresh r12 directory, base runtime
`/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64`,
base archives in the same build tree's `downloads`, addon archives at
`/Users/alex/.local/state/vinix/android/gms-browser-webview-audit-2026-10-26/wpe-dependencies/apks`,
the pinned compiler `/Users/alex/code/v-tccbin-bootstrap-20261026/v`, and the
complete retained r11 `fault-probe` directory. The command logs are retained
as `browser-prepare-r12{,-build,-self-test}.log` in the external state directory;
individual cross-compiler argv and results are inside the prepared bundle.

The maintained `compare-preparation.v` verified the pinned r11 `build.json`,
all eight copied source files, actual executable pins, and equality of every
base/addon archive, runtime/helper, compiler and fault-fixture dependency receipt.
Only `session.v` differs, at SHA-256
`fac881830a0efab0ddbfde6ccc4166bad57d8e23c74379d529971f7299e213fb`;
the seven other preparation sources are identical. This check passed using
the retained `browser-compare-preparation-r12` executable and log. The complete
r11 inventory was independently verified before preparation.
