# Browser engine failure diagnostics, 2026-11-15

The contact-label adapter in 194bdbe31 passed the complete signed ARM suite and
the real account layout progressed past those calls. In r108 the native browser
engine exited immediately before CookieManager.removeAllCookies failed during
account fragment creation. The window remained on Checking info. Complete
public/private evidence is in [the contact-label report](maps-contact-labels-20261115.md).
The launcher deleted its temporary engine log before the runtime could preserve
it, and its exit message omitted the process status.

The launcher now reports the numeric engine status and retains the final
64 KiB of a failed session's log at the app-private webview/last-failure.log.
It reads the original open regular-file descriptor, leaving its position
unchanged, handles interrupted/partial IO, writes an exclusive mode-0600
temporary file and atomically replaces the previous failure. Logs stay private;
the original stderr receives no log content. Engine/Xvfb process cleanup and
temporary session/X authority removal retain their existing order. Successful
client disconnects do not replace the last failure log. No sandbox settings,
account authority or cookie success behavior change.

## Host and build checks

External root: /Users/alex/.local/state/vinix/android. Current compiler is
/Users/alex/code/v/v, V 0.5.2 cbfc1be. The ten production browser session tests
passed normally and under AddressSanitizer (detect_leaks=0, halt_on_error=1),
including zero, short, exactly-64-KiB and larger binary logs, repeated bounded
replacement, unchanged descriptor position, exact private mode, destination
symlink replacement without victim modification, and invalid/device descriptor
refusal. Existing descriptor, authority, environment and cleanup cases passed.
Receipts and generated C/binaries remain outside Git in browser-failure-tools-
20261115-r1 and browser-failure-tests-* roots.

The full paired account protocol build passed, including the fresh static
AArch64 launcher, with captured source/compiler inputs and readback under the
original caps: RSS 629145600, wall 300000 ms, reserve 1073741824, shared growth
536870912 and output 4194304. Elapsed 23211 ms, peak sampled RSS 368590848,
maximum observed shared growth 42438656 bytes, exit/child 0/0, empty reason,
complete cleanup. Root: browser-failure-protocol-build-20261115-r1.
run-android SHA256:
ba2e85a71e4f285fb91162c6c62bf82331003f47986417b9a2e8e41d84b0240b.

## r109 ARM and protected retry

Fresh staging and the complete signed ARM suite passed, child exit 0,
readiness pass and CURRENT-API-PASS. The complete API export reconstructed
without removals: 24059 bytes / 47 chunks.

| API evidence | SHA256 |
| --- | --- |
| maps-browser-api-uart-20261115-r1/full.log | 5f3c81cc503cfaa0c9920fc0d4ecf507edf1b61525c6dbe88f267f56108058a6 |
| maps-browser-api-readback-20261115-r1/archive.json | 6c2a2121836de8b53aaa4db271f94a4265adb3b370c8948c47bf352d36846b74 |
| maps-browser-api-child-20261115-r1/child.log | b4028702a84ea8880f3390fb868cea1f2d2362230e8d11b98ff0cdbf3057ff8c |

GMS PID24020 reached readiness on checked persistent volume
42e185336c2d46c7b08a37891d41e70b. Maps PID64752 launched once, rendered
onboarding and the chooser, and attempted Add account once. Three device
check-ins succeeded. This run failed earlier than r108: X11 admission socket
failed before engine startup, followed by the same cookie-removal exception.
Maps exited on the account query deadline; GMS remained alive. No credentials
were entered. The retained private log contains Xvfb/XKB warnings, not an
engine exit or sandbox failure. The numeric engine-status path remains pending.

The production diagnostic retained an app-private mode-0600 log, 898 bytes;
it was copied to r109-private/browser-failure.log before the checked stop.
After the complete account export ended, full results were copied and synced
to the checked data volume. Mount check, copied receipt/log and prompt preceded
stopping QEMU23328. PID absence and no open image handles preceded read-only
extraction; e2fsck passed. The complete export reconstructed without removals:
1429898 bytes / 2793 chunks. The receipt compares identical to the private copy
and private logs match their manifest. Receipt status is
user-stopped-no-authentication-claim with cleanup_survivors=1, so complete
controller cleanup is unqualified. The test guest is stopped. Account
authentication remains unqualified.

| Account evidence | SHA256 |
| --- | --- |
| maps-r109-uart-20261115-r1/interval.log | 2406268988d5c7a4d493ef038a90bd55ace17b65692a541af2c67fd1fd8532c5 |
| maps-r109-readback-20261115-r1/archive.json | 9b8ad8c08ca859bbe093fb9f92eb26224a5faab21b9da5fdc256eed141907357 |
| Same readback/exported-receipt.json | 5f856f6a091b5157ac331f4c6ffac5df87543ff4e1b64e0cd042519bf3cf4e57 |
| Private r109-private/results/broker.log | 4e6635c569b2c49ea621d24e94e6a0ce66ffcfa5525c42adb745d779a9d1a2a2 |
| Private r109-private/browser-failure.log | 142634a775ba4852e36feca88bb2403a1227439c43b13a6762ad0a4955beaca9 |

The X11 waiter currently rejects POLLERR before checking readable data. Vinix's
Unix close path explicitly sets POLLIN|POLLHUP|POLLERR, including when a reply
remains queued. This can discard the wrong-cookie rejection response used by
display admission. The next fix drains readable responses while preserving
complete-header validation and refusal of connection errors/invalid descriptors.
It does not establish the underlying engine failure seen in r108.
