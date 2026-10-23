The same signed regression APK first reproduces the null interpolator loader on
framework228. The XML resources are compiled by aapt2 and loaded through the
public AnimationUtils API. Numerical samples use an independent double-precision
Bezier oracle, including the four Material progress curves found in Maps.

Coverage includes all ten XML tags, nondefault scalar attributes, quadratic and
pathData curves, endpoints and clamping, a legal vertical path segment, legal
control points outside the unit square, reversing or discontinuous paths,
unknown XML, missing resources, repeated loads, and parser cleanup after success
and failure. A parser proxy counts closes and unwraps its concrete XmlBlock
parser only for native typed-attribute lookup. This probe uses a null theme.
The numerical assertion rejects NaN as well as excessive error.

The retained receipt records the exact APK, framework and native library hashes,
staged runtime identities, source archives, generated DEX, compiled XML dumps,
raw harness outcomes, and logs. The initial framework234 failure is retained
separately: its normalized pathData curve exposed insufficient native path
sampling precision after the four Maps curves and scalar cases had passed.
The final run keeps framework234 unchanged and substitutes native235, with only
the four reviewed path-precision source files changed from native233. The APK
remains identical in all three runs. This regression proof does not establish
Maps functional behavior.

The copied host receipt links the same four precision source hashes to the
normal and AddressSanitizer ownership and numerical checks retained in
`../path-precision/`.

The final fixture reaches its PASS marker and READY and remains alive. Its raw
harness outcome is still `startup_failed` because the inherited Maps-only native
diagnostic prints and clears a missing `nge`/`bB` field error against the fixture
Main class. The two exact diagnostic markers are retained; application
`ANDROID-WS-FAIL` or numerical assertion failures are rejected by the validator.

Run the retained evidence validator from the repository root:

```
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/interpolators/validate.v
```

The permanent generator is
`tests/native-android-ws/startupfixture/interpolators.v`; its install and runtime
checks are part of the normal startup fixture. The retained build helper and
configurations document the frozen signed APK used for the comparison.
