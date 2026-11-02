# Broadcast-permission ARM pass and Secure-setting linkage failure

The corrected V2 broadcast-permission fixture **passed on ARM**, exercising
actual dynamic and manifest receiver delivery, permission denials and immutable
authority despite mutable public metadata. GMS then advanced beyond its missing
broadcast overload and exited after missing `Settings.Secure.putString`.
No manual Maps launch, Sign in, credentials or imagery test occurred; current
map rendering and authentication remain unverified.

## Corrected fixture, runtime r2

Fixture fix `ce3f6085b` makes exception-merge receiver state verifier-safe and
bounds HandlerThread startup through a latch. Delivery `ebbad3e1b` pins the signed
r3 APK and distinct V2 runner. The complete failed r1 fixture and evidence below
remain unchanged. This retry reused the same immutable prepared image manifest
`cd669a48739890494fd4780acd077c25e0bbcbf586330bb2f855ead92ae0fe7b`;
its framework/native pair was not rebuilt or changed for this fixture fix.

Paths below use `S=/Users/alex/.local/state/vinix/android`,
`A2=S/maps-broadcast-permission-runtime-audit-2026-11-02-r2`, matching r2 live
controls and stopped `maps-broadcast-permission-vm-2026-11-02-r2` with its four
clone sidecars. The V2 transfer is
`S/broadcast-permission-v2-api-transfer-live-2026-11-02-r1`.
The prepared parent, prior complete sealed roots and historical auditors remain
required alongside these new runtime roots.

The isolated UID/GID 10147 child 44618 exited zero with profile
`broadcast-permission-v2`, six exact input identities and eleven unchanged
checks. Receipt SHA-256 is
`d4dbf81403a04e51772a26609a8c61db3c80274907f546287e3c6510b49e0795`.
The complete 10,175-byte, 110-line child hashes to
`b773e2a81b7bcc6e42a85c7b2ea92293a06d5dcdb7007227ddf92686c6649aeb`:
one exact full PASS at line 95, readiness at 104 and normal teardown through 110.
Independent `A2/fixture-validation.md` hashes to
`f2f684ac4fb296310b155d0c6c472955a8a4aceb94d648c51c9953c4e95c28f5`.
It verifies real delivery for the fixture's declared/requested self-owned
signature permission and null-permission legacy calls, rejection of unknown,
unrequested and non-signature permissions, forged-grant controls, metadata
mutation/restoration, queued callback barriers and bounded startup/cleanup.
No health diagnostic was suppressed. This proves the exercised primary-APK
process-local contract; it does not establish cross-process routing or a general
Android permission service. Unchanged zero-removal diagnostic import preserved
33 chunks of the 16,507-byte fixture archive, without new strict fixture-protocol
qualification.

After releasing the fixture mount, GMS attached its authenticator. Controller
receipt `e23f77a84d94d19829249c6bec02456bc293754dc1720b515dbabae70da5843d`
records 17:00:47–17:01:41 UTC, broker 48654, service readiness true, failed/exit 1,
drain EOF true/status 1/304,280 bytes/errno zero and zero cleanup survivors.
The next uncaught error is missing static
`Settings.Secure.putString(ContentResolver,String,String)Z`, through `eaaw.b`
source 282 → `eaav.a` source 4 → nearby.sharing.ModuleInitializer.onHandleIntent
source 63. GMS then calls System.exit(10), recording native VM status 10.
Transport readiness alone does not establish successful startup or authentication.

Automatic export completed with guest input idle. Before stopping the VM, the
unchanged strict collector passed 21 entries, 2,831 chunks and 1,449,222 bytes,
archive `01d2a9efdac9145c42726e5f458b3f3de17c5c0778d3c84ce996692cd64ee2aa`.
Import took 274 ms at 28,999,680 bytes sampled RSS; both exits are zero with
complete cleanup. The full exact private broker log remains separately at
`A2/broker-log-diagnostic/child.log`, 304,280 bytes, SHA-256
`6bab767303650d039be9ae714c7cc7441a57c3db273ff6109df79817f7c7a448`.
The existing guest-pinned canonical-base64 decoder and separate fresh readback
passed without modifying UART or payload bytes. Private logs remain outside the
strict account archive apart from hashes. Failure cleanup removed the live
broker session required by the supported desktop Maps launcher.

Owned exclusive 12 GiB/four-CPU VM 49137 started at 16:56:16 UTC. One SIGTERM was
requested at 17:03:15; QEMU records signal 15. The first stop returned 1 after an
identity race; no second signal was sent. Qualified reconciliation returned zero
at 17:03:27, and `gone.json` plus an independent empty exit-1 ps query confirm
absence. Final UART exactly equals the immutable after-private-log full snapshot,
both SHA-256 `f93849cb5e10454443900ed434e0929f44e4fc91bdca722c637051c0c6543c51`.
No compiler or Java ran while the VM was live. The nine-root complete r2 seal
and separate fresh-process readback passed all 680 entries. Manifest
`maps-broadcast-permission-runtime-sealed-2026-11-02-r2/sealed/manifest.json`
hashes to `bab6cf72c2b30a3c8430ecdbc0f055799731466fea6c69022415c0d057cb0982`.
Both guard/child exits are zero with complete cleanup under the original
600 MiB RSS, 900-second, 64 MiB shared-growth and 1 GiB reserve limits. A first
guard preflight rejected misplaced control paths before starting the sealer;
the preserved rejection and corrected invocation did not change any limit.

