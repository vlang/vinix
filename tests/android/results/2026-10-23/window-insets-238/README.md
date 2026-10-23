# WindowInsets values and Builder regression

The signed startup APK calls `WindowInsets.Builder` first in the new probe, matching the missing class reached by Maps' window-insets compatibility initialization. It retains all previous startup probes, including the native path-interpolator and TextureView transform checks.

The new probe checks all five legacy setters and getters, scalar edge values, fluent setter identity, component-wise maxima across typed masks, visibility, `WindowInsets` and Builder copies, build snapshot isolation, equality/hash consistency, consume behavior, replacement on live and consumed snapshots, both inset overloads, zero clamping, and four negative-argument failures. Two less obvious assertions follow the retained AOSP implementation: a gesture-only legacy setter leaves the current map consumed, and Builder accepts a mixed IME mask while the public maximum getter rejects it. `hasInsets()` must still see a nonzero IME maximum after the status maximum is overwritten with zero.

The pair uses identical signed APK and native235 runtime binaries with framework236 as baseline and framework238 as fixed. The receipt retains actual DEX, exact generator and fixture sources, staged runtime hashes, raw suite results, serial logs, screenshots, and build helpers. The copied AOSP source documents the behavior used for assertions.

Run the retained checks from the repository root:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/window-insets-238/validate.v
```

The baseline fails at the first Builder allocation with `NoClassDefFoundError`, after the existing interpolator and TextureView checks pass. The fixed framework prints `BOOTSTRAP-WINDOW-INSETS-PASS` and `ANDROID-WS-READY`; the validator also checks survival of all previous distinct startup PASS markers.

The raw fixed harness outcome remains `startup_failed`: the inherited native235 Maps diagnostic prints and clears a `NoSuchFieldError` and its `nge` class cause while inspecting this fixture's Main class. The validator requires exactly those two diagnostic failure markers, a ready backend, no process exit, and no app assertion or `ANDROID-WS-FAIL`. It does not reinterpret the raw outcome as a clean harness pass. This fixture does not establish a Google Maps functional outcome.

This original pair predates the expanded signed-value union and system-overlay regressions. Their later same-APK baseline236/fixed239 replay is retained in `../window-insets/`; this earlier pass does not cover those edge cases.
