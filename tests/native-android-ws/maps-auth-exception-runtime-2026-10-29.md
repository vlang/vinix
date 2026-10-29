# Maps caught authenticator exception runtime, 2026-10-29

The private exception diagnostic identified a concrete Add account failure:
GMS called `BlockingServiceConnection.getService()` on the main thread. Its
`IllegalStateException` propagated through
`AbstractAccountAuthenticator$Transport.addAccount()` and was mapped to error 1.
The synthetic authenticator regression also passed on ARM. This run does not
validate a dispatch fix or successful Google authentication.

Artifacts below are relative to `/Users/alex/.local/state/vinix/android/` (`S`).
The stage is `maps-auth-exception-r1`, source revision
`bfac0d82d4ffbb11bb1b64f271ddd2175fdcffc2`, inventory SHA-256
`b8b214ffc061366718511b4d293077e8901d797884e884ebaad84f346d5341e1`.
Its producer evidence is separately sealed at
`S/maps-auth-exception-stage-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`1792e1b32944d17152a8e4cdd65a41df7fa9de5e3ad79a792c5a98015d38952b`.
The [framework successor](authenticator-exception-framework-2026-10-29.md)
adds private caught-throwable logging while retaining result mappings.

The live clone is `maps-auth-exception-vm-r1` (`VM`), with controls and derived
results in `maps-auth-exception-runtime-audit-2026-10-29-r1` (`A`). It used the
frozen kernel, one 12 GiB/four-CPU VM and the explicit `user-default` network
backend recorded in `VM/launch.json`.

## ARM fixtures

The [pinned fixture runner](auth-exception-fixture-run.md) exercised the
authenticator exception regression and network observation fixture as UID/GID
10117. Both child receipts record wait status zero, exact single terminal and
native readiness checks, drained EOF and unchanged pinned inputs. The
authenticator log contains `AUTHENTICATOR-BASE-PASS`, covering the existing
fourteen-dispatch contract and exception mappings with the private diagnostic.

The network verifier accepted the complete finite observation sequence. IPv4
TCP and the hostname-based socket constructor connected. IPv4 TLS failed with
unclassified throwable code 10; no known transport cause was identified.
IPv6 TCP timed out, and its TLS probe was skipped. These are connectivity
observations, not a TLS or authentication pass.

Each original UART interval remains intact. The unchanged no-removal planner
and diagnostic reconstructor produced two-entry archives, followed by bounded
`child.log` extraction. This collection is a diagnostic derivation; no strict
SERVICE-QUERY import is claimed. The full derivation, hashes and checks are in
`A/fixture-validation.md`, `A/auth-fixture-diagnostic`,
`A/network-fixture-diagnostic` and their read-only child outputs. The transfer
server served exactly the three pinned files and exited; its completed receipt
is retained in `S/auth-exception-api-transfer-live-2026-10-29-r1` (`T`).

## Maps account and rendering observations

The broker reached readiness before Maps was launched from the desktop.
Sign in at 13:21:09 UTC opened the account dialog; Add account at 13:21:14
returned to onboarding. The private `VM/authenticator-caught-private-01.png`
captures the fixed diagnostic marker, the main-thread blocking-call exception
and its stack through `akgu.addAccount` and the framework transport. The public
receipt records stages 1 and 2 for operation 2, followed by stage 9 / event 2 /
code 1, with no interaction offer. In this run the private diagnostic explains
the generic terminal error. No credentials were supplied.

Skip, Paris search and Eiffel Tower-to-Paris driving directions worked. The last
route input was at 13:28:00; route geometry was visible at 13:28:11. The held
screenshot at 13:29:16, 76 seconds after the last input without intervening
input, still shows a beige map background and a 23-minute estimate.
`VM/diagnostic-render-private-01.png` records EGL frame 64 and COMPOSE frames
with `different_rgb=3679`, establishing that nonuniform rendered pixels reached
both stages. This does not establish imagery decoding or texture correctness.
The same private screen includes a `Service not registered` unbind exception;
its relationship to the missing imagery is unestablished.

The controller ran from 13:18:11 to 13:30:32 with both onboarding and TLS traces
enabled. It recorded service ready, no preparation error,
`user-stopped-no-authentication-claim`, broker exit 137 after explicit stop and
two cleanup survivors. Running versus zombie state is not established by that
count. Empty initialization/pump-failure arrays do not establish authentication.

## Evidence and shutdown

Clone and kernel guards passed. Kernel installation exited zero with complete
cleanup after 47.466 seconds and peaked at 31,522,816 bytes sampled aggregate
RSS, under 600 MiB RSS, 900 seconds, 4 GiB observed growth and a 1 GiB reserve.
The complete Maps export passed the strict collector under 600 MiB RSS,
300 seconds, 64 MiB growth and a 1 GiB reserve, with exit zero, complete cleanup
and 28,704,768 bytes peak sampled RSS. Its exact UART interval is 2,243,803 bytes,
SHA-256 `6e8b410af2cc7f36d88dd9b37d2c57bd34074a689d5f9d08d27227c4fb144068`.

Owned VM PID 32823 received the SIGTERM request at 13:31:31. A transient ownership
mismatch followed; reconciliation confirmed absence at 13:31:36.

| Retained artifact | SHA-256 |
| --- | --- |
| `A/maps-strict-results/results/receipt.json` | `1048e745d8e08f54f0e1e89baaa8eddb848cc47b230954f7a652fc8f4cd1948a` |
| `VM/authenticator-caught-private-01.png` | `e54579748a473011aec983efd9fcd0c1ca3410cc45d985709dcba578b8f55630` |
| `VM/diagnostic-route-held-01.png` | `8a1fd05c1705db3704f749b3eccc05e75ad5ed4dc9fffb991fdd9d4701c484b4` |
| `VM/diagnostic-render-private-01.png` | `7fa03dabc075c9133ca5f6e24589cf33554da5d671642eec2f9547c6dafc7835` |
| `VM/kernel-patch.json` | `eddbd032b26e11800d60b125b9b8b6727d6223d6a069f250f7cbff77d12a603e` |
| `VM/stop.json` | `bc7dc9c30012bb395604d9939acad338cc892b1e0684d613e274eee191e311dd` |
| `VM/gone.json` | `5017b616c6755b6460f583ddccc6f9edbc9f82028e01b9244bae1e6f99265483` |

The three closed roots `VM`, `A` and `T` are bound by
`S/maps-auth-exception-runtime-sealed-2026-10-29-r1/sealed/manifest.json`, SHA-256
`9b354d84d6ea481d5ab56906ed2b62df9fb45311c4656d547eb21ae60ad21a4e`.
The seal and independent fresh-process complete readback passed for 465 entries,
with exit zero, complete cleanup and zero swaps under 600 MiB RSS, 900 seconds,
64 MiB observed growth and a 1 GiB reserve. Elapsed times were 5.772/3.102 seconds;
peak sampled RSS was 13,991,936/13,598,720 bytes. Preserve the complete external
bundle; this report does not replace it. Google login and usable map imagery
remain unverified.
