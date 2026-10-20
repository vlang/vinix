# APK workflow checks, 21 October 2026

These checks run the unchanged F-Droid Editor 1.98 and Open Sudoku 2.5.2 APKs
in an ARM64 Vinix QEMU guest. The V framework extension fixes their framework
failures; the apps still render through GTK and the embedded X11 bridge.
No native Vinix WS backend or phone hardware result is claimed.

`apk-workflows.json` separates inspected functional workflows from the generic
observation runner. An observed window has `passed: null`. The workflow checks
cover editing, saving, clearing and reopening a document, and selecting a
Sudoku puzzle, entering a value by touch in Single number mode, returning to
the list and reopening with progress retained. They do not cover every app
feature; Sudoku's popup tabs and import/export are outside this run.

Screenshots are unmodified QMP framebuffer captures. The test replaces the
APK behind the existing Android Calculator desktop entry, which explains that
outer caption on both apps. Serial logs are retained as gzip files, including
known nonfatal upstream PackageParser, CloseGuard and icon warnings. A missing
method, Java linkage error or JNI abort during the checked workflow is a
failure, even if the last frame still contains app pixels.

The preserved 3 October runtime failed the newer fork ABI preflight in the
20 October check. This application driver deliberately keeps the stack and
memory probes and records its narrower scope. Full runtime conformance is not
established. The maintained runtime build installs the extension automatically;
use matching freshly built overlays for `tests/android/run` with every normal
preflight enabled.

For the exact preserved-runtime investigation, use the prepared overlays from
the preceding run and the original, unextended ATL framework JAR. The local
paths used here are `build/android-editor-20261020-prepared/overlay`,
`build/android-opensudoku-20261020-prepared/overlay`, and
`build/android-calculator-20261020-borderless-prepared/overlay`.

```sh
build-support/android/native-tool extend-framework ORIGINAL-API-IMPL.jar \
  build/android-framework/api-impl.jar --java /path/to/java
build-support/android/native-tool compile-framework \
  build/android-framework/libvinix-android-framework.so --cc aarch64-linux-musl-gcc
v -cc cc -o build/android-framework/stage-overlay \
  tests/android/results/2026-10-21/stage-overlay.v
build/android-framework/stage-overlay BASE_OVERLAY WORK_DIR \
  build/android-framework/libvinix-android-framework.so build/android-framework/api-impl.jar
v -cc cc -path '@vlib|@vmodules|./tests/native-android-run' \
  -o build/android-framework/application-driver \
  tests/android/results/2026-10-21/application-driver.v
build/android-framework/application-driver --apk /path/to/Editor-1.98.apk \
  --activity org/billthefarmer/editor/Editor --mode desktop --observe \
  --memory 12288 --timeout 900 --state-dir /path/to/state \
  --initramfs WORK_DIR/initramfs.tar
```

The driver defaults to the archived local runtime and current desktop/kernel;
`--runtime`, `--desktop` and `--kernel-dir` override them. For Sudoku, use
`org/moire/opensudoku/gui/FolderListActivity`. For Arity, omit `--observe` and
the activity override; the runner checks `123+456=579` with per-key
acknowledgements. The new options bar moves its input point to desktop
coordinates `(360,198)`, or `(240,115)` relative to a direct X11 window.

The optional `VINIX_ANDROID_REUSE_BOOT=1` path is specific to this macOS/HVF
investigation. It requires its own stopped, already prepared state directory.
It replaces the FAT disk's base initramfs and starts the same QEMU devices
directly, retaining the existing final guest-init module and kernel. Normal
runs use the maintained boot preparation path.

Use `desktop/tools/input` for clicks and text, and
`tests/native-android-run/run screenshot --socket STATE/qmp.sock --destination FRAME.png`
for captures. Inspect the current frame before choosing coordinates. Dialogs
and layouts move as app state changes. `qmp-keys.v` supplies real QMP key chords
such as Ctrl+A for the save-path field. `retain.v` hashes the inputs, frames,
kernel and framework and compresses the logs; its input workflow verdicts are
authored separately after inspecting the actual actions.

Host checks also passed: the framework transformation guards, 26 runtime
staging cases, and PTY/QMP session lifecycle tests. The ARM64 V library compiles
with `-Wall -Wextra -Werror`, has 64 KiB-aligned LOAD segments and imports no V
heap allocation support.
