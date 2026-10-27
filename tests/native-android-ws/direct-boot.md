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
