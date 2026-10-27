# Maps direct boot metadata diagnostic overlay

`maps-direct-boot-stage.v` appends a framework metadata correction to the sealed
`maps-controller-memory-r1` image. It uses the separate receipt kind
`vinix-maps-direct-boot-diagnostic-v1`. The corrected controller is the sealed
static ARM `maps-account-guest-build-2026-10-27-r7` producer; all producer and
base manifests are selected by exact constants in the stager.

The memory base manifest is
`944007c40fff691ad3c2973970ad5e840aea7bff7370bda5486377c274a1fd21`.
The complete framework producer at
`/Users/alex/.local/state/vinix/android/combined-account-webview-direct-boot-framework-2026-10-27-r1/`
has manifest
`a3445b78a7c4049fa71ee0f81469dca7da2236c36788500cd8bd3c8bb0b81552`,
JAR `bf3853c98155e420162dc8d1759735a497e8d8bb9724cd9eb7f209c4edb04c0d`
and DEX `3742f3915d4989ced425914e1fe4f6f662bd32566183534a849f8ad8ccd07213`.

The exact framework successor is the `direct-boot-2104` profile over the sealed
service-query framework. It retains 2,104 classes. Only `ComponentInfo` and
`PackageParser` change: one copy constructor and four component parsers change,
one parser helper is added, and `ComponentInfo.directBootAware:Z` is added.
The complete producer receipt, JAR and DEX identities are checked before and
after preparation. No other classes are added. This diagnostic supplies metadata
used by normal service resolution; it does not establish Google login success.

Exactly six regular files are appended: the framework JAR and DEX, headless
`framework-build.json`, `framework-sha256.json` and `guest-inputs.json`, and the
Maps deployment `build.json`. Headless inputs change only the existing JAR pin.
The deployment changes exactly the five payload input pins and its framework
manifest identity. All other decoded keys and values remain equal, including
the corrected controller aliases, JNI, launcher, APKs and security roles.

The memory stage retains eleven ordered modules. This stager preserves all
eleven, then appends `maps-direct-boot-diagnostic.tar`, yielding twelve. It
checks twenty inherited complete dependency bundles, the memory base and the
new framework producer. Destination and ancestor safety checks include the
original inventory and every overlay through the memory correction, preserving
first-inode modes. Historical staging profiles remain unchanged.

Preparation APFS-clones only boot media and firmware variables. TAR and module
hash checks stream bounded buffers. The output keeps the thirteen embedded
project source/header files, command receipts, inventories and source/tool
hashes. Host builds require Boehm GC. The external host toolchain, libraries and
operating system are environmental inputs, so the closure is not hermetic.

With the shared compiler slot released:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/maps-direct-boot-stage \
  tests/native-android-ws/maps-direct-boot-stage.v
/absolute/external/maps-direct-boot-stage --self-test
/absolute/external/maps-direct-boot-stage --prepare /absolute/external/fresh-output
```

The stager preserves the base kernel. Before booting a fresh mutable clone, use
a separately audited receipt profile to install the same frozen pidfd kernel.
No kernel source or kernel build change is needed for this framework overlay.

The pinned compiler built this Boehm host tool in 8.86 seconds with
531,120,128 bytes maximum RSS and zero swaps. Its self-test passed the exact
producer audit, obsolete pins, five-input deployment delta, one-input headless
delta, six-file payload, inherited modes and protected ancestors. Build and
self-test logs are retained outside Git in
`/Users/alex/.local/state/vinix/android/maps-stage-build-2026-10-27-r1/`.

Preparation passed at source revision
`374dfb6c1842c3523b49c582403347fc49be99f6`. The immutable output is
`/Users/alex/.local/state/vinix/android/maps-direct-boot-r1/`, with manifest
`fa9e552f7faf4aabfcf17821efc442918bab5576ea230d25eb9dcd6788d62285`,
receipt `6a26ae2fb065f53d2d37f379eb9089df5a5beb3e6386426fb6fee74f5823c2c9`
and overlay `33c2c38893f72f389601666dc8039c8855c935c91e20c9b8dc04816a6142ae56`.
It passed complete input inventories before and after preparation, all twelve
module readbacks and source-closure checks. Preparation took 170.82 seconds,
with 65,945,600 bytes maximum RSS and zero swaps. The original kernel remained
unchanged; ARM runtime and Google account sign-in still require separate checks.
