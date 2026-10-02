# Android APKs on Vinix

The ARM64 desktop can run APKs with the open source
[Android Translation Layer](https://gitlab.com/android_translation_layer/android_translation_layer).
It uses ART to execute DEX bytecode and translates Android framework calls
into GTK widgets. The x86-64 runtime runs through Vinix's existing QEMU user
translation support in a normal desktop window, with input and pixels carried
by the existing X11 bridge. This gives ART the 4 KiB memory ABI it requires
while the ARM64 kernel continues to use 16 KiB pages.

Stage the runtime and the optional open source Arity calculator, then include
them in an image. The host needs Python 3, curl and `x86_64-linux-musl-gcc`
in addition to the desktop's ARM64 build tools:

```sh
./build-android-aarch64.sh --with-calculator
./build-desktop-aarch64.sh --compact-initramfs --with-android
./run-desktop-aarch64.sh --no-build --mem=8192
```

Open **Android Calculator** from Start or Quick Launch. The sample is the
developer's unchanged Arity 1.1 APK, extracted from its
[official source archive](https://code.google.com/archive/p/arity-calculator/).
Both the archive and the APK are checked against recorded SHA256 hashes.

On an existing X11 display (including a session started with `startx`), launch
another APK with:

```sh
run-android /root/example.apk
run-android /root/example.apk -l com/example/MainActivity -w 480 -h 640
```

`-l` selects an activity using slash-separated names. Other arguments are
passed to Android Translation Layer. App data is stored under
`$XDG_DATA_HOME/vinix/android` (normally `$HOME/.local/share/vinix/android`);
set `ANDROID_APP_DATA_DIR` to choose another directory.

The builder installs a complete, checksum-pinned Alpine x86-64 runtime under
`/opt/vinix-android-x86_64` and a static ARM64 QEMU translator at
`/usr/bin/qemu-x86_64`. Its musl loader, GTK, ART and dependencies stay private
to the APK process. `/usr/share/atl` contains the runtime's Android font map.
`build-support/android/packages.lock.json` records every Alpine package
version and hash; `runtime-manifest.json` preserves provenance.
`--update-lock` explicitly regenerates the package selection from Alpine edge.

A small runtime compatibility library obtains the initial thread's stack
bounds from QEMU's actual target memory mappings. musl's normal 4 KiB `mremap`
probe cannot discover that stack through a 16 KiB host. Worker thread attributes
remain supplied by musl. The library also implements `MAP_32BIT` using real
mappings below 2 GiB, which QEMU's ARM host otherwise does not honor. This
keeps ART's compressed object references valid. ART runs in interpreter mode,
with image compilation and its JIT disabled; QEMU still needs
`VINIX_ALLOW_WX=1` for its translator.

Support is experimental and follows Android Translation Layer's implemented
API subset. Google Play Services, a full Android system image and general APK
compatibility are outside this implementation. Native libraries in an APK must
target `x86_64`. Arity contains only Java/DEX code. Version 1.1 uses the keyboard
for input; click its input field above the history list before typing. Newer
Arity versions use Android APIs and resource qualifiers that this runtime does
not yet implement.

Run the isolated QEMU test after staging the runtime and building the desktop:

```sh
python3 tests/android/run.py
```

The test boots Vinix with private VM state, opens the unchanged APK in the
native desktop, types an expression through QEMU's keyboard, verifies the text
drawn by the Android app, and captures the actual guest framebuffer. Test-only
text observation is supplied through `LD_PRELOAD`; it does not calculate the
answer or change the APK. Logs and the screenshot are retained in
`build/android-smoke`. `--mode=direct` tests ART and X11 without the compositor.
