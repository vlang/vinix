The native render loop now checks for a pending Java exception before dispatching input. A rendering failure proceeds directly to the existing exception reporter and exit path, preserving the original exception without making forbidden JNI calls from input hit testing.

The same signed negative-test APK and framework were booted against immutable native228 and native230. Their 81-file native snapshots differ only in the render-to-input guard in `runtime.v`. The fixture presents one frame while the host positions the pointer, then pauses its next `onDraw` while the host queues only a button press. That `onDraw` throws `IllegalStateException: expected queued-input render failure`.

| Run | Observed result |
| --- | --- |
| Baseline228 | Original Java exception followed by `JNI NewLocalRef called with pending exception`, `in call to NewLocalRef`, fatal SIGABRT and ART `HandleUnexpectedSignal reentered`. The launcher records exit1. |
| Guarded230 | `ANDROID-WS-FAIL input or render`, the original Java exception and its `DrawFailureView.onDraw` stack, then launcher exit1. No fatal JNI diagnostic, SIGABRT, signal-handler reentry or touch callback. |

Both raw harness outcomes are intentionally `startup_failed`; this regression validates failure reporting, not successful application startup. The identical exit codes do not establish the fix: the retained serial traces establish that the guarded run avoids the secondary JNI fatal. Both input logs record pointer positioning and a separately queued button-down during the throwing draw callback. Inherited Maps-only native diagnostics can print and clear unrelated missing `nge`/`Main.bB` lookups before this test; they are retained unchanged.

The first exploratory fixture queued a complete click, whose initial pointer movement was consumed before the button press. It therefore exited through the ordinary exception path without reproducing the JNI failure. A later staging retry failed before boot because an extracted `/sbin/init` symlink could not be overwritten, and its interactor saw an old serial log. These were test/harness setup issues. The final runner removes its previous output before each paired run; only the corrected, matching APK pair is evidence for the guard.

`identities.json` records the actual staged libraries, framework, launcher, desktop/session and native guest identities, the signed APK/DEX identities, build-tool hashes and retained artifact hashes. The native source archives contain 81 exact sources per build; the framework archive contains 104 exact sources. Kernel/base identities are inherited: no preboot kernel/shared-image hash was captured for these fixture runs. `fixture-inputs` contains the public test-signing key, resource/manifest template and three support smali files consumed by `fixture.v`.

JNI permits only a limited set of functions with an exception pending; `NewLocalRef` is outside that set. `ExceptionCheck`, the existing reporter's `ExceptionDescribe`, and frame cleanup are allowed. `ExceptionDescribe` prints and clears the pending exception. See [Android JNI tips](https://developer.android.com/ndk/guides/jni-tips#exceptions) and the [JNI function specification](https://docs.oracle.com/en/java/javase/11/docs/specs/jni/functions.html#exceptiondescribe).

Run the self-contained retained validator from the repository root:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/render-exception/validate.v
```

The retained `prepare.v`, `run.v`, `interact.v`, `fixture.v` and native builder show the original guest workflow. Guest reproduction also needs the runtime/tool binaries identified in the receipt and the shared VM paths in the configurations.
