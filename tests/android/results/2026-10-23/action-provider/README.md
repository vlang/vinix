The same signed standalone APK fails with missing `android.view.ActionProvider` on framework243 and passes on framework244, with native236 unchanged. The only framework source changes are the new generator and its hook in `framework_classes.v`.

The probe checks ActionProvider defaults and virtual factory dispatch, visibility predicate gates, listener replacement/removal, both subUI states and reset. Real MenuItem calls check provider identity, same/different/null replacement, old-provider reset and clearing an old direct action view. Real popup Buttons are found through the Dialog view tree and clicked with `View.performClick()`: callback order is item listener, PopupMenu listener, then provider default action, stopping when handled. This standalone app has no prior startup probes and sends no QMP input.

The fixed app reaches PASS and READY and stays alive for the full 120-second observation window. Its raw harness result remains `startup_failed` because native236 carries inherited Maps-only diagnostics that print and clear a missing `Main.nge/bB` field/class exception. The validator allows exactly those two markers and rejects an app assertion, WS-FAIL or exit.

Menu integration is limited to provider retention/reset and popup default-action fallback. Provider-created action-view caching, menu visibility/submenu integration and clearing a provider from direct `setActionView` are not implemented by this change. No rendering or navigation claim follows from this fixture.

Validate retained evidence without a guest or build artifacts:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/action-provider/validate.v
```

The permanent fixture generator is `tests/native-android-ws/action-provider-fixture.v`; its OUTPUT argument generates and signs the APK with the local Android toolchain and fixture key referenced by the source. The retained prepare helper pins separate baseline/fixed native directories and the shared fixture VM. Exact framework/native source snapshots, actual signed/framework DEX, staged hashes, raw results and screenshots identify the executed inputs. APK and runtime binaries are identified by SHA256 rather than committed. The class contract follows [AOSP Android 15 ActionProvider](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r5/core/java/android/view/ActionProvider.java).
