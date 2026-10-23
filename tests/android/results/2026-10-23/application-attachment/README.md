# Application attachment publication

`ATLLoadedApp` stores its Application before calling `attachBaseContext`. Its
cached getter previously returned that object without taking the existing
initialization lock, allowing another thread to use a partially attached app.
The getter now takes that lock on every call. Same-thread attachment callbacks
can reenter; the lock is released before provider initialization and
`Application.onCreate`.

The same signed companion/service APKs and native204 library ran in both native
WS guests:

| Framework | Result |
| --- | --- |
| framework217-observer2 | `startup_failed`: competing getter escaped incomplete attachment |
| framework-attachment221 | `window_observed`: attachment race passed; no WS failure or assertion |

The fixture holds attachment open until it observes a competing getter blocked
at `getApplicationUnsafe`, then completes attachment. It checks owner reentry
and initialized state, and joins the worker inside `Application.onCreate` to
verify that ordinary getters can proceed during that callback. Earlier intent,
geofence, location, account and SQLite fixture checks also pass in the fixed log.

`receipt.json` records the exact input framework/APK/native-library/harness
hashes and retained artifact hashes. `sources.json.gz` contains exact extension
source snapshots, fixture Smali and both generated `ATLLoadedApp` classes.
`validate.v` checks the retained evidence and hashes; `build.v` and `run.v`
record the commands used. Large runtime/APK/JAR files remain under
`build/android-maps`. The private boot, efivars and native staging copies were
removed after the completed tests to recover disk space. Re-running requires
recreating those private copies from the runtime and an idle boot image first.
No pre-run boot/kernel or per-run guest binary hashes were captured; their
identity is not asserted by this receipt.

This verifies the framework race. Google Maps startup and map display require
separate end-to-end validation.
