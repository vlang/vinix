# Maps explicit service-query diagnostic overlay

`maps-service-query-stage.v` appends a framework-only diagnostic overlay to the
sealed `maps-controller-r1` image. It has its own receipt kind,
`vinix-maps-service-query-diagnostic-v1`. The pinned successor framework changes
one existing `PackageManager.queryIntentServices(Intent,int)` implementation;
it adds no classes, methods or fields. Its complete producer retains both DEX
inventories and the original protected-storage framework identity.

The six regular payload files are the framework JAR and DEX, the headless
`framework-build.json`, `framework-sha256.json` and `guest-inputs.json`, and the
Maps deployment `build.json`. Headless input pins change only the existing
framework JAR key. The Maps receipt changes exactly five existing input pins
for those framework and headless files, plus its `framework_manifest_sha256`.
All other decoded values and key sets must remain equal. The JNI, both
controller aliases, launcher, APKs, accounts, browser and sandbox roles retain
their complete original bundles and identities.

The stager checks the exact complete controller base, all sixteen inherited
manifest bundles and the new framework bundle before and after staging. It
audits destination and ancestor inodes in original module order, preserving
first-inode modes, APFS-clones only boot media and firmware variables, and
appends `maps-service-query-diagnostic.tar`. Independent FAT readback checks
the overlay, Limine configuration and all nine unchanged modules. No SDK or
runtime tree is copied or rebuilt. TAR and large-file hashing use bounded
buffers; the host stager uses Boehm GC.

Build and prepare with one compiler at a time:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/maps-service-query-stage \
  tests/native-android-ws/maps-service-query-stage.v
/absolute/external/maps-service-query-stage --self-test
/absolute/external/maps-service-query-stage --prepare /absolute/external/fresh-output
```

This separate diagnostic stage records the intentional framework successor
while preserving the original native producer's protected-framework coupling.
It does not alter production staging compatibility rules or authentication
checks. It is a credential-free framework isolation input, with no Google login
claim. The retained source and executable closure is not hermetic: host V/C
toolchains, libraries, SDK and operating system remain environmental inputs.
Preparation preserves the original kernel; use the separate service-query
kernel-patcher profile on a fresh mutable clone to install the frozen pidfd
kernel before booting. Prior producers and patcher profiles remain unchanged.

Validated on 2026-10-27 from source commit `61088f06c`. The immutable bundle is
`/Users/alex/.local/state/vinix/android/maps-service-query-r1`; its receipt
records checkout revision `9227518a0db0b8722c2373ef81ac7f6d9ca77bf5`, which
includes that source commit. All thirteen compiled project source/header
files are copied into the bundle and verified against their original paths
before and after preparation. The stager source SHA-256 is
`b37e93d522701cb66661643daa18d978753dfd4dfd9b4d1ce267b9e1d1748d21`;
the retained executable `../maps-service-query-stage-r1` is
`18aa92e042d5397435612f668c71151bfc9128ffa67170ba7b63a7f4044f4d77`.

| Validation | Result | Seconds | Maximum RSS (bytes) | Swaps |
| --- | --- | ---: | ---: | ---: |
| Host build, Boehm GC | Pass | 12.68 | 485,048,320 | 0 |
| Exact-profile and mutation self-tests | Pass | 0.28 | 12,140,544 | 0 |
| Fresh prepare and complete input rechecks | Pass | 128.73 | 65,306,624 | 0 |

The first compile rejected an immutable nested JSON fixture alias. A fresh
JSON encode/decode fixed that test fixture; the successful retry retained the
same production guards. Independent source review verified the exact producer
pins and receipt contract before preparation. The six-file TAR is 5,539,840
bytes. Disk free space changed from 25,929,500 to 24,693,524 KiB while other
sessions were active; this is not an isolated allocation measurement.

| Artifact | SHA-256 |
| --- | --- |
| Bundle `sha256.json` | `4d4850aa0f4204999e0d8d9c0cdd3ef0466b4d67c9b26ea371005e4cc93e0b9b` |
| `stage.json` | `18b7dd22ada72f89cdefea9f6bcda00362571bfb6a20e8f63e568177b32bae50` |
| `maps-service-query-diagnostic.tar` | `beab8be6e214199a1e7a509bc386943b31ccf45f89cc8580b94666a3b42fe5a0` |
| `boot.img` | `cd244cb944409f0e1446de7987951a63a8e13721abd90f7dcbb7a81a567c3efc` |
| Adjacent `maps-service-query-stage-compile-r1.log` | `3b7d699f473554fb25290dd05ee0d30547527940e19716959a51ea601c930305` |
| Adjacent `maps-service-query-stage-compile-r1-retry.log` | `b1e57226ea3de49c6b1926f602925ace30c38c23093f35ff879dbdc1682d679a` |
| Adjacent `maps-service-query-stage-selftest-r1.log` | `aee17f437f96e1055d21fea5a37d635f974e0451303148f40ee3d28a583a40d0` |
| Adjacent `maps-service-query-stage-prepare-r1.log` | `25554572eb8be4c64ff1839863ba7cc6d7bf0d2e4268a2f3ae64894ad5b96454` |

All nine original module hashes and their independent FAT readback receipts
are retained in the sealed bundle. Independent post-seal review matched the
copied source/tool closure, six payload digests, inherited modes, exact receipt
deltas, module readbacks and the measurements above. This validation prepares
a diagnostic input; actual guest startup and Google sign-in remain separate
runtime checks.
