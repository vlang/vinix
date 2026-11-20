# Maps account flow: cookie clear completion, 2026-11-20

Continuation of r112, whose first protected Maps launch faulted in the
kernel. The [thread-lookup fix](../kernel-current-thread/README.md) was built
on the deployed kernel source and booted in fresh guests r113, r114 and r117,
staged exactly as r112 (same parent, framework, native, engine, controller and
API inputs). No kernel fault occurred in any of them.

`build/qemu-horizontal` no longer exists in the checkout; these guests use
Homebrew QEMU 11.1.3 (`launch-argv.original.json` keeps the staged argv). It
only lacks horizontal wheel events. Concurrent host writes stopped two
staging attempts (r115, r116) at the 512 MiB shared-growth guard with 80 GiB
free; r117 staged with a 4 GiB growth guard (observed 240 MB).

## r113: sign-in page blocked by cookie removal

Maps rendered onboarding. Sign in opened the account chooser, and Add account
passed GMS PreAddAccount: challenge, FRP snapshot and a real device check-in
(`setCheckinResult done with result=true`). MinuteMaidActivity started, then
its fragment's `onCreateView` called `CookieManager.removeAllCookies`, which
threw `IllegalStateException: WebView cookie removal failed`. The fragment
never created its WebView; the window showed "Checking info..." until the
16-minute broker session ended (receipt status
`bounded-session-ended-no-authentication-claim`).

The engine was healthy: its profile, cookie snapshot database (now opened
through the canonical path) and caches were created between 10:59:20 and
10:59:38, and it left no `last-failure.log`.

Cause: the engine answers op 15 (cookie clear) with op 262
(`cookie_cleared`, added in 88a28c24e), but `browserclient` only treated
`ack`, `cookie_result` and `failure` as a request completion. The reply was
queued as a callback, the read waited out its 30 s deadline and closed the
channel. Fixed in 007f894e4 with a host test that fails without the fix
(`browser completion timed out`).

## r114 and r117: fix deployed, check-in timing

The client library was rebuilt from 007f894e4 with current V and
`aarch64-linux-musl-gcc` (same flags as the account client), SHA256
edae1c1ddb0f11cf32ea9e47eeb92f0c7be117fd13c1d141146112ab6279f1fa, exporting
only the four `vinix_android_browser_*` symbols and needing only `libc.so`.
`VINIX_CURRENT_BROWSER_CLIENT` (066ba54c3) stages it with its deployment pin;
the account controller admitted it in both guests.

Neither run reached MinuteMaid. In both, GMS's PreAddAccount `CheckinHelper`
gave up after 10000 ms (`setCheckinResult done with result=false`) and showed
"Something went wrong / problem communicating with Google servers". In r114
the same forced check-in logged `Checkin Succeeded` just after the timeout,
the pattern r85 recorded. In r117 a second Add account did not start another
PreAddAccount pass before the session ended. The cookie fix therefore still
needs a run whose check-in finishes within GMS's 10 s window.

No account was authenticated; no credentials were entered.

## Evidence

Under `/Users/alex/.local/state/vinix/android/`:

| Item | Location / SHA256 |
| --- | --- |
| r113 serial | maps-current-20261120-r113-account/serial.log, 6061229c1600a625abb22fc909357e76f44db3b3eaa03f3868c28155f41e2712 |
| r114 serial | maps-current-20261120-r114-account/serial.log, 54d7acc398a08b795962a2cb1a6005eb4da657b1e71f47d25e9b76177fcb104c |
| r117 serial | maps-current-20261120-r117-account/serial.log, 48079ea3ee20f232fbb826d6b1dc227c76b6417b8a1ece13b74cb1de98db81c3 |
| Browser client build | browser-cookie-clear-build-20261120-r1 (source revision, build log) |
| Stager build | maps-r114-tools-20261120-r1 |
| Kernel build | maps-thread-fix-kernel-20261120-r1 |

Screenshots of each step are in the guest directories. The guests are
stopped; their data volumes are retained unchanged.

