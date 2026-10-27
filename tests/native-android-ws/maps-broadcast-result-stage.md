# Maps BroadcastReceiver result diagnostic overlay

`maps-broadcast-result-stage.v` appends generic BroadcastReceiver result APIs to
the immutable credential storage Context stage. Its separate receipt kind is
`vinix-maps-broadcast-result-diagnostic-v1`; previous staging profiles remain
unchanged. Google Play Services reached `setResultCode(int)` during its actual
startup broadcast and failed because that framework method was unavailable.
This overlay enables another runtime retry; it does not establish account login.

The exact base is
`/Users/alex/.local/state/vinix/android/maps-context-storage-r1/`, manifest
`6296bcff89e1a6555c803b0ee94f435cbae1f01c37ce97451080612a95fdde2c`.
Its retained framework producer is
`/Users/alex/.local/state/vinix/android/combined-account-webview-credential-storage-framework-2026-10-27-r1/`,
manifest `cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691`,
JAR `9b894cc92c5d3d0e871b5389285b09b107d49cd5c4493fcc2449f3510f961352`
and DEX `b96a441b6eca36e0a6fa7a6da01d9e4508136e64ec0f0f3850cf15e2d90ff132`.
The successor producer profile is `broadcast-result-2104`. It changes the existing
BroadcastReceiver, PendingResult, ATLLoadedApp and VinixBroadcast classes, with
changed method counts of 2, 2, 1 and 1 and added method counts of 14, 11, 0 and 0.
It adds one private receiver field and six private PendingResult fields, with no
added classes. Manifest and registered delivery share per-delivery result state;
Java replaces the broadcast task's lazy JNI entry while the native library stays
compatible. The complete successor is retained in
`/Users/alex/.local/state/vinix/android/combined-account-webview-broadcast-result-framework-2026-10-27-r1/`,
manifest `21d53cc9cd2ccd9c53fc7774a826d83673f3391d30c1757074e3edcba2c8b046`,
JAR `5dfba8c7e0006f6c84510d72b8fde84706bcb7f3489b3620cd340ec0361d8564`,
DEX `5305155d203c856a1828596d06c48ba130fbf9a373dec6b558a3fc4e53bdac11`
and build receipt
`280b6de249825cfc773e16e12c933d18a6013a4ac8b7e9a0cbbc9e7f1cdbc1e1`.
Preparation requires these exact pins and verifies the complete sealed bundle.

Exactly six regular files are appended: the framework JAR and DEX, headless
`framework-build.json`, `framework-sha256.json` and `guest-inputs.json`, and Maps
`build.json`. Headless inputs change only the existing JAR pin. The deployment
changes exactly five payload input pins and the framework manifest identity.
All other decoded keys and values remain equal, including the r7 controller
aliases, JNI, launcher, APKs and security roles.

All thirteen ordered base modules are preserved before the fourteenth,
`maps-broadcast-result-diagnostic.tar`, is appended. Preparation verifies
twenty-four inherited complete bundles, the Context storage base and the new
framework producer before and after preparation. Every earlier overlay's
destination and ancestor modes are audited, including the direct-boot and
Context storage corrections; first-inode modes remain unchanged. Thirteen
embedded project source/header files and command/tool identities are retained.

The output uses APFS media clones with no full-copy fallback. Disk samples use
`/usr/bin/env LC_ALL=C /bin/df -kP`, with a two-second deadline, 8 KiB output
bound and checked KiB conversion. Preparation requires at least 1.5 GiB of
initial available space, maintains a 1 GiB reserve and rejects a decrease above
512 MiB from the initial sample. Samples follow input audits, source/tool and
payload writes, each media clone, overlay creation, each FAT mutation and the
final recheck. Concurrent writes may conservatively trip this guard. Failed
artifacts remain external; historical evidence is never deleted or rewritten.

The base kernel remains unchanged. A separately audited receipt profile must
install the same frozen pidfd kernel in a fresh mutable clone before runtime
validation. No runtime or kernel rebuild is required for this framework overlay.

Measured host validation is retained in
`/Users/alex/.local/state/vinix/android/maps-broadcast-result-stage-build-2026-10-27-r1/`.
`build.log` records 10.47 seconds, 466,436,096 bytes maximum RSS and zero swaps.
`self-test.log` records PASS in 0.31 seconds, 12,304,384 bytes maximum RSS and
zero swaps, covering the strict disk parser and reserve/growth boundaries,
exact profile, five-input deployment and one-input headless deltas, six-file
payload, inherited modes and protected ancestors. The tested tool SHA-256 is
`26b86e5bca4a0d7d5d14dc39202e19a5a6378b7c1efa2c54fd61c59dce4aadb6`.

The original `prepare.log` and failed output remain intact. Its overlay install
exited 153 (SIGXFSZ) under the outer process's 512 MiB file-size limit, after
90.22 seconds with 52,527,104 bytes maximum RSS and zero swaps. Repeating with
the same tool and a 16 GiB outer file-size limit passed; the stager's disk
reserve and growth guards stayed enabled. `prepare-r2.log` records PASS in
167.64 seconds, 64,585,728 bytes maximum RSS and zero swaps, with all disk
samples passing and complete immutable inputs rechecked.

The successful immutable stage is
`/Users/alex/.local/state/vinix/android/maps-broadcast-result-r2/`.
Its `sha256.json` SHA-256 is
`98522d60a7627927b7ee6b861db502b6574e3d6ab14fdecb09e2da38b2f441de`;
`stage.json` SHA-256 is
`8c5cc2c1d6ad92cbd6ae0f95d265b5f69f41e40c36a7bd3873139ffb2ccbabcd`.
The receipt records source revision
`445f57ce7dd45da2cf407e051603b109803b2c57` and pins the exact retained thirteen-file
source/header closure. Its retained stage source matches the tested checkout
bytes, SHA-256
`de945cffef28351dabd43d9b52a21be07235d8ea1b37b6a38a06cce1b59e64a9`.
These results establish host staging and self-test success; guest execution,
Maps startup and Google account authentication require separate runtime evidence.
