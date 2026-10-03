# Roblox APK on Vinix

The Roblox desktop entry launches the unchanged Android APK through Vinix's
native ARM64 [Android Translation Layer and ART runtime](android.md).
ART executes its Java/DEX splash activity, and the Android native-library
loader attempts to load the APK's ARM64 engine. Roblox compatibility is still
being implemented: the latest actual APK test stops during engine loading at the
missing `mallinfo` allocator statistics API. No Roblox application frame,
authentication or gameplay has been verified on this path.

Build the coherent native Android runtime described in [Android APKs](android.md),
then stage the Roblox launchers and include both layers in the desktop:

```sh
./build-android-aarch64.sh --art-runtime /path/to/desugared-art-runtime \
    --bionic-runtime /path/to/bionic-runtime --atl-runtime /path/to/atl-runtime
./build-roblox-aarch64.sh
./build-desktop-aarch64.sh --compact-initramfs --with-roblox
```

`--with-roblox` includes the shared native Android layer. The Roblox builder
verifies the staged ART, native-library loader and coherent framework receipts,
including their payload hashes, native architecture and 16 KiB page contract.
It stages two small launchers and a manifest which records their hashes and the
shared Android runtime's provenance. The default output is
`build-aarch64-roblox/aarch64/staging`. `VINIX_ANDROID_STAGING` selects the shared
Android layer; `VINIX_ROBLOX_STAGING` selects the Roblox launcher layer when
building the desktop. The builder's `--android-staging` and `--build-dir`
options select those paths explicitly.

Supply a complete genuine Roblox APK containing `lib/arm64-v8a/libroblox.so`
at `$HOME/Roblox.apk` in Vinix, normally `/root/Roblox.apk`. The builder does
not download or bundle the proprietary APK. Open **Roblox** from Start or
Quick Launch, or launch it on an existing X11 display:

```sh
VINIX_ROBLOX_APK=/root/Roblox.apk run-roblox-client
run-roblox /root/Roblox.apk
```

The launcher selects `com/roblox/client/startup/ActivitySplash` and a 1280×720
window. Additional arguments are passed to ATL. App data uses the same
`ANDROID_APP_DATA_DIR` setting as other Android APKs, normally
`$HOME/.local/share/vinix/android`. The APK and its native engine are unchanged.

The tested APK is Roblox **2.738.1397**, `com.roblox.client`, version code 3092,
with SHA256 `bbe00ae306cc251c4ea55b7a932d9c524ecb0d6d9203c2a6161bcf0fae792742`.
The coherent framework supplies `Build.SUPPORTED_64_BIT_ABIS`; the private
native-library loader's fork callbacks resolve its earlier `__register_atfork`
dependency. The real configuration implementation supplies asset-manager
snapshots and screen qualifiers, and checked I/O wrappers supply its fortified Android APIs.
The native engine now requires `mallinfo`, whose live, free and high-water
allocation fields lack a musl implementation. That missing provider prevents
the engine from loading completely. A successful Android calculator test does
not establish Roblox compatibility.

Run the [Android observation harness](../tests/android/README.md) with the actual
APK to retain startup diagnostics and its framebuffer:

```sh
python3 tests/android/run.py --launcher roblox --apk /path/to/Roblox.apk \
    --observe --mode direct --runtime-arg=-X --runtime-arg=-verbose:jni \
    --state-dir /tmp/vinix-roblox-observation
python3 tests/android/run.py --launcher roblox --apk /path/to/Roblox.apk \
    --observe --mode desktop --state-dir /tmp/vinix-roblox-desktop-observation
```

Observation requires an application window to draw and remain visible; a
startup failure is retained as a failed result. Both paths were tested on
3 October 2026 with the APK hash above: Java, configuration and fortified I/O
preflights passed, and the engine startup failed without a painted application
frame. The direct JNI log identifies `mallinfo` as the load failure; the desktop
entry reaches the same later unresolved JNI initialization. Host launcher and
shared-runtime validation checks are in `tests/roblox/launcher-test.py` and
`tests/roblox/build-test.py`.