## Historical runtime r1: fixture rejected by ART

The first broadcast-permission ARM run failed in the signed test APK before
Main.onCreate. ART rejects Main.run(Context) at offset 0xD1: register v3 has type
Conflict where DynamicReceiver is required. This establishes a fixture verifier
error, without a functional receiver-permission or delivery result. GMS was not
started; no manual Maps launch, Sign in, credentials or imagery check occurred.

Core `0b00959bc`, producer `84a791b70`, fixture `13b507ee7`, delivery
`b35483fa5`, [SDK qualification](broadcast-permission-sdk-2026-11-02.md)
`f5767ea68`, [fresh native coupling](broadcast-permission-native-2026-11-02.md)
`12ebe4dfe` and [media profile](maps-broadcast-permission-stage.md) `8d9b86793`
are committed. This profile changes Context and ATLLoadedApp, adds the policy
utility and includes the directly coupled fresh native library. Prepared image
manifest is `cd669a48739890494fd4780acd077c25e0bbcbf586330bb2f855ead92ae0fe7b`.
Preparation passed in 296.748 seconds at 89,079,808 bytes sampled RSS with both
exits zero and complete cleanup; clone and frozen-kernel installation then
passed before boot under the original resource limits.

Complete r1 evidence remains below `/Users/alex/.local/state/vinix/android`:
`maps-broadcast-permission-runtime-audit-2026-11-02-r1` (`A`), matching live
controls, prepared `maps-broadcast-permission-r1`, stopped
`maps-broadcast-permission-vm-2026-11-02-r1` with clone sidecars, and the live
broadcast-permission transfer root. `A/runtime-result.md` closes the historical
pending operator checkpoint without changing it. Failed host attempts, original
signed fixture and historical complete bundles remain preserved.

The dedicated UID/GID 10146 invocation began at 16:39:35 UTC with signed r2 APK
`0219961f053e02b8d4435b87e86acec64e56d57eb2b68d2f175638016eda37b5`.
The class verification error occurs during ATLLoadedApp.createActivity before
the activity is constructed. The runner reports a child failure marker; no PASS,
READY, successful runtime receipt or fixture export archive was produced.
Before retry edits, current and signed-build-frozen fixture sources.v matched
SHA-256 `78a207cf444e58e09b2b81fc798e35afcd907176cd3bc1ce44bb5848f13712ef`.
The failed APK identity was independently rechecked. No runner health rule was
relaxed and no failed broadcast behavior was interpreted as a permission result.

The full exact failed child is separately retained at
`A/failed-child-diagnostic/child.log`, 10,164 bytes, SHA-256
`560a7b3fec84caa94e227fb52bbbe529d7b898114e074629691c08f15c07a266`.
The existing guest-length/hash-pinned canonical-base64 decoder and a separate
fresh readback passed, guard/child exits zero and cleanup complete. This is
diagnostic preservation without fixture-protocol qualification. Its immutable
14,936-byte UART interval derives from the pinned before-fixture snapshot and
hashes to `0a01af353de517bd923adc8b2f329347f6bfb5f8335b0d412c472fbff0817aa7`.
Original UART and payload bytes remain unchanged.

Owned exclusive 12 GiB/four-CPU VM 26194 started at 16:37:01 UTC and stopped
cleanly with one SIGTERM at 16:45:37. Stop/gone receipts, QEMU signal 15 and an
independent empty exit-1 ps query confirm absence. Final UART equals the
immutable after-failed-fixture full snapshot, both SHA-256
`c100483c35415caca1faad2134aa9aca96b5a9808f9c843a0515388ce434b422`.
No compiler or Java ran while the VM was live. The nine-root complete evidence
seal and separate fresh-process readback passed all 625 entries. The manifest at
`maps-broadcast-permission-runtime-sealed-2026-11-02-r1/sealed/manifest.json`
hashes to `7175ebc452eb39cb1bf48966b2f83eae7dc9868f72200fe63890767f503f2844`.
Both guard/child exits are zero with complete cleanup under the original
600 MiB RSS, 900-second, 64 MiB shared-growth and 1 GiB reserve limits.

At this checkpoint, the next step was correcting and resigning the fixture,
updating its exact runner and transfer pins, and running it on a fresh VM with
the immutable prepared framework/native image. The r2 result above completes
that retry. All r1 evidence remains required; r1 alone does not establish the
framework's functional ARM behavior or current Maps success.
