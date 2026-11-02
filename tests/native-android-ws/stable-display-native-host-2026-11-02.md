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

Source parent: `7ccb4c5f685b2097831a246ef1f0fa79a16f22eb`. Tested source hashes:

- `stable_display.v`: `8d8e8f2e81c6b0b4cd6a11648c59184dff1269c97ab7b0a636a4ef8cd517a6d8`
- `bindings.txt`: `76f62e0ceefb04f147856b711cce651380841027ee3d3fd70e4bc9787b956d60`
- `check-stable-display-native.v`: `00e6e4d759ea0040d9bfcf64385a6a6f8c7d9ae5f4454ed7f6a908e576858d36`

The host probe executes the production geometry/JNI bodies with deterministic
syscall and JNI tables. It checks ABI sizes/offsets, all 160 output bytes,
read-only and close-on-exec flags, fd zero, open/ioctl/geometry failures, signed
bounds, close failure without retries, 1,000 descriptor lifetimes, fresh Points,
and pending-exception/class-reference cleanup. All six negative controls were
detected: missing close, writable open, missing close-on-exec, fd-zero rejection,
ignored ioctl failure, and unchecked dimension overflow.

Evidence is retained outside Git:

- `~/.local/state/vinix/android/stable-display-native-check-2026-11-02-r3`
  (PASS receipt `7e44cd62b2ed38d0ffa788c72d8635fe9aef984725a5ab41e0a8d22d98726016`).
- `~/.local/state/vinix/android/stable-display-native-check-2026-11-02-r2`
  preserves the initial successful host probe before the ARM codegen fix.
- `~/.local/state/vinix/android/stable-display-native-check-2026-11-02-r1`
  preserves the rejected checker extraction attempt.
- `~/.local/state/vinix/android/stable-display-native-controls-2026-11-02-r1`
  preserves all guards, generated projects, logs and earlier compile failures.

The initial combined compile exceeded the unchanged 600 MiB aggregate guard and
was stopped cleanly. Separate serial V project generation and its emitted
Makefile build passed. The final host run passed in 1.749 seconds, sampled
117,637,120 bytes aggregate RSS, with 101,056,512 bytes detailed maximum RSS,
zero process swaps, 3,526,656 bytes observed volume growth and complete cleanup.
The 600 MiB, 300-second, 512 MiB growth, 1 GiB reserve and file/output caps stayed
in force. The first coupled ARM compile rejected the old compiler's generated
`memdup` for an addressed fixed JNI argument array. The complete rejected
`current-native-build-2026-11-02-stable-display-r1` is preserved. Arguments now
use explicit stack storage consumed synchronously by JNI, and the exact-source
host checks were repeated. Coupled ARM production and guest validation remain
separate from these host results.
