# Maps onboarding trace runtime, 2026-10-27

Maps rendered onboarding in the fresh trace VM. Screenshots after Sign in and
Skip still show onboarding; Android touch delivery and callbacks remain
unverified. No account authentication or working map screen is established.

The immutable stage is
`/Users/alex/.local/state/vinix/android/maps-onboarding-trace-r2`, prepared from
source `527981b8cf3961a889dcbc2de83553e33d3f2b97`; its manifest SHA-256 is
`de315f3f5f0120efbd1368a47e11db945aa9212160fc7e1ff351e522e9435be5`.
Its complete controller producer is `maps-account-guest-build-2026-10-27-r8`
under the same external Android state directory, manifest
`c2c08ed987052e5170f9b90cd4af7f9de6fcb4e98684def4dc5e28f058409b4f`.
That producer retains its actual source closure and records build revision
`d7fcf435ace7f024ce6d7a0b5f44a7b0b97a5539`; no clean-HEAD equivalence is claimed.
The audit observed repository HEAD
`1c9f30f96c50cf02f6989b195ee4b365960f3160` in the shared checkout.

The mutable copy is
`/Users/alex/.local/state/vinix/android/maps-onboarding-trace-vm-r1`.
Fresh cloning and frozen-kernel installation passed with zero swaps:

| Evidence | SHA-256 | Time / peak RSS |
| --- | --- | --- |
| Adjacent `maps-onboarding-trace-vm-r1-clone.json` | `a28a4c7965ec156959d0116f2c6331c1a2829c65a8270cb04b9162045f982ca6` | Clone: 12.70 s / 34,881,536 B |
| Build root `fresh-clone.log` | `5f1abd484fe77a960d5b7dd751f56879addc756df44c5e13e8b303a6d1ff3b73` | Same execution |
| VM `kernel-patch.json` | `5e79a7bf2fdd5370e5cf8507d1e33072978c1ba3497330cea3095ea33dbb58da` | Patch: 149.96 s / 42,713,088 B |
| Build root `fresh-kernel-patch.log` | `1d1955042d72318060643846567bd37bdcd420c834bb82a59f933a5f5423963f` | Same execution |

The build root above is
`/Users/alex/.local/state/vinix/android/maps-onboarding-trace-build-2026-10-27-r1`.
The installed kernel SHA-256 is
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`,
from source `ecbd3964aff243304e16df45271c7de8dee4d2da`. Its patch receipt binds
the preserved controller, framework and other staged payloads.

The parent operator recorded broker start at 06:59:49 UTC and the actual Maps
desktop launch at 07:06:09 after correcting an earlier Calculator click.
Onboarding rendered at 07:08:30. Sign in was targeted at `(438,590)` at
07:08:54; Skip at `(602,149)` at 07:10:39; the corrected screenshot-only driver
targeted Skip again at 07:15:50. The observed client rectangle was
`198,95,480,640`. Independently inspected `sign-in-click-01.png`,
`skip-click-01.png` and `skip-screen-only-01.png` all display onboarding.
These are visible-state observations, with coordinate and callback uncertainty.
Summarized private-screen diagnostics do not establish callback execution.

Both complete interaction-tool bundles are retained under the same state root:
`maps-interact-client-rect-2026-10-27-r1` (`sha256.txt` SHA-256
`585631000e1f4d4674331425cef0d455681860cf20dc0da2e8d139facd830213`) and
`maps-interact-screen-only-2026-10-27-r1` (source commit `1c9f30f96`, manifest
`2014f629db01ce23de5cead33883b7b9a1a267b1aae01a54925d27e993737eca`).

SIGTERM was requested for the owned 12 GiB VM, PID 40752. Both `stop.json` and
`gone.json` record 07:17:15 UTC; a separate process query confirmed absence.
No QEMU reap status is claimed. The exact final UART is 1,033,060 bytes,
SHA-256 `82ad0d5e49eb1eb7328f7e32a479c1e4f741c5e39d3c6f06dbe1f403cae8a247`.

The unchanged historical strict collector rejected this UART at line 876
with `unknown export frame` (exit 1; 0.42 s; 8,175,616 B peak RSS; zero swaps).
Its fresh self-test passed all five supported protocol families. An anchored,
metadata-only scan found a BEGIN declaring archive
`b3dcd088d10dcab8a85ce15b87c2d8f146e2dd7c399128eae6e5db3abd805b31`,
1,441,575 bytes / 2,816 chunks, but only 1,234 anchored Maps-prefixed lines and no
canonical END. No public broker receipt was imported. Readiness, trace selection,
terminal broker status and authentication therefore have no imported receipt.
No incomplete archive was reconstructed; the failed import and original UART
are preserved. Private Maps and broker logs remain excluded from public import.

The fresh audit is
`/Users/alex/.local/state/vinix/android/maps-onboarding-trace-runtime-audit-2026-10-27-r1`.
It retains the exact snapshot, collector failure, fresh self-test, bounded
metadata observations, tool identities, sealer source, selected hashes, clone
proof and commands. Complete producer bundles remain required by their checkers.

Streaming sealing and a separate complete readback passed for seven roots /
3,842 typed entries at
`/Users/alex/.local/state/vinix/android/maps-onboarding-trace-runtime-sealed-2026-10-27-r1`.
The seal manifest SHA-256 is
`2ec30d7cc4007a4a9838a8f7c1af5b80499494bfbadf5e396b0f35d3d8bbafca`.
The roots are the audit, stopped VM, immutable stage, trace build tree,
controller producer and both complete interaction-tool bundles. Seal and
independent check took 15.98 / 10.01 seconds, peaked at 22,216,704 / 22,904,832
bytes RSS, and reported zero swaps. Adjacent `-seal.log`, `-seal.time`,
`-check.log`, `-check.time` and `-execution.txt` preserve actual commands/results
outside the frozen roots. Earlier runtime bundles and failed stages are unchanged.
The supplemental execution receipt SHA-256 is
`3fb5999998aaf6e22969e4d7d8ceba4e4492edb514743c97fd128917a03c3fa6`.