## r118–r123: sign-in WebView, check-in timing, account queries

Logs are now copied to the data volume before each guest stops
(`cp broker.log maps.log receipt.json /var/lib/vinix/apps/rNNN-private/`)
and read with debugfs, because the serial export deliberately omits them.

| Run | Check-in | Furthest point | Stopped on |
| --- | --- | --- | --- |
| r118 | passed | MinuteMaid created, no cookie exception | `WebView.setMapTrackballToArrowKeys(Z)V` missing |
| r119 | passed | same, past the trackball call | `WebSettings.setDisabledActionModeMenuItems(I)V` missing |
| r120 | passed | same | `LinkageError`: new `onReceivedSslError` default names absent `SslErrorHandler` |
| r121 | timed out | "Something went wrong" | GMS 10 s check-in wait |
| r122 | — | Maps onboarding | Maps main looper: `account query deadline expired` |
| r123 | timed out twice | "Something went wrong" | Maps later exited without a logged exception |

r118 confirms the cookie-clear fix in the guest: MinuteMaid's
`removeAllCookies` no longer throws.

Fixes from these runs, each committed with its builder checks:

- 0e9f40e95 adds the WebView members MinuteMaid calls. The new
  `tests/native-android-tools/framework-api-gaps.v` resolves every framework
  call of selected app classes through superclasses and interfaces.
- b069cd085 and da2adf461 add AOSP-default WebView client callbacks, no-op
  deprecated settings and URL helpers, and dispatch page starts through the
  public `onPageStarted(WebView, String, Bitmap)` that GMS overrides. No
  added method may name a class the framework lacks; the builder asserts it.
- b03749d2f gives broker account queries 30 s instead of 5 s. The broker
  forwards them to the owning service's main-thread pump, which GMS keeps
  busy during startup.

Framework `framework-webview-client-20261120-r2` (api-impl.jar SHA256
c43de53515ff4f88708433a97051fa45dff83fddc1533bd130ea33495c89c770) and
native `account-deadline-native-20261120-r2` (SHA256
5a4fbdb70ab38113ad59fc54ae8490794ac6b088b1d5fcc5f5efc5a12c5c28e3) are the
current candidates. The native producer needs `VINIX_ANDROID_RUNTIME` pointed
at `native-runtime-libs-20261120-r1/opt/vinix-android-aarch64`, because the
runtime libraries under `build/` are gone. The smali tools are in
`combined-account-webview-global-settings-string-framework-2026-11-05-r1/smali-tools`
(`VINIX_SMALI_TOOLS`).

### Check-in timing (r121)

GMS's forced check-in started at 531750 ms and finished at 549193 ms.
Its callback was delivered (`1 callbacks for checkin started at: 531750`),
7 s after CheckinHelper's 10 s wait had expired. The packet capture shows the
network exchange took under a second; the first DNS lookup came about 8.5 s
after the start, while GMS started DroidGuard and twice failed to load the
Cronet module (`UnsatisfiedLinkError` for `internal.J.N.MDkrKi31`) before
falling back to Java. JIT is enabled. Check-in passed in 4 of 8 runs today.

### Remaining work

