# Broadcast-result ARM runtime and Maps onboarding

The signed `broadcast-result` fixture passed on ARM with the combined framework.
Google Play Services attached its authenticator transport and remained alive
until the controller's bounded session ended. Maps rendered onboarding, but
account login and the map screen remain unverified. No credentials were supplied.

The fixture receipt records child PID 21665, UID/GID 10117 and `wait_status=0`.
Its eleven checks passed: exact pass once; native WebSocket ready once; bounded
log and lines; live input until pass and ready; drained through EOF; clean exit;
isolated Unix identity/data/home/surface; metadata-only disabled companion;
explicit environment without account/browser channels; closed inherited
descriptors; unchanged pinned inputs. The exact marker includes
`direct-boot-metadata credential-context broadcast-results`. This exercises
the generic framework regression, including real broadcast deliveries, rather
than Google account authentication.

The public broker receipt spans 2026-10-27 04:50:18–05:05:44 UTC and records
`bounded-session-ended-no-authentication-claim`, `service_ready=true`,
`broker_exit=137`, `cleanup_survivors=2` and an empty error. Authenticator and
browser initialization failure lists are empty and not truncated. Readiness
only proves transport attachment. The session expiry limits what subsequent
UI attempts can establish; the two reported cleanup survivors preclude a
clean broker shutdown claim.

Fresh `maps-resume-sign-in-01.png` and `maps-resume-skip-01.png` captures in
`maps-broadcast-result-vm-r1` still show onboarding after attempted clicks.
Effective click coordinates, delivery and callback execution were not verified
in this run. An unchanged screenshot alone cannot distinguish missed input
from an application transition failure. The earlier onboarding diagnosis is
not established again by this run.

All artifact paths below are relative to
`/Users/alex/.local/state/vinix/android/`. The framework and immutable stage
record source revision `445f57ce7dd45da2cf407e051603b109803b2c57`; the fixture
records `e82ca648198b9e412a5c4defb8e2724503abf01c`. The audit observed repository
HEAD `d7fcf435ace7f024ce6d7a0b5f44a7b0b97a5539`; this does not assert equality
to unrelated concurrent checkout edits.

| Input | Complete bundle | SHA-256 |
| --- | --- | --- |
| Framework manifest | `combined-account-webview-broadcast-result-framework-2026-10-27-r1/sha256.json` | `21d53cc9cd2ccd9c53fc7774a826d83673f3391d30c1757074e3edcba2c8b046` |
| Fixture manifest | `broadcast-result-fixture-2026-10-27-r1/sha256.json` | `93146d2bff516752ca62ea21cfb7bd532ced9abfe81345beb61e40a0b5d9b77d` |
| Immutable stage | `maps-broadcast-result-r2/stage.json` | `8c5cc2c1d6ad92cbd6ae0f95d265b5f69f41e40c36a7bd3873139ffb2ccbabcd` |
| Live fixture JAR | Framework bundle `api-impl.jar` | `5dfba8c7e0006f6c84510d72b8fde84706bcb7f3489b3620cd340ec0361d8564` |
| ARM runner | `broadcast-result-run-2026-10-27-r1/run` | `95be25cf1f8837bc717d200b0b92642c3085adbd789aad25356b89a73f07a8df` |

Owned VM PID 82922 was stopped with SIGTERM at 06:15:55 UTC and its absence
was reconciled at 06:16:38 UTC. The stopped UART snapshot in
`maps-broadcast-result-runtime-audit-2026-10-27-r1/serial-snapshot.log` is
2,325,568 bytes, SHA-256
`35fed287823b522e9ba008a69f82748285b7370e7225b93339fc46285868a055`.
The unchanged historical strict Maps collector and all five protocol
self-tests passed. Its complete Maps import verifies 24 entries, 1,441,989
bytes and 2,817 chunks, archive SHA-256
`ac96606f908b2d306e5ea5f14fb8bdfa1017b4ce1b13f515041193576a63997c`.
Private broker/app logs remain excluded by the producer.

The separate fixture export verifies both entries, 22,487 bytes and 44 chunks,
archive SHA-256
`d5272e18571fd282ecd251bb4244b4ecefb0993627dbd37aedcb8b86d4e23e6c`.
The existing checksum-gated v2 selector used zero byte removals from the same
snapshot. This is a selected-export diagnostic, not a strict service-query
import; its generic historical scope string does not describe the successful
Maps strict import. Its self-test passed 8 positive and 38 rejection cases.

The audit retains exact tools, source, byte-selection plan, commands, logs and
timings. `maps-broadcast-result-runtime-sealed-2026-10-27-r1` seals that audit,
the stopped VM, immutable stage and complete framework, fixture and runner
bundles in place: six roots, 7,899 typed entries, manifest SHA-256
`37fd34728b0678b0fbbbaac2444ad2523e04bf4f4bccfa4941005817b2c4ac16`.
Seal and separate full readback passed, using at most 22,708,224 and
22,298,624 resident bytes respectively; all measurements reported zero swaps.
The strict import peaked at 27,869,184 bytes. Adjacent `*-seal.*` and
`*-check.*` files retain the seal/check command output and measurements.
No compilation or VM launch occurred during this audit. Original complete
bundles remain mandatory for historical checkers; no evidence was removed.
