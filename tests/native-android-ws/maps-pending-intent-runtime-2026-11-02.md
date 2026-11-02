# PendingIntent ARM pass and missing stable-display API

The signed PendingIntent regression **passed on ARM** with the new framework.
Play Services subsequently reached readiness, then exited before Maps opened:
`DisplayManager.getStableDisplaySize()Landroid/graphics/Point;` is absent from
the deployed SDK. Its stack reaches `IntentOperation.onHandleIntent()` and
`PhenotypeRegistrationOperation.onHandleIntent()`. This run establishes neither
successful check-in nor authentication, and does not revalidate Maps imagery.

The deployed source is `f544e142c`, narrow producer `358db21e2`, fixture
`7820a7685`, runner/transfer `07d5dcd6c` and media profile `824c6e2ca`.
The [SDK/native pair](pending-intent-pair-2026-11-02.md) and
[media qualification](maps-pending-intent-stage.md) preserve the exact inputs.
Prepared image manifest is
`87261cadaf528836f4f3903465110d9fb929588fa46b435bbe5ce846104ba473`.

Evidence is under `S=/Users/alex/.local/state/vinix/android`:
`maps-pending-intent-runtime-audit-2026-11-02-r1` (`A`), matching live controls,
`maps-pending-intent-vm-2026-11-02-r1`, its four clone sidecars, prepared
`maps-pending-intent-r1` and `pending-intent-api-transfer-live-2026-11-02-r1`.
Complete prior bundles and unchanged auditors remain required.

The guest's unused UID/GID 10138, protected inputs and dedicated read-only
runtime mount were verified before running the fixture. No input occurred during
export. The actual receipt records child 34319, wait status 0 and all six exact
input pins/eleven health checks. The complete 9,801-byte, 114-line child has one
readiness marker at line 103, one full PASS at 108, and teardown through 114.
Its SHA-256 is
`4757318c0c4daa3818475ff0f6dceef13f310d7d368e9536b12bf3c345364415`.
Seven real service deliveries, one broadcast, a two-sender one-shot race and
cleanup before PASS are covered by the signed source. Independent detailed
`A/fixture-validation.md` hash is
`77aa75a5f5cb7c37ac20354fb25a0984803e9d87fd2fa07bf2005000d90b374c`.

Linked immutable snapshots and unchanged zero-removal SERVICE-QUERY tools
preserve all 32 chunks of the 15,946-byte fixture archive. This is diagnostic
reconstruction, not a new strict fixture-protocol qualification. All original
bytes, normal ART warnings and failed historical controls remain intact.

The fixture mount was released before the account controller. Actual controller
receipt `a53c419a56e075d5a261bf01a71d43b1266373734d9a0c2e214b7a3bf00a5995`
runs 08:47:04–08:47:56 UTC: broker 61632, readiness true, status failed, exit 1,
drain EOF true/status 1/83,097 bytes/errno 0, cleanup survivors 0. The bounded
stack capture records the missing method and Java uncaught-exception path.
No live recovery-flag value was recorded; observed operation execution alone
does not prove every worker change was caused by PendingIntent.

The initial automatic Maps launch encountered the same SQLite hardlink guard
as earlier baseline runs; the account controller performed its established
validated dealias step. No ad hoc library change was made. Maps was not opened
after broker failure. No sign-in, credentials, Next or trust bypass occurred.
The unchanged strict account collector passed 21 entries/2,831 chunks/1,449,095
bytes, archive
`2dcc9e5df53fcee009ca3fed02f359f6ea64208c6c9972ab889c2e9d88d0d683`.
It took 287 ms at sampled RSS 29,409,280 bytes, both exits 0/cleanup complete.
Private logs remain excluded except hashes and bounded diagnostic capture.

Owned exclusive 12 GiB/four-CPU VM 28175 ran 08:38:52–08:52:12 UTC. One SIGTERM
stopped it cleanly; stop tool returned 0, absence and gone.json were confirmed.
Final UART equals the immutable after-maps full snapshot,
`17f4b9f64b8217fcd7abc1a219fb95e39710196101c8aeb64b3c8c1724eb18d2`.
No host compiler or Java process ran while the VM was live. Preparation, clone and
kernel installation passed their original guards. All import and sealing phases
retain 600 MiB RSS, 1 GiB reserve, file cap 16777216 and the original time/growth
limits; no check was weakened.

The nine closed roots passed complete sealing and separate fresh-process
readback: 616 typed entries, manifest
`S/maps-pending-intent-runtime-sealed-2026-11-02-r1/sealed/manifest.json`, SHA-256
`49cb851c233b92bd6b893a52383230b78ae05554473241bcb0ae3fdd3ee1ddb5`.
Seal/readback took 8.248/4.789 seconds, both exits 0 with complete cleanup under
the original 600 MiB/900-second/64 MiB-growth/1 GiB-reserve caps. The missing
stable-display API is the next concrete framework work; it is not validated by
this run.