- Google's sign-in page talks to GMS through `addJavascriptInterface(...,
  "mm")`. The framework's `addJavascriptInterface` is a stub and the browser
  engine has no JavaScript bridge, so even a loaded sign-in page cannot hand
  its result back. This needs an engine operation and a native binding.
- Check-in: make Cronet load (or fail fast), or shorten DroidGuard startup,
  so the forced check-in finishes inside 10 s.
- GMS reads forwarded account queries on its main thread; answering
  native-only queries on a worker would remove the latency at its source.
- r123's Maps exit left no exception; its cause is unknown.

| Private log | broker.log SHA256 | maps.log SHA256 |
| --- | --- | --- |
| r118 | 8ade76f051ab05d601bfa6e92e5eaa147358e92b95ff82589582726d300956de | 19ce8549f8d8d0b88f17aa61ce5a00054d833e9f55fbc5f9bbdeda3d2996c3b8 |
| r119 | 6f6994179376bca53c33e42321b1735bd9c6e32285c586e153787fed5e45e86b | 894d9f9519372501c8db427d91f4403097f326d5b7d33369a44a7de95203c562 |
| r120 | 04b1bd3c20ff7e7769f3c4d6d8f8281b18ed73de4cb18fd1e556140af9538734 | f0dd02cd0726085895d2d340ad1de2b2b670b285c53e00167149a362e646b8f4 |
| r121 | ba2d2acc78eced2289843802af339a08c22bef3049e4a136b34d74f0dd438830 | cc671f1fd394e7b1affdda33aa63e6c349536574f30f2385bbedceefe71d99e8 |
| r122 | c9c85aa4bce1e56821f8d41800fe737b37092133b076ce8953a013e958b48763 | 08d511606414871c2eecffd2b63ca4de55e5d3e832ea6480799f39d2793e062f |
| r123 | c611bf9bdb25d756d7b763bcfce5fa6513109aa10c644438cb55ba3d2df06a1f | 49a32b17bc07294486229e4e734793a1dbaa285886a3131a87043dc537418dcb |

Each is under `maps-current-20261120-rNNN-account/private/`. All guests are
stopped; no credentials were entered and no account authenticated.

## r124–r127: JavaScript bridge, then the WebKit sandbox

Google's sign-in page calls GMS through `addJavascriptInterface(..., "mm")`
and uses return values synchronously, so the WebView now has a real bridge:

- c17cfe704: three browser operations (`js_interfaces`, `js_call`,
  `js_reply`) and the engine side. A document-start script defines each
  interface; its methods call `window.prompt` with a per-engine marker, and the
  `script-dialog` handler holds the prompt open until Android answers. Values
  are tagged text counted in UTF-16 units. Host tests run the generated script
  in JavaScriptCore against a fake Java side.
- 406b0a98a: the framework keeps interface objects, publishes their
  `@JavascriptInterface` methods and answers calls by reflection
  (`androidtools/java/android/webkit/VinixJavascriptBridge.java`, compiled with
  javac and D8 into the framework, with a host JVM check); the native client
  dispatches each call and always replies. The framework gains the
  `JavascriptInterface` annotation.
- c319e28ac: six platform members the MinuteMaid classes call
  (`Settings.System.getConfiguration` stopped r124).
- 9d61c2dc9 and 2385836aa: `setCookie`/`getCookie` no longer throw when the
  engine refuses a cookie (stopped r126), and bare-host cookie URLs are
  normalized to `http://host/` like Android's `WebAddress`.

r126 and r127 ran with 8 vCPUs; check-in passed in both. Earlier failures
correlate with the guest's load: passing check-ins took 2.6–6 s at 158–173 s
of uptime, the slow ones 10–22 s, two of them at 465–531 s after a lost tap.

r127 reached the sign-in page load and showed "Something went wrong — Please
go back and try again". The engine aborted (status 134). Its retained
`webview/last-failure.log` shows why no page has ever loaded in a guest:

- `bwrap: Creating new namespace failed, likely because the kernel does not
  support user namespaces`, then WebKit's `readPIDFromPeer` error. Running
  bwrap by hand in the guest, even `--unshare-user` alone fails. The Vinix
  kernel, on master too, rejects `CLONE_NEWUSER` and `CLONE_NEWNET`
  (`proc.unsupported_namespace_flags`); seccomp filters already exist. The
  engine runs under the app's unprivileged UID and refuses
  `WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS`, so WebKit cannot start a web
  process.
- `GLib-GIO-ERROR: No GSettings schemas are installed`. The browser runtime
  ships the schema XML and glib-networking's GNOME proxy module but no
  compiled `gschemas.compiled`; `tests/android-browser-deployment/build.v`
  should compile it (or the launcher should select GLib's dummy proxy
  resolver).

