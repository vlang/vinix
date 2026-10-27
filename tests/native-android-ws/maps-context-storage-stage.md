# Maps credential storage Context diagnostic overlay

`maps-context-storage-stage.v` appends the generic credential storage Context
API correction to the immutable direct-boot framework stage. Its separate
receipt kind is `vinix-maps-context-storage-diagnostic-v1`; historical staging
profiles remain unchanged.

The exact base is
`/Users/alex/.local/state/vinix/android/maps-direct-boot-r1/`, manifest
`fa9e552f7faf4aabfcf17821efc442918bab5576ea230d25eb9dcd6788d62285`.
Its direct-boot framework baseline has manifest
`a3445b78a7c4049fa71ee0f81469dca7da2236c36788500cd8bd3c8bb0b81552`,
JAR `bf3853c98155e420162dc8d1759735a497e8d8bb9724cd9eb7f209c4edb04c0d`
and DEX `3742f3915d4989ced425914e1fe4f6f662bd32566183534a849f8ad8ccd07213`.
The successor producer is
`/Users/alex/.local/state/vinix/android/combined-account-webview-credential-storage-framework-2026-10-27-r1/`.
Its manifest is
`cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691`,
JAR `9b894cc92c5d3d0e871b5389285b09b107d49cd5c4493fcc2449f3510f961352`
and DEX `b96a441b6eca36e0a6fa7a6da01d9e4508136e64ec0f0f3850cf15e2d90ff132`.

The required `credential-storage-2104` framework audit retains 2,104 classes.
Only `ContextImpl`, `Context` and `ContextWrapper` change, each adding exactly
`createCredentialProtectedStorageContext()` and `isCredentialProtectedStorage()`.
There are no changed existing methods, added fields or added classes. The
producer audit and complete framework inventory are checked before and after
preparation. This fixes API availability; Google account login requires a
separate runtime check.

Exactly six regular files are appended: the framework JAR and DEX, headless
`framework-build.json`, `framework-sha256.json` and `guest-inputs.json`, and Maps
`build.json`. Headless inputs change only the existing JAR pin. The deployment
changes exactly the five payload input pins and framework manifest identity.
All other decoded keys and values remain equal, including the sealed r7
controller aliases, JNI, launcher, APKs and security roles.

All twelve ordered base modules are preserved before the thirteenth,
`maps-context-storage-diagnostic.tar`, is appended. Preparation verifies
twenty-two inherited complete bundles, the direct-boot base and new framework
producer. Destination and ancestor checks include every earlier overlay,
including the memory and direct-boot corrections, retaining first-inode modes.
APFS media clones, streaming TAR checks and complete inventory readbacks bound
memory use. Thirteen embedded project source/header files and command/tool
receipts are retained in the output; the external toolchain and operating
system remain environmental inputs.

Preparation requires at least 1.5 GiB of initial free space. It records free
bytes after input audits, retained source/tools, payload creation, each media
clone, overlay creation, each FAT mutation and the final input recheck. It
fails if free space falls below a 1 GiB reserve or decreases by more than
512 MiB from the initial sample. Unrelated concurrent writes can conservatively
trip this guard. APFS cloning has no full-copy fallback; no immutable evidence
is deleted or rewritten to recover space.

Samples use `/usr/bin/env LC_ALL=C /bin/df -kP` for the output parent filesystem,
with a two-second deadline, an 8 KiB output bound and checked KiB-to-byte
conversion. The command identity and tool hashes are retained. The pinned
bootstrap's `os.disk_usage` declares an incompatible Darwin `statvfs` layout;
its impossible 1.17 TB reading tripped the guard during the first input audit,
before creating an output directory. That failed 38.48-second preparation
used 36,028,416 bytes maximum RSS and zero swaps. Its complete build and failure
logs remain in the `maps-context-storage-stage-build-2026-10-27-r1/` state bundle.

With the shared compiler slot released:

```sh
/Users/alex/code/v-tccbin-bootstrap-20261026/v -new-compiler -prod \
  -gc boehm -nocache -cc cc \
  -path '/Users/alex/code/vinix/tests/native-android-ws|/Users/alex/code/vinix/build-support|/Users/alex/code/vinix/build-support/android|@vlib' \
  -o /absolute/external/maps-context-storage-stage \
  tests/native-android-ws/maps-context-storage-stage.v
/absolute/external/maps-context-storage-stage --self-test
/absolute/external/maps-context-storage-stage --prepare /absolute/external/fresh-output
```

Preparation preserves the base kernel. A separately audited receipt profile
must install the same frozen pidfd kernel in a fresh mutable clone before boot.
No runtime or kernel rebuild is required for this framework overlay.

The pinned compiler built the corrected Boehm host tool in 9.37 seconds with
527,286,272 bytes maximum RSS and zero swaps. Its self-test passed malformed and
overflowing `df` output, disk reserve and growth boundaries, exact producer
profile, obsolete pins, receipt deltas,
six-file payload, inherited modes and protected ancestors. Build/self-test logs
and executable are retained in
`/Users/alex/.local/state/vinix/android/maps-context-storage-stage-build-2026-10-27-r2/`.
The executable SHA-256 is
`e06aa25dc9e8ec090abaebead26768b2dce051ebe04a393bedd54821d6bc468e`.
