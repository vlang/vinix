# Protected storage guest regression

`protected-storage-fixture.v` builds a signed regression APK from the retained
bootstrap fixture. It uses direct field reads and actual Context methods to
check `ApplicationInfo` protected directories, null-preserving copies,
Application/Activity metadata identity, PackageManager metadata, CE/DE flags,
file/cache/custom/database paths and committed, isolated preferences. Nested
wrappers, configuration contexts and same-package contexts are included.
The expected device directory is exactly `dataDir/device_protected`.

Vinix provides distinct subdirectories inside the application's private root.
This regression does not assert separate encryption keys or unlock states and
does not use Google accounts or network services.

Build with one compiler at a time, writing results outside the repository:

```sh
v -o /absolute/external/storage-builder tests/native-android-ws/protected-storage-fixture.v
/absolute/external/storage-builder /absolute/external/fresh-output \
  build/android-whatsapp/fixture build/android-framework/tools \
  /absolute/path/to/java build/android-native-ws/android-15/lib/apksigner.jar
```

Java heap is capped at 512 MiB; smali and baksmali use two jobs. The builder
records command arrays, source/executable/input hashes, APK signatures and a
SHA-256 inventory. `--smali-check OUTPUT SMALI_TOOLS JAVA` checks generation
and DEX roundtrip without requiring the bootstrap APK.

For a guest run, stage only `probe.apk` into the existing private runtime's
readable test directory. After deploying the matching framework and JNI
library, use an existing V controller to fork the launcher with a WS stdin
pipe, fresh writable application data and home directories, and an absolute
surface path in that data directory:

```text
VINIX_ANDROID_ROOT=/opt/vinix-android-aarch64
ANDROID_APP_DATA_DIR=/absolute/fresh/storage-data
VINIX_ANDROID_HOME=/absolute/fresh/storage-home
VINIX_SURFACE_PATH=/absolute/fresh/storage-data/probe.surface
argv: /opt/vinix-android-aarch64/usr/bin/run-android
      /opt/android-test/protected-storage.apk -l org.vinix.bootstrap.Main -w 64 -h 64
```

When using explicit UID/GID launch, both directories must be owned by that
existing identity and the private loader mount must already admit W+X; see
`build-support/android/nativeidentity/README.md`. No account registry, account
socket or browser broker is needed. Keep the pipe writer open until the
following marker appears in captured stdout, then close it for normal shutdown:

```text
PROTECTED-STORAGE-PASS direct-fields copy-null metadata paths preferences wrapper configuration package-context
```

Host validation on 2026-10-27 used source base
`2045b466e2a032586a699d67379be3daec61dc15` plus the fixture source retained in the bundle.
Pinned V compilation, smali assembly (empty diagnostics), DEX roundtrip and
APK v1/v2/v3 signature verification passed. Guest ART execution is pending.
Bundle: `/Users/alex/.local/state/vinix/android/protected-storage-fixture-2026-10-27-r1`
(2.2 MiB). APK: 17,031 bytes, SHA-256
`786681da81d8b075e38f844014ab767e26f4388bfb5f8bf62e4cd380c978f0e6`.
The bundle's `sha256.json` has SHA-256
`82cdff638c26fc6f662a64fce54165e487169a2a4ee2030275ab86843da9a42f`.
