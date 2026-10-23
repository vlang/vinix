Animation path precision, 2026-10-23

The actual native path functions pass numerical and lifetime checks both normally
and under AddressSanitizer. Cubic and quadratic curves match an independent
double-precision oracle within 0.001 at 99 interior x samples. The original cubic
still has five renderer vertices; animation independently refines retained spans
to a 0.00025 chord-deviation threshold with recursion capped at 16.

Checks cover Java-owned snapshots after source release, copied paths, appending
into a nonempty builder, repeated self-add across reallocation, reset/unref,
affine control transforms, the inherited projective polygon approximation,
contour jumps and normalized arc length. Every snapshot native allocation fails
in turn; metadata allocation/reallocation and JNI array failures also release all
owned storage. Nonfinite source coordinates fail explicitly.

The harness compiles extracted production functions. Only allocators and JNI
array creation/copy are replaced; the checked allocators call real C allocation
functions and assert zero remaining production allocations. ASAN leak detection
is disabled for unmanaged V harness strings; exact production allocation
accounting remains enabled. The receipt hashes six production inputs and the
runner/harness, all retained in `sources.json.gz`.

Run from the repository root:

```
v run tests/native-android-ws/path-precision-host.v
v run tests/native-android-ws/path-precision-host.v asan=true out=build/android-path-precision-asan
v run tests/android/results/2026-10-23/path-precision/validate.v
```

The compiled-XML Android regression, including the original failed coarse-path
run and the unchanged signed APK replay, is retained in [interpolators](../interpolators/README.md).
