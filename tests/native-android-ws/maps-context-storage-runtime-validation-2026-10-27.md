# Credential-storage closed runtime validation

The ARM credential-storage fixture passed with framework source `34ecf3339`.
Play Services progressed to missing `BroadcastReceiver.setResultCode(int)` and
exited. No actual Maps launch after the broker is established; authentication
remains unverified.
The current stage source is `d095ddece430ffe1ff39d2cb25ae9e922f6dd6be`
(report `1e11eef84`); the frozen diagnostic selector is from `373ed9a537`.

Evidence is under `/Users/alex/.local/state/vinix/android/`. The closed VM is
`maps-context-storage-vm-r1`; audit plans, commands, measured logs, selected pins
and public diagnostic metadata are in
`maps-context-storage-vm-r1-stream-plan-2026-10-27-r1`.

The raw UART is 2,307,288 bytes, SHA-256
`0da4945e145bc5057247dc28d745647c3cadd39dd976089e9d93358ed2590c24`.
The unchanged strict collector rejects serial line 4408. Its proposed output
is absent; `closed-collect.log/time` preserve exit 1. Kernel exec/ELF messages
and console process rows interleave within Maps chunks 1969 and 1970.

The original 25-range diagnostic candidate remains rejected for a complete
archive hash mismatch. A separate 26-range plan verifies the complete Maps
archive `9278172dc1d7edb23329da920d3f5f7608714599456ce6d8204d7e9755203cee`:
1,439,702 bytes, 2,812 chunks, 21 validated entries. This is a diagnostic
derivation, not a strict import or replacement UART. Its public receipt says
`failed`, broker exit 1, transport `service_ready=true` and zero cleanup
survivors. Private app logs stay excluded; only `broker.log` hash metadata is
retained: `b91874eff2f20bb5b76b2669d65d3ec8ed141f012110fb2398ed9d60e0e0d787`.

The intact fixture export verifies with zero removals:
`a913fb7fed52bac6a3123c16d1e69d8869801ba38e19076d532ede215543e423`,
18,791 bytes, 37 chunks, two entries. Its public receipt records profile
`credential-storage`, UID/GID 10117, child 18201, wait status 0, exact PASS and
READY checks, drained EOF, clean exit and unchanged pinned inputs. The JAR,
signed APKs and ARM runner match their complete producer manifests. UART 6176
contains the exact marker ending `direct-boot-metadata credential-context`.
This establishes generic fixture execution on ART.

Filtered UART 6108 records `NoSuchMethodError` for the super method
`BroadcastReceiver.setResultCode(I)V`, through Chimera and
`ATLLoadedApp.receiveBroadcast` / `Context.sendBroadcast`. The retained
`broker-status.png` shows transport READY before broker exit; its SHA-256 is
`3bf1f93824e9eb69cd0dc8d9bee3cb299bb95cfa949f51f56d2f509ef42a3748`.

The validated runner launched owned QEMU PID 5373 at 01:50:55 UTC and recorded
SIGTERM at 01:55:40 UTC. Initial stop returned 1 during the known ownership
race after recording the signal; reconciliation passed at 01:55:48 UTC with
the PID absent. There is no QEMU reap-status claim.

The audit uses the existing frozen selector and streaming sealer; no compiler
or VM was run. Strict rejection took 0.08 seconds / 16,433,152 bytes peak RSS;
fixture verification 0.02 seconds / 16,580,608 bytes; corrected main diagnostic
0.24 seconds / 33,685,504 bytes. All recorded zero swaps.

The new audit references complete original producers and the preceding full
direct-boot closure, retaining historical check requirements. All 24 exact
stage inputs are covered: 17 by the prior 60-root controller closure, two by
the 44-root service-query closure, four by the 55-root direct-boot closure,
and the new credential-storage framework. All three pinned full checks were
rerun successfully. Their logs and resource measurements remain in the new
plan. No old images or full inventories were copied. Scope excludes recursive
history and hermetic SDK/C/shared-library/QEMU rebuild dependencies.

The new 46-root / 8,002-entry seal is
`maps-context-storage-vm-r1-runtime-sealed-2026-10-27-r1`, manifest SHA-256
`4379eee189a06846c6bc85213e8cf59faef8bbc9383ab85312aa5a4ab00590e9`.
Streaming seal plus its internal check passed in 9.46 seconds with 27,066,368
bytes peak RSS; the separate pinned full check passed in 3.28 seconds with
22,986,752 bytes. Both recorded zero swaps. Adjacent logs and measurements use
prefix `maps-context-storage-runtime-stream-2026-10-27-r1`.

The new plan occupies 1,540 KiB and seal 2,096 KiB; large originals were hashed
in place. The narrow disk budget permitted at most 16 MiB new output, a
384 MiB start, 256 MiB reserve and 128 MiB drop. Retained before/after samples
show 485,196 / 457,412 KiB available, a 27,784 KiB decrease. Independent reviews
checked exact roots, direct inputs, diagnostic/public metadata and report scope.
This audit does not explain the earlier 92 GiB host observation or establish
sustained broker memory behavior.
