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

Fresh ARM/account validation is pending. This diagnostic change does not yet
identify the engine's underlying cause or qualify account authentication.
