# Service lifecycle diagnostics, 2026-10-29

The Binder-identity guest run captured `DiskWriteViolation` through
`Service.attachBaseContext` and `Service.onCreate`, both reaching unconditional
base-framework `System.out.println` diagnostics. These captures establish
unwanted callback I/O; they do not establish the sole cause of broker exit 1.

The method-only provider changes exactly three `android.app.Service` methods:

- `attachBaseContext(Context)` retains the superclass call and return.
- `onCreate()` and `onDestroy()` become empty callbacks, matching
  [AOSP Service](https://android.googlesource.com/platform/frameworks/base/+/HEAD/core/java/android/app/Service.java).

Every other Service byte, its constructor, Context/ContextWrapper constructors,
attachment state and exceptions, StrictMode, and native code stay unchanged.
The normal framework build invokes this provider after service bindings; the
narrow successor can call `framework_service_lifecycle_source(original)`.
Only the canonical retained diagnostic implementations are accepted.

## Focused checks

Artifacts are outside Git under `/Users/alex/.local/state/vinix/android` (`S`).

| Check | Artifact | Seconds | Peak sampled RSS, bytes |
| --- | --- | ---: | ---: |
| Exact provider, 11 rejection controls, before/after API28 DEX roundtrip | `service-lifecycle-checks-2026-10-29-r1/source-r2` | 6.185 | 184,483,840 |
| Signed APK, v3 verification, two-class DEX roundtrip | `service-lifecycle-checks-2026-10-29-r1/fixture-r3` | 5.708 | 82,755,584 |

Both checks passed with zero swaps, complete guard cleanup, and unchanged
600 MiB aggregate RSS, 300 seconds, 512 MiB growth and 1 GiB reserve limits.
The source checker proves constructors and all bytes outside the three methods
unchanged, verifies Context/ContextWrapper and nonempty StrictMode preservation
inputs, tests rejection without filesystem mutation, and exercises the actual
filesystem provider. Independent source reviews found no blocking defect.

The first APK attempt is preserved at `service-lifecycle-fixture-2026-10-29-r1`:
the JVM's `JAVA_TOOL_OPTIONS` banner failed the empty-assembler-diagnostics
assertion. Equivalent 256 MiB heap and two-processor settings now use explicit
JVM arguments. The assertion remains strict. The final fixture uses the existing
`org.vinix.bootstrap/Main` entry; an earlier generator compile predates that
entry correction and did not produce an APK.

Final fixture: `S/service-lifecycle-fixture-2026-10-29-r2/probe.apk`.
SHA-256: `d15082450bbc70efc761ec8403e5544e40a98efe3f0a3d69b75b9d142e25b283`.
Provider SHA-256:
`5117e4a20d30ca738b442aa93de239bba6ef2a67349a1303650f237dca057436`.
Inputs, commands, signature verification and artifact hashes are retained in
the fixture's `build.json` and checker `receipt.json`.

The fixture constructs real Service subclasses under `detectDiskWrites` with
an inline listener. It checks exact policy identity, zero unintended callbacks,
attachment order/base identity, duplicate/null rejection and create/destroy.
A real `FileOutputStream.write` must still notify the listener after stream
construction; the original policy is restored before result reporting.

ARM execution, Maps retry and Google login remain pending. Host assembly and
signature checks do not establish runtime success or broker-exit causality.
