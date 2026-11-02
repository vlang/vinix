# Broadcast-permission ARM fixture rejected by ART

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

The next step is correcting and resigning the fixture, updating its exact runner
and transfer pins, and running it on a fresh VM with the immutable prepared
framework/native image. All r1 evidence remains required; this attempt does not
establish the framework's functional ARM behavior or current Maps success.
