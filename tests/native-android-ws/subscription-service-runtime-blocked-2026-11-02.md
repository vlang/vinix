# Subscription service host pass; image preparation blocked

The no-modem subscription-service fix is committed as `bf4a357a6`. Focused checks
passed 116 refusals, 22 semantic controls and API-28 DEX roundtrips. The signed
fixture `1d2a2ec4d`, SDK producer `8dd3331d1`, delivery tools `49b32a12d`,
[SDK/native pair](subscription-service-pair-2026-11-02.md) `5e78f8f7e` and
[media profile](maps-subscription-service-stage.md) `64d50e93a` passed their
required host checks. All 70 native-consumed classes remain equal; the locale
DSO is retained. ARM execution and live GMS/Maps validation are pending.

Host disk pressure blocked preparation. A stricter 3 GiB outer growth allowance
was refused before spawning because free space fell below its 1 GiB reserve plus
growth budget. A further-restricted 512 MiB attempt started input auditing, then
stopped after 12.031 seconds on 1,081,581,568 bytes observed shared-volume growth.
It peaked at 53,362,688 bytes RSS, guard/child exited 125/137 and cleanup completed.
The stager's internal 512 MiB write budget and all input checks stayed unchanged.
No prepared image was created and no VM was launched. About 1.3 GiB remained.

Both original guard receipts/logs and checkpoint are preserved outside Git in
`/Users/alex/.local/state/vinix/android/maps-subscription-service-live-controls-2026-11-02-r1`
and matching `maps-subscription-service-runtime-audit-2026-11-02-r1`. Qualified
SDK/tool evidence remains sealed at its original locations. Restore stable host
disk headroom before the image/ARM retry; current Maps imagery and authentication
remain unverified.

Disk space later recovered and the original-budget preparation retry passed.
The [resumed runtime result](maps-subscription-service-runtime-2026-11-02.md)
records the ARM subscription-service pass, strict account export, next GMS
AutofillManager linkage failure and clean owned-VM stop. The original failed
attempts and this checkpoint remain unchanged apart from this continuation link.
