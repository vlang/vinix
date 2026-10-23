The same signed APK calls TextureView.setTransform(Matrix) on framework235 and
framework236, using the identical native235 library. The baseline reproduces
the missing setter found in Maps after the native235 interpolator checks pass.

The fixture checks nine matrix values, including perspective; copying the input
on initial and replacement sets; isolation from mutated getter outputs; supplied
output identity and fresh null outputs; per-view state and both existing
constructors; null resets; and invalidation. It also draws a 4x4 background and
checks every pixel and the View geometry after setting a content transform.
The backend continues to report no available texture surface.

All earlier startup, interpolation and accessibility checks remain enabled.
Raw outcomes, exact source archives, signed-APK DEX, staged binary identities
and screenshots are retained. The fixed run must reach its PASS marker and
READY and stay alive. Its raw harness result is qualified by the two inherited
Maps-only diagnostics for the fixture's missing nge/bB field; the validator
rejects application failures or assertions. This proof does not claim that a
video or texture surface is rendered.

Validate retained evidence from the repository root:

```
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/texture-transform/validate.v
```

The fixture generator is `tests/native-android-ws/startupfixture/texture_transforms.v`.
The retained prepare/build helpers document the source snapshot and signed APK.
The build helper imports that snapshot with
`-path '/Users/alex/code/vinix/build/android-maps/texture236/source|@vlib'`.
