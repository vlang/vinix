# APK Activity declaration verifier

`accountmanifest.verify_activity(apk, expected_package, expected_class)!` reads
the complete binary Android manifest and requires a direct
`manifest/application/activity` declaration. The manifest package must match
exactly. The Activity's `name` attribute must use the exact Android namespace
URI and a literal class name; relative and package-local class names follow
Android component naming rules. An `activity-alias`, foreign namespace, textual
substring or declaration outside the application does not authorize launch.

The caller must authenticate the APK, certificate and installed package first.
This verifier does not check signatures, enabled/exported state, permissions or
whether the declared class exists in DEX. It reads a unique root
`AndroidManifest.xml` ZIP entry without extracting archive paths and validates
its CRC. Limits are 1 GiB APK, 65,536 ZIP entries and string pool entries,
4 MiB manifest, 16 MiB each for decoded strings and attribute names,
256 element/namespace nesting and
4,096 attributes per element. Styled string pools are rejected.

Host regression tests include UTF-8 and UTF-16 pools, compressed and stored
ZIPs, exact namespace/package/class matching, aliases, malformed references,
surrogates, duplicate entries/attributes/Activities, CRC failures and every
truncation of a complete manifest:

```sh
v -cc /usr/bin/cc test build-support/android/accountmanifest
v -path 'build-support/android|@vlib|@vmodules' -o /tmp/account-manifest-verify tests/android-account-manifest/verify.v
/tmp/account-manifest-verify /path/to/installed.apk com.google.android.gms fully.qualified.Activity
```

Generated binaries and APK evidence belong in an external state directory.
