# Native Maps onboarding trace runtime, 2026-10-27

The second native trace attempt did not reach Maps onboarding. The operator's bounded
GUI diagnostics identified missing `android.provider.Settings$Global.putInt` in
the broker; a later Maps launch reported `No such file`. Strict UART collection
failed, so no public broker receipt, readiness, terminal status or authentication
result was imported. No working map screen is established.

All artifact names below are under
`/Users/alex/.local/state/vinix/android/`. The immutable stage is
`maps-native-onboarding-trace-r3`, source revision
`1fefb8dc2844175cb579b2cb7e5311f2241d8d21`, inventory SHA-256
`96b90172e338080ff50bf0e1188bdefc1f50e61fe3ad654593dfbac4d918d741`.
It retains the complete r8 controller and r5 native producer, whose manifests
are respectively
`c2c08ed987052e5170f9b90cd4af7f9de6fcb4e98684def4dc5e28f058409b4f`
and `05baf5d011337d54aab26f6cc3c535f801221d51aceb966ebc9442d88b5fd6b8`.
The frozen kernel is
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.
No equivalence to the concurrently edited checkout is claimed.

Both attempts are retained as `maps-native-onboarding-trace-vm-r1` and `-vm-r2`.
The second clone receipt SHA-256 is
`d0c24f26723e0a27ae4da475853e75a30d6a893e3c3d056e34ace83cf3cb44b8`;
its `kernel-patch.json` is
`1b51cf146b47cc33f8b820b28c8deedcfdb8cfab55e84fbe2b22eccaaf0fcc6f`.
Complete preparation tools, commands and bounded receipts remain in
`maps-native-onboarding-trace-build-2026-10-27-r1` and `-r2`, with both adjacent
clone source closures preserved.

| Exact UART snapshot | Bytes | SHA-256 |
| --- | ---: | --- |
| First attempt | 46,339 | `930ddf65f1711e8146b8440abb8c5cb045e0487c6634bbf8744eed5bf438a841` |
| Second attempt, failed import | 2,277,070 | `0e96fd49ba0b768e5da2b93af695a1c6f8dc22bebeec1c55c697096033bed8e0` |
| Second attempt, final | 2,277,514 | `3d7c3efb83d7dd6beeb1486738e657b7739a0c8205ebdcd3a6fc52885d596ab7` |

First-attempt PID 28559 disappeared without owned stop/gone receipts; QEMU
recorded SIGTERM from PID 409, whose identity and reason remain unknown. There
was no canonical account export BEGIN or END.

The second export had matching BEGIN/END declaring archive
`2532b6fbe57b11c0b2526e3b8ab425f180a6c79f3f6e6431ff2de30b1d653100`,
1,439,735 bytes and 2,812 chunks. The unchanged historical strict collector
(`f1245b715d75ab41a6f1c8b3c0d45e1aed9158bfe3cd097c939ee845a3b1b29e`)
exited 1: `unknown export frame at serial line=4135` (0.28 s, 16,285,696 B
peak RSS, zero swaps). No public-results directory was emitted. The original
snapshot and failure are unchanged; no frames were repaired or reconstructed.

Payload-free V analysis classified line 4135 as an anchored CHUNK record with
ten fields, lengths `[5,64,4,546,7,7,8,7,4,4]`, instead of four. Its intended
payload field contains a non-base64 printable character followed by additional
lowercase word fields. Nearby valid-shaped CHUNK lines 4133/4141 have lengths
`[5,64,4,684]`. This explains strict rejection; the source of the additional text
is unverified. Complete analysis source, binaries and bounded build receipts
are retained. No field bodies, decoded payload or private logs were displayed.

SIGTERM was requested for second-attempt PID 47741 at 09:04:58 UTC. The initial
runner exited 1 during post-signal ownership reconciliation; QEMU logged signal
15 from PID 72514. A separate process check found PID 47741 absent. The existing
`reconcile-stop` action subsequently passed without another signal; its
ownership-bound `gone.json` records 09:09:21. The initial ownership difference
remains unexplained; no QEMU reap status is claimed.

Bounded GUI evidence remains in the second VM root, qualified as operator
observations rather than a successful strict import:

| Screenshot | SHA-256 |
| --- | --- |
| `broker-failure-types-01.png` | `05d9bbaae9215b73a066c4f560e156cecee3c18d887efd9d2c61829497b693ff` |
| `broker-failure-receipt-01.png` | `0a74e48bf5dc30fd601f22135d0b8d048782a187b62eef75e9935a234b6bfc3f` |
| `maps-launch-02.png` | `78840b3d041a007e8d5c2f2cb4ccd1f3a932af2d8f080f0255dc494db40f38ae` |
| `maps-exit-files-01.png` | `1783574837d260a131fddf32863fdfb1e87521b8183636eacb1e8bb1b015d132` |

The audits are `maps-native-onboarding-trace-runtime-audit-2026-10-27-r1` and
`-r2`; their observations, exact snapshots and commands remain outside Git.
The complete seal is
`maps-native-onboarding-trace-runtime-sealed-2026-10-27-r1/manifest.json`,
SHA-256 `83465abd4a8a57942769d6694d390186724b11fbf1a7cd5ee5b06926bde76cff`.
It covers 18 complete, nonoverlapping roots and 5,783 typed entries, including
both runtime attempts, preparation inputs, clone source closures and interaction
tool. Streaming sealing and its internal readback passed in 15.69 s,
27,344,896 B peak RSS, zero swaps. A separate agent's complete readback passed
in 14.05 s, 23,117,824 B peak RSS, zero swaps. Exact commands, exit status and
execution-log hashes are in the adjacent `-execution.txt` record, SHA-256
`91f20d6abbfcc362c1c308e0100aae981de2848b615440e035d948d837af0dbe`.
