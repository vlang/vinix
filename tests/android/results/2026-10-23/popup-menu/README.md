The same signed standalone APK fails at the unimplemented `PopupMenu.native_init()` on framework242/native235 and passes on framework243/native236. Both components change together: the new native menu resource lookup reads the new `VinixMenu.vinixContext` field. The framework delta is the PopupMenu generator, its hook, and ATL `menus.v`; the native delta is only `menus.v`.

The probe uses real compiled menu XML and checks constructor Context resource access, nested resource titles/icons, Activity-owned resource fallback, hidden/disabled/checked items, submenu navigation, item-listener precedence/fallback, repeated show/dismiss, callback reentry and stale captured buttons. A real guest mouse click on the visible final leaf must produce its callback and the eighth delayed dismissal before the final PASS. This is a standalone app with no previous startup probes.

The original signed test also called the preexisting unsupported `MenuItem.getIcon()` and failed with `AbstractMethodError` on the fixed runtime. Its source, APK identity, both raw runs and staged identities remain under `rejected-get-icon/`. The final probe inspects the existing stored icon field instead; it does not add a getter API.

The fixed app remains alive for the full 180-second observation window and reaches READY. The harness raw result is still `startup_failed`: native235 and native236 carry inherited Maps-only diagnostics which print and clear a missing `Main.nge/bB` field/class exception. Exactly those two failure markers are allowed; an application WS-FAIL, assertion or process exit fails validation. Popup presentation is the documented centered Dialog fallback; anchored placement and outside-click dismissal are not covered.

Validate retained text evidence without a VM or build artifacts:

```sh
/Users/alex/code/v/v_old -nocache -cc cc run tests/android/results/2026-10-23/popup-menu/validate.v
```

The permanent fixture generator is `tests/native-android-ws/popup-menu-fixture.v`. Generate/sign with its OUTPUT argument using the local Android toolchain and fixture signing key referenced by the source. The retained prepare helper pins both runtime pairs and an independent fixture VM. `interact.v capture`, then `interact.v click X Y`, capture the actual visible guest state and send mouse input through that fixture's QMP socket. Retained source snapshots, actual signed/framework DEX, compiled XML dump, staged hashes, helpers, logs and screenshots document the executed inputs. APK and runtime binaries are identified by SHA256 rather than committed.
