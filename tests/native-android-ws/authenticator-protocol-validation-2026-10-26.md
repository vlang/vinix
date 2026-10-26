# Authenticator metadata protocol validation

The broker-owned authenticator metadata route passed host validation against
production commits `1507fec33` (protocol, IPC, client and broker) and `638e9984c`
(registry/model and selected APK metadata). Tests are committed in `f11b537f5`
and `289983e3e`.

| Normal regression module | Test files | Test functions | Result |
| --- | ---: | ---: | --- |
| nativeaccountauth | 13 | 42 | PASS |
| accountipc | 2 | 10 | PASS |
| accountclient | 7 | 24 | PASS |
| accountbroker | 6 | 16 | PASS |
| Total | 28 | 92 | PASS |

All 17 added metadata test functions also passed under AddressSanitizer with
`ASAN_OPTIONS=detect_leaks=0`. This checks memory access on the exercised paths;
it does not establish absence of leaks. Each compiler and test process exited 0.

The checks cover header-only operation 6, forbidden request fields, broker-only
event kind 9, every truncated metadata payload, malformed identities, count and
boolean bounds, duplicate account types, full-width resource IDs, decoded-string
ownership, ABI getter bounds and request/event matching. Broker checks reject
unregistered peers and forged authenticator metadata events. Independent source
review found no definite authorization, decoder cleanup, lifetime or wire-bound
issue in this route.

The compiler was `/Users/alex/code/v-tccbin-bootstrap-20261026/v`, with
`-path '@vlib|build-support/android' -gc none -manualfree -cc cc`. Full module
suites ran sequentially with empty `VTEST_ONLY`/`VTEST_ONLY_FN`, `VJOBS=1`,
`VTEST_KEEP_SESSION=1` and an external `VTMP` per module. ASAN builds added
`-cflags '-fsanitize=address' -ldflags '-fsanitize=address'`. Command settings,
source snapshots, logs, 28 normal binaries and three ASAN binaries are retained
under `/Users/alex/.local/state/vinix/android/review-authenticator-descriptions-r1`.

Retained SHA-256 inventories:

| File in that directory | SHA-256 |
| --- | --- |
| `receipt.md` | `4d6add7463d928fb0c93d707bac2240f09a879d0d77ea7012ed9307aa4b954bc` |
| `sources.sha256` | `ca237db48a7e67642d916a21e83e7b48064bff0104901e9223c488fa60ff732e` |
| `binaries.sha256` | `fa087a1263b8fc328fde0e21cb7fddd9f40fe6de3021ccbf0ab41e36ce1fc0c2` |
| `evidence.sha256` | `89ba205b6e210126f257320399ef25f72f2e0ecc7f08db0f727038eb720dc64f` |

The four broker tests' separate normal/ASAN binaries and logs are covered by
`/Users/alex/.local/state/vinix/android/review-broker-authenticator-descriptions-checksums.sha256`,
SHA-256 `8505d18cb4fb1ccbc827c2551f6434e680209c0d570bdab5754466ac5747ef42`.
Source, binary and evidence checksum verification passed.

This bundle validates host protocol and broker behavior. Successful pinned Google
APK enumeration, guest query latency, ART dispatch and real Google account
sign-in require runtime evidence and are not established here.
