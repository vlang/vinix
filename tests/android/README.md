# Android calculator smoke test

Build the Android runtime and sample APK, then build the desktop and kernel:

```sh
./build-android-aarch64.sh --with-calculator
./build-desktop-aarch64.sh --no-initramfs
make -C kernel ARCH=aarch64 CC=clang LIMINE_MP=1
python3 tests/android/run.py
```

The test starts a separate Vinix QEMU guest with a private boot disk, EFI
variables, package store and kernel snapshot. It uses the existing Alpine
minirootfs with the Android runtime, X11 and the desktop under test. The test
assembles a compact initramfs and deduplicates library aliases as hardlinks.
It never writes the normal desktop's persistent volume.

The native desktop opens **Android Calculator**. The test waits for the actual
APK's X11 window to draw, clicks its input field, sends `123+456` through QEMU's
keyboard, and requires the APK to display `579`. It waits for the actual input
text to acknowledge each character and bounds retries for dropped key events.
A test-only preload library observes GTK and Pango text calls to verify the
input and result; it leaves the APK and runtime behavior intact.
QMP captures the guest framebuffer as `build/android-smoke/calculator.png`.
`serial.log` retains startup diagnostics and `result.json` records the verdict.
A failed test also attempts to capture the screen.

Useful options:

```sh
python3 tests/android/run.py --desktop /path/to/vinix-desktop \
    --kernel-dir /path/to/kernel --state-dir /tmp/vinix-android-test
python3 tests/android/run.py --apk /path/to/calculator.apk \
    --activity calculator/Calculator --keys '123+456' --expect 579
./build-desktop-aarch64.sh --compact-initramfs --with-android
python3 tests/android/run.py --initramfs build-support/init-aarch64/initramfs-desktop.tar \
    --memory 12288
```

`--initramfs` selects another base image, with the test files added as a boot
overlay. Its existing X11 and libraries are retained for production image
verification. `--runtime` selects another staged Android layer; `--runtime-arch
x86_64` compiles the result observer for an x86 runtime translated by QEMU.
`--mode direct` brings up the same APK on the X11 bridge before
desktop integration, sends XTEST keyboard input, and displays its real pixels
on fbdev for a QMP screenshot. The normal desktop test exercises compositor
keyboard forwarding. The host needs `aarch64-linux-musl-gcc` and Python Pillow.
The default translated runtime also needs `x86_64-linux-musl-gcc` for its
test-only observers. Before launching the APK, the test checks mapped stack
bounds, worker stack guards and ART's memory mapping prerequisites in the real
guest. `--strace` adds translated runtime syscall diagnostics.
`--click X Y` changes the desktop screen position clicked before typing;
`--focus X Y` changes the APK window position clicked in direct mode.

For bring-up of another APK, capture its actual window and startup diagnostics
without the calculator observer or simulated input:

```sh
python3 tests/android/run.py --apk /path/to/application.apk \
    --activity package/Activity --title package --observe \
    --mode direct --state-dir /tmp/vinix-apk-observation
```

`--observe` requires a painted APK window to remain visible for 30 seconds
(`--observation-seconds` changes this duration). It captures `application.png`
and records `observed: true` with `passed: null` in `result.json`; this only
establishes that a window was observed, not that the application's functionality
works. Startup failures retain a screenshot where possible, diagnostic logs
and an explicit failure reason. A proprietary APK must be supplied locally;
the harness does not modify or redistribute it.
