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
