# Stable display native bridge: host checks

The native `DisplayManager.getStableDisplaySize()` bridge queries `/dev/fb0`
with `O_RDONLY | O_CLOEXEC` and `FBIOGET_VSCREENINFO` (`0x4600`). It supplies the
complete 160-byte Linux UAPI buffer, closes the descriptor once on every opened
path, and constructs a fresh `Point` from positive signed pixel dimensions.
Unavailable or invalid geometry produces `(0,0)`. JNI lookup/construction errors
retain their original exception and release the local class reference.

[AOSP DisplayManagerService](https://android.googlesource.com/platform/frameworks/base/+/597a3da445c5/services/core/java/com/android/server/display/DisplayManagerService.java)
returns a fresh empty Point when stable dimensions are unavailable and treats
stable size as a device property. Using current framebuffer geometry is limited
to this fixed-mode, single-framebuffer guest. This change establishes no dynamic
mode, rotation, or multiple-display behavior. It does not read or map pixels,
change device permissions, or change `Display`, `Point`, or app-window metrics.

Source parent: `a54bdfd40b43aa5bb5bd3fd514ba526857e61967`. Tested source hashes:

- `stable_display.v`: `615914b95158b22a6ba0a941465f9ce4f3448cb16260aa77fc7632ee679bf5c8`
- `bindings.txt`: `76f62e0ceefb04f147856b711cce651380841027ee3d3fd70e4bc9787b956d60`
- `check-stable-display-native.v`: `a427ce7c4a65deb9d35454d9def787c5b8ae10745467f7366fd048e475b0e95c`

The host probe executes the production geometry/JNI bodies with deterministic
syscall and JNI tables. It checks ABI sizes/offsets, all 160 output bytes,
read-only and close-on-exec flags, fd zero, open/ioctl/geometry failures, signed
bounds, close failure without retries, 1,000 descriptor lifetimes, fresh Points,
and pending-exception/class-reference cleanup. All six negative controls were
detected: missing close, writable open, missing close-on-exec, fd-zero rejection,
ignored ioctl failure, and unchecked dimension overflow.

Evidence is retained outside Git:

- `~/.local/state/vinix/android/stable-display-native-check-2026-11-02-r2`
  (PASS receipt `eac5cb1100412bb3ac718ee265c97f2f78bc8e38a861900576e44759777c0c92`).
- `~/.local/state/vinix/android/stable-display-native-check-2026-11-02-r1`
  preserves the rejected checker extraction attempt.
- `~/.local/state/vinix/android/stable-display-native-controls-2026-11-02-r1`
  preserves all guards, generated projects, logs and earlier compile failures.

The initial combined compile exceeded the unchanged 600 MiB aggregate guard and
was stopped cleanly. Separate serial V project generation and its emitted
Makefile build passed. The final host run passed in 5.038 seconds, sampled
392,675,328 bytes aggregate RSS, with 297,107,456 bytes detailed maximum RSS,
zero process swaps, 16,035,840 bytes observed volume growth and complete cleanup.
The 600 MiB, 300-second, 512 MiB growth, 1 GiB reserve and file/output caps stayed
in force. Coupled ARM library production and guest validation are separate.
