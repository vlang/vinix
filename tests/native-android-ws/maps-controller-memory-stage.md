# Maps controller memory diagnostic overlay

`maps-controller-memory-stage.v` replaces only the Maps account controller over
the immutable `maps-service-query-r1` image. Its separate receipt kind is
`vinix-maps-controller-memory-diagnostic-v1`. It selects the complete static ARM
controller producer `maps-account-guest-build-2026-10-27-r7`, manifest
`680942c83d4877b8258e5f53ac454aebc3c021331470a002754bc1647ae1e890`,
and executable
`9c213a85235b802fc3b068ff2d195ea207ba82ded7fe6cdee408e0bd55921c0c`.

The overlay has exactly three regular files: the static controller at
`opt/vinix-maps-account/bin/maps-account-guest`, its identical desktop alias at
`usr/bin/run-android-calculator`, and `opt/vinix-maps-account/build.json`.
Only the two existing controller alias entries in the deployment receipt's
`inputs_sha256` change. All other decoded values and key sets remain equal,
including the service-query framework, JNI, launcher and security role pins.
This diagnostic does not establish Google account login success.

The sealed base's Limine configuration contains ten modules. Its receipt's
`preserved_modules_sha256` map has nine entries; the service-query overlay is
the tenth. The new stager verifies and preserves all ten, then appends
`maps-controller-memory-diagnostic.tar`, yielding eleven modules. It retains
the complete base and eighteen inherited dependency bundles, including the
previous controller producer. The corrected controller is a separate complete
input. Historical stagers and checkers keep their original strict profiles.

All occurrences of the payload destinations and their ancestors are checked
against the original module inventory and every later overlay inventory.
First-inode modes are preserved. Preparation APFS-clones only boot media and
firmware variables, streams the three-file TAR, and reads back the installed
overlay, Limine configuration and all ten original module hashes. The output
retains command receipts, thirteen embedded project source/header files,
inventories and source/tool hashes. Large inputs use bounded buffers; host
builds require Boehm GC. The host toolchain, libraries and operating system are
environmental inputs, so this closure is not hermetic.

With the shared compiler slot released, build and prepare from the repository:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/maps-controller-memory-stage \
  tests/native-android-ws/maps-controller-memory-stage.v
/absolute/external/maps-controller-memory-stage --self-test
/absolute/external/maps-controller-memory-stage --prepare /absolute/external/fresh-output
```

Preparation retains the base kernel. A separately audited controller memory
kernel-patcher profile must install the frozen pidfd kernel on a fresh mutable
clone before booting. The prior kernel profiles do not accept this receipt kind.

The pinned compiler built this host tool in 16.13 seconds with 466,894,848 bytes
maximum RSS and zero swaps. The self-test passed its exact-profile, obsolete-pin,
alias, receipt-delta, payload, inherited-mode and protected-ancestor cases.
Build and self-test logs are retained outside Git in
`/Users/alex/.local/state/vinix/android/maps-stage-build-2026-10-27-r1/`.

Preparation passed from source revision
`99de7484d7dd3c2b1fd4c2d519c73a60c881b7b3`. The complete immutable output at
`/Users/alex/.local/state/vinix/android/maps-controller-memory-r1/` has manifest
`944007c40fff691ad3c2973970ad5e840aea7bff7370bda5486377c274a1fd21`.
It checked all complete inherited bundles before and after preparation, read
back the overlay and every original module, and retained the source/tool closure.
Preparation took 163.63 seconds with 64,913,408 bytes maximum RSS and zero swaps.
This is host staging evidence; the corrected ARM controller still needs a guest
runtime check.
