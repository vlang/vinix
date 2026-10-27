# Component direct boot metadata regression

The explicit service resolver exposed a missing Android API field during real
Play Services startup: `ServiceInfo.directBootAware` could not be resolved on
the class or its superclasses. The field belongs to `ComponentInfo`; declaring
it there preserves inheritance for activities, receivers, services and providers.

`framework_direct_boot.v` adds the public boolean field with its false VM
default and preserves it in the `ComponentInfo` copy constructor. PackageParser
reads canonical attribute `0x01010505` through a one-attribute TypedArray,
including boolean resource references, with a false default. Activity aliases
copy the target activity's value. This follows the Android 10 implementations of
[ComponentInfo](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r47/core/java/android/content/pm/ComponentInfo.java)
and [PackageParser](https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/android-10.0.0_r47/core/java/android/content/pm/PackageParser.java).

The maintained `--direct-boot` combined framework profile requires the complete
sealed service-query baseline. It preserves all 2104 classes, changes only the
ComponentInfo copy constructor and four PackageParser methods, adds one parser
helper and one field, and preserves other methods and non-DEX JAR members.
The focused checker rejects malformed or previously patched input and can
assemble the two changed classes independently.

The signed generic fixture extends explicit service queries with literal true,
resource true, resource false and omitted defaults; inherited field resolution
through ServiceInfo; ServiceInfo and ComponentInfo copies; and metadata-only
disabled companion activities, receivers, providers and aliases. It repeats
checks through ContextWrapper and retains constructor traps for unintended
service or companion Application startup. It does not use Google accounts or
network authentication. Assembly and fixture generation alone do not establish
ART execution or Google sign-in success.

Validation used source commit `96b4bafdd` (producer revision
`b8af133695a68450cd10d9e5b72ad13c4e1b363f`, which includes it). The focused
checker passed transformation and malformed-input checks and assembled the two
changed classes. The combined builder selftest passed; the complete producer
then checked the exact class/method/field delta and repeated it after DEX
roundtrip. The signed fixture passed APK signature verification and DEX/manifest
inspection. Independent source review covered register lifetimes, alias
inheritance, fixture coverage and the runner's profile selection and isolation.

Sealed artifacts live below `/Users/alex/.local/state/vinix/android/`:

| Bundle | Inventory SHA-256 |
| --- | --- |
| `combined-account-webview-direct-boot-framework-2026-10-27-r1/sha256.json` | `a3445b78a7c4049fa71ee0f81469dca7da2236c36788500cd8bd3c8bb0b81552` |
| `direct-boot-fixture-2026-10-27-r1/sha256.json` | `12dfc238b637266100e8545b67ba263d91c9bf477fbdfcb14df337dae07d2cfa` |
| `direct-boot-run-2026-10-27-r1/sha256.txt` | `a50a5fb47353dd58543032d0e97daa32d5bab6d52df46ff8abccf7340b1b8bda` |

The framework JAR SHA-256 is
`bf3853c98155e420162dc8d1759735a497e8d8bb9724cd9eb7f209c4edb04c0d`;
its DEX is `3742f3915d4989ced425914e1fe4f6f662bd32566183534a849f8ad8ccd07213`.
The sequential framework producer took 158.02 seconds, peaked at 492,257,280
bytes resident and recorded zero swaps. This avoids a full runtime/kernel
rebuild for the focused compatibility change.

`service-query-run.v` retains its original default profile and adds an explicit
`--direct-boot` profile with immutable enhanced APK/JAR pins and the longer
exact pass marker. Its host selftest rejects 40 malformed or cross-profile
cases. The static ARM runner SHA-256 is
`8caab5559b73dbe1ffc9645006e899fd82dfbe5cfac810df4f189db9eb152a60`;
the retained source SHA-256 is
`4645c01c0594af3ee29729f1f650d5d13872936e3d0de4b70040d705f4f0a264`.
After transferring the three pinned files to a root-protected guest input
directory and admitting the runtime with the existing controller's read-only
W^X mount policy, run with a fresh output directory and an unused, provisioned
fixture principal:

```sh
/var/lib/direct-boot-input-r1/run --direct-boot \
  /opt/vinix-android-aarch64 \
  /var/lib/direct-boot-input-r1/client.apk \
  /var/lib/direct-boot-input-r1/disabled.apk \
  10117 10117 /var/lib/direct-boot-result-r1
```

The runner keeps its bounded live-input/EOF protocol, permanent identity drop,
explicit environment and descriptor closure, exact success/error checks and
owned process-group cleanup. The guest ART run and subsequent Maps account
flow remain pending; these build receipts establish no authentication result.
