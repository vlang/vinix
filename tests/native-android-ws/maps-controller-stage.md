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
