# Credential storage Context regression

Real Play Services startup reached `aeaj.a` and failed because Context did not
declare `createCredentialProtectedStorageContext()`. The next method, `aeaj.b`,
also requires `isCredentialProtectedStorage()`.

Source commit `34ecf3339` adds both APIs to Context, delegates them through
ContextWrapper, and implements them on ContextImpl. Each factory call returns
a fresh ContextImpl with the existing resources, app and theme; it clears only
the device storage flag. This preserves other flags and avoids copying cached
directories or preferences from the original context. The credential predicate
complements the existing device predicate because this runtime has two storage
modes: the app root is credential storage and its private `device_protected`
child is device storage. Both directories are available together; this change
does not introduce separate encryption keys or a lock/unlock lifecycle.

The factory and wrapper contracts follow Android 10's
[Context](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r47/core/java/android/content/Context.java),
[ContextWrapper](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r47/core/java/android/content/ContextWrapper.java)
and [ContextImpl](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r47/core/java/android/app/ContextImpl.java).
The existing configuration factory already preserves the storage flag; the
new fixture verifies that behavior for both modes.

The maintained `--credential-storage` producer requires the complete sealed
direct-boot baseline. It preserves all 2104 classes and all existing methods,
adds exactly two methods to each of Context, ContextWrapper and ContextImpl,
adds no fields or classes, and preserves all non-DEX JAR members. It repeats
the exact delta check after DEX roundtrip. The focused checker also assembles
the three classes and rejects malformed or previously extended input.

The signed fixture retains the explicit service query and direct-boot metadata
checks, then verifies default CE mode, dual storage predicates, fresh factories,
DE-to-CE roundtrips after both directory caches are primed, independent committed
preferences, nested wrapper factories, configuration contexts, app/resources
identity and unchanged original contexts. Paths include data, files, cache,
custom directories and database paths. It repeats through ContextWrapper and
uses only fixture values. Assembly, signatures and source review do not prove
ART execution or Google account authentication.

The focused checker passed transformation, malformed-input rejection and
three-class DEX assembly. The combined builder selftest and exact full-profile
DEX roundtrip passed. The signed fixture passed APK signature verification and
DEX inspection. Independent review covered the factory's registers, storage
flags, fresh caches, wrapper delegation and fixture assertions.

Sealed artifacts live below `/Users/alex/.local/state/vinix/android/`:

| Bundle | Inventory SHA-256 |
| --- | --- |
| `combined-account-webview-credential-storage-framework-2026-10-27-r1/sha256.json` | `cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691` |
| `credential-storage-fixture-2026-10-27-r1/sha256.json` | `cfb17c0567dc7901d082f727e777c986c351a559126b53b5db8322cd027044d6` |
| `credential-storage-run-2026-10-27-r1/sha256.txt` | `f15a4cac8d4a91701794b671e84b41b2cae4fa30ff549a3007558ad345486862` |

The framework JAR SHA-256 is
`9b894cc92c5d3d0e871b5389285b09b107d49cd5c4493fcc2449f3510f961352`;
its DEX is `b96a441b6eca36e0a6fa7a6da01d9e4508136e64ec0f0f3850cf15e2d90ff132`.
The sequential producer took 61.16 seconds, peaked at 494,059,520 bytes
resident and recorded zero swaps. It uses the source revision stated above.

The runner retains both historical strict profiles and adds the explicit
`--credential-storage` profile. It pins the new APKs and framework, and requires
the exact extended pass marker. Its host selftest rejects 59 malformed and
cross-profile cases. The static ARM runner SHA-256 is
`74cc1fb3721c400d4a64d5c7e0c9fb095b0404aa9eed927cbfb6ace06774cb46`;
its retained source is
`fda7c13c1b1cc90665fbd5d85f38c1fc645ee79b64b614838e095e1e2ed962e6`.
The ARM build took 1.87 seconds, peaked at 367,362,048 bytes resident and
recorded zero swaps.

After transferring the three pinned files to a root-protected guest input
directory and admitting the runtime with the existing controller's read-only
W^X mount policy, run with a fresh output directory and an unused, provisioned
fixture principal:

```sh
/var/lib/credential-storage-input-r1/run --credential-storage \
  /opt/vinix-android-aarch64 \
  /var/lib/credential-storage-input-r1/client.apk \
  /var/lib/credential-storage-input-r1/disabled.apk \
  10117 10117 /var/lib/credential-storage-result-r1
```

The runner preserves bounded startup/shutdown and log limits, live input,
permanent identity drop, explicit environment and descriptor closure, exact
success/error checks, and owned process-group cleanup.

The closed `maps-context-storage-vm-r1` run passed this fixture on ARM. Its
intact selected export verifies against SHA-256
`a913fb7fed52bac6a3123c16d1e69d8869801ba38e19076d532ede215543e423`
with zero removals: 18,791 bytes, 37 chunks and two entries. The public receipt
records profile `credential-storage`, UID/GID 10117, wait status 0, exact
PASS/READY checks, drained EOF and unchanged pinned framework/APKs/runner.
The plain UART pass marker includes `credential-context`.

In the same run, Play Services exposed missing `BroadcastReceiver.setResultCode(int)` and
exited. This proves the generic fixture's ART execution; Google account flow
remains unverified. The [closed runtime report](maps-context-storage-runtime-validation-2026-10-27.md)
retains the strict Maps collection failure separately from verified diagnostic
exports and identifies the complete original input closure.