Loading the sign-in page therefore needs either user and network namespaces
in the kernel or an explicit decision to run WebKit's web process without
its sandbox; that is a security policy choice, not taken here. The bridge
is built and unit-tested but not yet exercised by a loaded page.

| Run | Private broker.log SHA256 |
| --- | --- |
| r124 | 5f999272994207d8d94f0df2207396b9130a1c89cab4dded5acc6561cd957e5e |
| r126 | 5736ecfdf2ff43751b5936fef1b672bfa1f9e31b60588a364991afb66dd6efff |
| r127 | ad72125e529952dd42b94705a1a887517425a0f77b980cb79116d024d5b8ea4f (also webview-last-failure.log) |

Current candidate inputs: framework `framework-signin-platform-20261120-r1`,
native `bridge-native-20261120-r4`, browser client
`bridge-browser-client-20261120-r1`, engine `bridge-engine-20261120-r1`
(API audit: 111 symbols present in the deployed libraries).

## r128–r146: WebKit's sandbox starts; the web process stops at EGL

The kernel now gives unprivileged processes user and network namespaces
(d65a77034 and following, see docs/linux-posix-qualification.md), and
GLib uses its direct proxy resolver (01db535b5), so neither blocker above
remains. Each run then exposed the next one:

| Runs | Stopped at | Fixed by |
| --- | --- | --- |
| r128 | bwrap: openat2 RESOLVE_IN_ROOT, then mount_setattr, unsupported | 112c791ad, d65a77034 |
| r129 | /sys/block and /dev/random missing | 7ecaba266 |
| r129–r131 | WebView creation timed out after 10 s (engine start ~15–26 s); a 60 s wait exceeded browserclient's 30 s cap; View finalizers blocked on the browser lock | 9b62d009a |
| r139 | bwrap: "setting up uid map": it maps the app to root, then back | c1346a7b7 |
| r143 | bwrap: O_PATH open of /dev/tty ran the tty open (ENXIO) | f9ecf676b |
| r144 | web process: no fontconfig file, no injected bundle | ac1c6f8ef, 1bc1ddb7a |
| r145–r146 | web process: "Could not create surfaceless EGL display" | open |

In r144–r146 WebKitWebProcess runs inside bubblewrap's user, pid, IPC,
UTS and network namespaces. It aborts because Mesa 26.2.3 in the runtime
(libgallium only, empty dri/) cannot create its DRI screen
("DRI2: failed to create screen"). The engine's UI process logs the same
warnings outside the sandbox, so this is the graphics stack, not the
sandbox. WebKitGTK 2.48's web process requires a surfaceless EGL display.

Check-in still fails some runs (r138, r140); tapping Add account as soon
as the chooser appears (poll screenshots after Sign in) avoided it in
r139 and r141–r146. A second Add account in the same session does nothing.
The engine deletes its session directory when it ends: copy
session-*/session.log while it runs (with sh, not the guest's zsh, whose
NOMATCH ends a loop on an unmatched glob).

| Run | session.log SHA256 |
| --- | --- |
| r143 | 50d3299a4b4680264d22a5f8fefef050c98df5b2390c3fb3dab03e03241438a8 |
| r145 | 2b0789a028945be0e2f3c201051db6b9b55362a4cbca7984c4ec8c908ba5f3cc |
| r146 | 173c1ae9c12b980e0af059789ec05b2a6d6615a2f0b29f1ea6e16854fc66112a (EGL_LOG_LEVEL=debug launcher, not committed) |

Inputs for r145: kernel from master f9ecf676b, native
`bridge-native-20261120-r7`, engine `bridge-engine-20261120-r3`
(API audit 113 symbols), launcher `launcher-proxy-20261120-r1`, browser
client `bridge-browser-client-20261120-r1`; the injected bundle was
copied to /usr/lib/webkitgtk-6.0/injected-bundle in the guest by hand
(the deployment has not been rebuilt with 1bc1ddb7a).
