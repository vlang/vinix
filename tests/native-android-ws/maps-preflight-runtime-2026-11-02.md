# Maps account check-in timeout and later broker failure

The unchanged Maps pair renders tiles and its profile menu, but sign-in still
shows Google's communication-error page. This credential-free diagnostic now
records `Checkin timed out`, check-in result `false`, then `RESULT_ERROR`.
The broker later exits with a separate authentication-pump failure. No framework
fix, network cause, successful check-in or authentication is established here.

Source baseline is `61af5f6f3`. The [admitted resource-lock pair and earlier Maps
search/photos run](maps-resource-lock-stress-runtime-2026-11-01.md) remain intact.
The prepared image, SDK/native library and Google APKs were reused unchanged;
no standalone fixture, credential, account creation, Next click or trust bypass
was involved. No compiler ran while the owned guest was live.

Artifacts remain under `S=/Users/alex/.local/state/vinix/android`: audit
`maps-preflight-runtime-audit-2026-11-02-r1` (`A`), stopped guest
`maps-preflight-vm-2026-11-02-r1` (`VM`), controls
`maps-preflight-live-controls-2026-11-02-r1`, and static source audit
`gms-preadd-preflight-method-2026-11-02-r1` with its matching controls.

| Input or result | SHA-256 |
| --- | --- |
| Prepared `maps-resource-lock-r1/sha256.json` | `d4dcdfa033e7e0fa21a634cae6087e95deedbbee4c4936d6be4b7af69f4d5171` |
| Framework JAR | `02aefc8136cb87eb8e9ebd0928cb15f3e1c2042e47d2a687170a0f9309ac4b20` |
| Native library | `aeb5ccd643020cbb20ad5630dabff4bfd0ff8b04a5b0fbcfd1b657b3bcd91dd7` |
| Actual controller receipt | `0b51eb570dd3c3bca1e32480402a749868ba18a4f031fe8b46607616f8e9c32e` |
| Detailed `A/validation.md` | `e3ac38f5a752491cd6ad66d2bf1938086b68977dcd050e5251a4ecd89f759006` |
| Static source `audit.md` | `c612800d4bfd2b5e7c1ea6d2bb7113d2c9541c4fd3d2da8f694c648b7a671150` |

Fresh clone/kernel checks passed in 6.713/41.894 seconds under original guards.
Exclusive owned VM93086 used 12 GiB/four CPUs and default user networking from
00:26:18 to its single SIGTERM at 00:36:28 UTC. Screenshots show real North
America tiles at 00:28:50, profile at 00:29:00 and the readable Google error at
00:29:19. Paris search/photos, GPS, routes and navigation were not repeated here.

Static-whitelist projections preserve selected private broker line numbers in
the immutable UART: action `com.google.android.gms.checkin.START` at
1668/1670/1821/3098/3100; `startCheckinAndGetCheckinResult` at 3109;
`Checkin timed out` at 3131; `setCheckinResult done with result=false` at 3147;
then `finish(resultCode, data) called with result=RESULT_ERROR` at 3151.
Bounded screenshots additionally retain the CheckinApi service class tokens.
Raw app/broker logs remain excluded except hashes and bounded projections.

The 25-class static audit retains fourteen bounded sparse disassemblies, exact
input readbacks and complete selected hashes. Its `final-selected.sha256` is
`024c10a096cdef7083451289fcd0eaa57e1db9e193e86319ce15a78dd5c47442`;
all 25 members pass readback. `Latna.a` distinguishes coroutine timeout text
`%s timed out` from task timeout `%s timed out (Task)` and API failure `%s failed`.
The observed literal matches the coroutine branch. `bitl.f` logs its method
entry before validation and scheduling, so that token establishes no completed
worker, remote status or network result. The actual challenge Boolean was not
captured. Keep every original APK/DEX/tool bundle required by historical auditors.

Later broker lines 3707/3708 record `ANDROID-AUTH-PUMP-FAIL stage=1 status=-1
pending=0` and `ANDROID-SERVICE-EXIT phase=3 reason=5 status=1`. The actual
controller runs 00:26:48–00:34:03, status `failed`, error `GMS broker exited`,
readiness true and broker30630 exit1. It finished before an operator stop command;
this is not a user-stopped successful run. Drain EOF is true, status1, 183,250
bytes and errno0; two cleanup survivors have unknown running/zombie states.
The earlier check-in timeout is not assigned as the cause of this later exit.

The unchanged strict account collector passed 24 entries/2,835 chunks/
1,451,101 bytes, archive SHA-256
`545f5b8a914db60da2c8f80a2fd8688138be19d03d9291925e2a7389da98f29e`.
Import took 317 ms at sampled RSS 28,901,376 bytes, both exits0/cleanup true under
original 600 MiB/300-second/64 MiB-growth/1 GiB-reserve/file-size caps. Linked
snapshots match; final stopped UART equals the complete after snapshot. The stop
tool's post-signal ownership race is preserved; absence and reconcile-stop0 were
recorded at 00:36:38 without another signal or any foreign VM action.

All nine roots, including four clone sidecars and both static audit roots, are
closed. Notes hash is
`fb2c30b803a334d693be2bb5f9276c9f0b61e291eaed554439c6fa91605c4f09`.
One complete seal and separate fresh-process readback passed 636 typed entries.
Manifest `S/maps-preflight-runtime-sealed-2026-11-02-r1/sealed/manifest.json`
has SHA-256 `28daf1e4ab9b70749e77e4e2e0a2c0c26fab0e81a7c0ad70a0d940fcee097a77`.
Seal/readback took 3.596/3.283 seconds; both guard/child exits0, cleanup complete
and zero swaps under unchanged 600 MiB/900-second/64 MiB-growth/1 GiB-reserve/
file-size caps. No import or seal attempt failed. Retention integrity does not
establish successful authentication or identify the missing platform behavior.
