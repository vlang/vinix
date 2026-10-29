# Maps handoff and transport runtime, 2026-10-29

The fresh guest reached Paris search and driving directions. Its public handoff
trace now establishes that Add account was dispatched and ended with error 1
before any interaction offer. Map imagery remained absent. Private TLS diagnostics
also exposed repeated IPv6 connection failures; they do not establish the cause
of every missing image or the account failure.

Artifacts below are relative to `/Users/alex/.local/state/vinix/android/` (`S`).
The immutable stage is `maps-account-handoff-r5`, produced at source revision
`05bf1b764ffb09587112fb61dc4adc6209dd071e`, inventory SHA-256
`256b9c62ad2c6c83668cac756697941c8cdba6e6eae9a31543016d6f85b90e7a`.
Its frozen inputs and verified fresh clone are documented in the
[staging checkpoint](maps-account-handoff-stage.md).
The live clone is `maps-account-handoff-vm-r1` (`VM`); controls and collected
results are `maps-account-handoff-runtime-audit-2026-10-28-r1` (`A`).

## Observations

The broker reached readiness before Maps was launched through the desktop.
Sign in opened the account dialog; Add account returned to onboarding without
showing a login activity. The strict public receipt contains exactly these
untruncated records:

| Stage | Operation | Event | Code |
| --- | --- | --- | --- |
| 1: admitted | 2: addAccount | 0 | 0 |
| 2: dispatch queued | 2: addAccount | 0 | 0 |
| 9: terminal response queued | 2: addAccount | 2: error | 1 |

This narrows the failure to the handled authenticator request, before an
interaction offer. It does not distinguish an explicit GMS `onError(1)` from
the framework's generic caught-exception mapping to error 1. A bounded private
search found no `addAccount failed` match; the current catch does not print the
throwable, so that absence does not clear the catch path. Empty initialization
and pump-failure arrays do not establish successful authentication.

Skip advanced to the main screen. Paris search and Eiffel Tower-to-Paris driving
directions worked, with route geometry and a 25-minute estimate visible. The last
route input was at 12:26:49 UTC; the route was visible at 12:27:36. At 12:28:11,
82 seconds after the last input with no intervening input, the background remained
beige and imagery was absent (`VM/route-hold-02.png`).

The private screen capture `VM/network-errors-private-01.png` confirms
`wolfjsse=enabled jul=FINE` and repeated `ConnectException` / `ECONNABORTED`
failures connecting to the IPv6 address of `mobilemaps-pa-gz.googleapis.com` on
port 443. This is positive transport-failure evidence. It does not cover native
Cronet/BoringSSL, HTTP completion, bitmap decoding or texture upload, and does
not establish that IPv4 networking would resolve imagery.

## Verification and retained evidence

Frozen kernel installation passed before boot, preserving all modules and the
configuration. The guard used 600 MiB aggregate RSS, 900 seconds, 4 GiB observed
shared-volume growth and a 1 GiB reserve. It exited zero with complete cleanup
after 52.657 seconds, at 31,244,288 bytes peak sampled RSS and 168,546,304 bytes
observed shared-volume growth. These shared-volume changes do not isolate
producer-owned allocation. Kernel-patch receipt SHA-256:
`a682ea2d5a02bcb6214acc171077867da0d19f3ca8d2a8c4165d763677d56230`.

One 12 GiB, four-CPU VM ran the controller from 12:18:12 to 12:28:40 UTC with
TLS tracing enabled and onboarding tracing disabled. Its status is
`user-stopped-no-authentication-claim`, with service ready, no preparation error,
broker exit 137 after the explicit stop, and `cleanup_survivors: 2`. The latter
counts tracked identities still visible at the cleanup deadline; zombie versus
running state is not established. No credentials were supplied.

Canonical UART export finished before VM shutdown. The exact captured interval
is 2,243,020 bytes, SHA-256
`7bf49a22bfceda2b373d9dbe7840cc1ca7278d2803be3fe79f082e58ef8c46c5`.
Strict collection passed at `A/maps-strict-results`, with exit zero and complete
cleanup under 600 MiB RSS, 300 seconds, 64 MiB growth and a 1 GiB reserve;
sampled peak RSS was 27,508,736 bytes. Private logs remain excluded from the
public result archive.

The runner requested SIGTERM for owned PID 68661 at 12:29:50. It then reported
a transient ownership mismatch; reconciliation confirmed absence at 12:30:11.

| Retained artifact | SHA-256 |
| --- | --- |
| `A/maps-strict-results/results/receipt.json` | `3fd6eadb284c6a8c741e46acae10b7a868647b6d13fd304a264595bf1df444d2` |
| `VM/route-hold-02.png` | `e8b4f4d762a4342755a3d8a70ec34022abc6e2652e139d936906cf4ddc888f63` |
| `VM/network-errors-private-01.png` | `7bea3e0a84ecafe8bb2b4c29a2de81f271e0168a11281f9fccfaeb11ebb66893` |
| `VM/stop.json` | `6529f236df4b5f77950ddaa0a1f216ca9c62f12c13f63ef52276173f9bb6dd44` |
| `VM/gone.json` | `2bf207f0a8c6a8f25f9723ae86d5f10c7053ef0cbccf61ea3c34eff0eb0923a7` |

Both closed roots are bound by
`S/maps-account-handoff-runtime-sealed-2026-10-29-r1/sealed/manifest.json`,
SHA-256 `c44273d90f76640cf4cb330ea1c43deae03266c1b3767ba9b8fad2f7069c7c05`.
The seal and fresh-process full readback passed for two roots and 405 entries.
Both guards exited zero with complete cleanup under 600 MiB RSS, 900 seconds,
64 MiB growth and a 1 GiB reserve. Their elapsed times were 3.354/2.403 seconds
and sampled peak RSS 23,937,024/13,336,576 bytes. This report does not replace the
complete external bundle.

The next checks are a fresh IPv4-only networking comparison and private logging
of the caught authenticator throwable. Successful Google login and usable map
imagery remain unverified by this run.
