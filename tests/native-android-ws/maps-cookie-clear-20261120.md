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
