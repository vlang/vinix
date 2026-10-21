# Native WS APK checks, 21 October 2026

Arity 1.1, Editor 1.98 and Open Sudoku 2.5.2 ran unchanged on ARM64 ART inside
Vinix QEMU/HVF with 12 GiB RAM. Their UI uses the V native WS backend. The
guest inspects `/proc/*/maps` and rejects GTK, GDK or X11 libraries, and rejects
Xvnc/Xvfb/embedded X11 host processes. Each retained log includes the real
native backend ready marker and library-map observations.

`apk-workflows.json` records manually verified functional workflows, hashes of
the tested APKs, DEX, native backend, loader, desktop and actual booted kernel,
plus source/header hashes and framebuffer hashes. `retain.v` checks the logs
for linkage/JNI/backend failures and compresses them; it does not infer a
functional pass from a window or produce the applications' results.

The screenshots are unmodified QMP framebuffer captures:

- Arity calculated `123+456=579` after real keyboard input.
- Editor recreated its Activity into Edit mode, accepted `Vinix native WS APK
  test`, saved it through the filename dialog to `Documents/VinixNative.txt`,
  cleared it through New, then reopened Recent. The phrase returned with the
  APK's word count of five.
- Sudoku queried its actual seeded SQLite database (three folders, thirty
  puzzles each), opened Easy's first puzzle, dismissed hints, switched to
  Single number mode, and entered `7` in the blank top-left cell by touch.
  Returning to the puzzle list and reopening retained `7` at row 1, column 1.

The existing Android Calculator launcher slot selects each test APK, which
explains the outer caption on Editor and Sudoku. Android's Back/Menu controls
are app navigation. The desktop supplies the sole window title/close controls.

Sources for the unchanged apps are [Arity](https://code.google.com/archive/p/arity-calculator/),
[Editor 1.98](https://github.com/billthefarmer/editor/tree/v1.98), and
[Open Sudoku 2.5.2](https://gitlab.com/opensudoku/opensudoku/-/tree/2.5.2).
The latter APKs came from F-Droid's `org.billthefarmer.editor_198.apk` and
`org.moire.opensudoku_20180507.apk`; exact APK hashes are in the report.

The [backend instructions](../../../../../build-support/android/nativews/README.md)
describe the maintained build. The isolated investigation used the preserved
3 October private runtime and the previously prepared calculator overlay.
It is not a fresh runtime release qualification: that runtime still fails
the newer `ANDROID-ATFORK-FAIL Android ABI exports` preflight. Known nonfatal
upstream PackageParser/CloseGuard messages remain in the logs. No phone
hardware, Bionic NDK/GLES, popup tabs, advanced editing or full WebView pass is
claimed. Static changelog HTML and native bitmap icons now render without the
previous resource-stream EOF exceptions.

Host checks passed: JNI descriptor widths, overload/name mangling and invalid
descriptor rejection; all 26 runtime staging fixtures; ARM64 desktop build;
and native JNI compilation with `-Wall -Wextra -Werror`. The native library
depends on androidfw, PNG, SQLite and libc, with no GTK/X11 dependency. Its
ELF LOAD segments have 64 KiB alignment.

## Reproducing the preserved-runtime investigation

The V helpers here retain the exact macOS/HVF setup, including local dependency
locations. Run them from the repository root. They use a separate overlay and
boot image under `build/android-native-ws`; stop only that QEMU instance before
updating its disk. They require the preceding run's prepared base, boot disk,
EFI variables and pinned framework tool jars, as named in the helpers. For a
new runtime use the maintained build instead of these archived local inputs.

```sh
build-support/android/native-tool extend-framework ORIGINAL-API-IMPL.jar \
  build/android-framework/api-impl.jar --work build/android-framework/extended
build-support/android/native-tool compile-native-ws \
  build/android-framework/extended/smali PRIVATE_RUNTIME_ROOT build/android-native-ws
v -cc cc -path '@vlib|@vmodules|./desktop/tools' \
  -o build/android-native-ws/build-desktop \
  tests/android/results/2026-10-21/native-ws/build-desktop.v
build/android-native-ws/build-desktop
v -cc cc -o build/android-native-ws/stage \
  tests/android/results/2026-10-21/native-ws/stage.v
build/android-native-ws/stage
v -os linux -arch arm64 -cc aarch64-linux-musl-gcc -gc none -cflags '-static' \
  -o build/android-native-ws/guest tests/native-android-ws/guest.v
```

Preserve the base disk's original `/boot/qemu-runtime.tar` as
`build/android-native-ws/original-qemu-runtime.tar` before the first update.
Compile `prepare-boot.v` and `run-vm.v` here with V. Then, while the private
QEMU is stopped, `prepare-boot desktop sudoku` patches a small final module
with the current native binaries, guest observer and selected unchanged APK.
Use `editor` or `calculator` for the other apps. `run-vm` writes its PID and
starts QEMU with the private boot disk and QMP socket.

`build/android-run` is the compiled `tests/native-android-run` CLI used for QMP
input and screenshot commands only; its legacy X11 application runner is not
used. For example:

```sh
build/android-run input click 350 211 --socket build/android-native-ws/vm/qmp.sock --settle 1
build/android-run input type '123+456' --socket build/android-native-ws/vm/qmp.sock --settle 1
build/android-run screenshot --socket build/android-native-ws/vm/qmp.sock --destination FRAME.png
```

For Editor, Menu → Edit, click the body and type. Save first writes the default
document; Save as opens the filename dialog. `tests/native-android-ws/input.v`
sends bounded QMP key taps, such as twenty Backspaces to replace the initial
filename. Then use New and Recent to verify the file read. For Sudoku, close
the changelog, select Easy and the first preview, dismiss the Welcome and
Popup hints, press Pop to switch to Single number, dismiss its hint, choose
7 and tap the top-left cell. Use Back and reopen the first preview. Inspect
current frames when choosing coordinates; state changes move menu rows.

The guest observer enables neither tracing nor APK mutation itself. The test
sample launcher sets `VINIX_ANDROID_TRACE_TEXT=1` and
`VINIX_ANDROID_TRACE_TREE=1` for evidence; normal production launches do not
log document content or view trees. `retain.v CHECKS.json` hashes final inputs
and captures after authoring the workflow verdicts separately.
