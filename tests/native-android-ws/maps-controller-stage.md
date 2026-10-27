# Maps controller diagnostic overlay

`maps-controller-stage.v` replaces the Maps account controller over the sealed
`maps-startup-r1` image. Its separate `vinix-maps-controller-diagnostic-v1`
receipt records this limited change. It makes no Google account login claim.
The framework, JNI, launcher, APK identities, account/browser roles and their
original complete receipts remain pinned to the startup deployment.

The overlay has exactly three regular files: the static ARM controller at
`opt/vinix-maps-account/bin/maps-account-guest`, its identical desktop alias at
`usr/bin/run-android-calculator`, and `opt/vinix-maps-account/build.json`.
The deployment receipt changes only those two existing `inputs_sha256` entries;
all other decoded values and key sets remain equal. Directory entries must be
ancestors of those files. Every occurrence of their destinations and ancestors
in the original eight TAR modules is checked, preserving first-inode modes.

The stager checks the complete sealed base, all fourteen inherited dependency
bundles, and the exact new controller producer before and after staging. It
APFS-clones only boot media and firmware variables, appends
`maps-controller-diagnostic.tar`, and reads back both the overlay and Limine
configuration. All eight existing FAT modules must retain their hashes.
The complete external output retains command receipts, thirteen embedded
project source/header files, tool hashes, inventories, modes and media hashes.
Large files and TAR modules use bounded streaming buffers; host builds use
Boehm GC. This audit closure retains project sources and executable identities;
the host V/C toolchain, libraries, SDK and operating system are environmental
inputs and the build is not hermetic.

Build and prepare from the repository, with one compiler at a time:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/maps-controller-stage \
  tests/native-android-ws/maps-controller-stage.v
/absolute/external/maps-controller-stage --self-test
/absolute/external/maps-controller-stage --prepare /absolute/external/fresh-output
```

Preparation preserves the base kernel. Before booting, use the separately
audited controller diagnostic kernel-patcher profile on a fresh mutable clone
to install the frozen pidfd kernel. The protected-storage patcher profile and
production deployment checker retain their original strict receipt kinds.

Measured preparation on 2026-10-27 used source revision
`1d0dc5da7063893dcf9db86d457a09bcf827b777`. The immutable complete bundle is
`/Users/alex/.local/state/vinix/android/maps-controller-r1`, with manifest seal
`3026dfd0e7d69fe81d0b8ba4d504d952fd14fa34d20c9b4cdf6d0b98cc9d857a`.
The controller overlay is 2,498,560 bytes, SHA-256
`bef5f25859e77a9671a6a144ccb56891da5ed2f7b4324a93a96da7fdcab1987a`.
The output retains the complete base, fourteen original dependency bundle
manifest pins, the new controller producer, source closure and tool identities.
Independent review passed the source, aliases, receipt delta and inherited modes.

External logs are beside the bundle, under
`/Users/alex/.local/state/vinix/android/`. The successful Boehm build took
12.07 seconds with 437,256,192 bytes peak RSS; self-tests took 0.32 seconds
with 7,602,176 bytes; preparation took 96.67 seconds with 68,648,960 bytes.
All three exited zero with zero swaps. Their logs and SHA-256 values are:

| Log | SHA-256 |
| --- | --- |
| `maps-controller-stage-compile-r1-retry.log` | `d0c391a634194a2bb3e7b198fe7bcafdedfda20a15f24b46eddd19697d7e5584` |
| `maps-controller-stage-selftest-r1.log` | `309221b2ec1908cf0c27755ce115e42f889e5c8cc701ab4c4abe3c570683b6b2` |
| `maps-controller-stage-prepare-r1.log` | `d30533d34a38b5d7177ad1bb03a4ddc6e122866ca72b07eb157255676272acd6` |

The initial build rejected a mutable self-test fixture alias; fresh JSON decode
fixed that fixture without changing staging guards. Its rejected build log is
`maps-controller-stage-compile-r1.log`, SHA-256
`0db4e0218894fc074e10337d4739ddb36958d0ccd502427e94e9e491c32a0ae2`.
An initial unsupported CLI invocation exited two before creating output; it is
preserved as `maps-controller-stage-prepare-r1-cli-rejected.log`, SHA-256
`e0a7e15a76a87ce692756dabb40139158307c42e351802f9a384f5e94f05c09b`.
Available host disk changed from 24,873,136 to 22,729,860 KiB while other
sessions were active; this is not an isolated disk-use measurement.
