# Maps native heartbeat runtime, 2026-10-27

Maps remains on onboarding after Skip. Native diagnostics show a stalled web
stage with readable queued input. The deployed browser's unsigned deadline
subtraction can turn an expired timeout into an infinite poll, consistent
with the measured wait. Exact userspace call-site attribution and a successful
correction still require a new deployed run. Google authentication is unverified.

All artifact names below are under
`/Users/alex/.local/state/vinix/android/`. The frozen 12 GiB VM is
`maps-native-heartbeat-vm-r1`. Stage `maps-native-heartbeat-r1` records source
revision `abc45f8cb630b24f4fe5143242119b7be49739c1` and inventory SHA-256
`70ea9f41ad045541066dec75a1ddcdc1e44efefd8d35ffb2e4414a77e2235b32`.
Native producer `current-native-build-2026-10-27-heartbeat-r1` records revision
`20661008884fcdf876d24c8110a1a15178d49e26`, inventory
`6619a4cd8dcc7e30aa43120494b874f230d1e9b8ee5c5b756e25fcf5e5148eae`,
and shared-object SHA-256
`3ac3ec1a026a409ec52b7973d9dcc4593bd5d266fc2c6e77fc5d5c1a88e439d9`.
Complete source closures and commands remain in that producer, the stage,
`maps-native-heartbeat-build-2026-10-27-r1` and
`maps-native-heartbeat-runtime-build-2026-10-27-r1`. Later checkout edits are
not part of this deployment.

The operator clicked Skip at (576,149) at 10:36:02 UTC. The 10:36:08 capture
still shows onboarding. A bounded Terminal query shows stage=web,
progress=2911, stable=1, with age_ms increasing from 23702 to 53704. Separate
nonconsuming MAIN-POLL samples change from poll=0/revents=0 to poll=1/revents=1.
The stage snapshot precedes polling; readable input establishes queued bytes,
without proving callback delivery or consumption. The sampler lasts five minutes.

Exact UART sysrq metadata at line 660 records main PID/TID 62935, parent 54085,
AArch64 syscall 73 (ppoll), descriptor count 1, null timeout and null mask.
This establishes an infinite ppoll wait at that sample, without a userspace
stack or browser-descriptor attribution. SIGQUIT was requested at 10:40:12;
the subsequent native-frame query was empty. No SIGQUIT stack is claimed.

| Screenshot in VM root | SHA-256 |
| --- | --- |
| `maps-skip-01.png` | `c89fb9ea585a5b7911259f17595e482b73629f875df90caf50c31ef00ece2e56` |
| `maps-heartbeat-query-01.png` | `d4f68cbe5edc3a7705dc07f52d96070fa2f2ae73795d5e9563986cd74c15f608` |
| `maps-native-stack-query-01.png` | `7d92373bac2250849accb3e2be7801c8bea57963e1b658aedf5b0c31b6da50e9` |

The public deployment pins browser shared object
`ad55dfd4d1e7fd11e092ef75bada71eb4c176845451b80dc023eb98c20a2935b`,
matching complete producer `current-browser-build-2026-10-26-r2`, revision
`1c6a46a51dcb1b342c3d6aaea4f0f532a28e6adc`. Its retained client source hash is
`4713f03a07aba207f335e68b4dea486290851134525851b8f19206b579088e35`;
`generated/browser.c` hashes to
`b7c03fa33ef2563c6a41670b1c621dce5ca6af72f062212134760a2fdefdd22e`.
At line 10385+, `browserclient__ready` subtracts current milliseconds from
a u64 deadline and narrows the result to an i32 poll timeout. Underflow can
produce a negative timeout, including -1. Independent source review confirmed
this mechanism; it does not substitute for validation of a rebuilt browser.
The complete host bundle `main-heartbeat-checks-2026-10-27-r3` passed its
instrumentation checks, including snapshot-before-poll and preserved input;
its four adjacent original build/run receipts and logs are retained too.

Host fix `9f01a1edb` now checks expiry before subtraction and clamps before
narrowing. All eight focused host tests and generated-C checks passed against
client source `3d40120b6b3c8c3fd60d54fed64977476d588f88b39665e2766a132507a74513`.
Complete separate evidence is `browser-deadline-host-2026-10-27-r2`, including
`validation.md` (SHA-256
`3df486c22ae870a9dac458bbe1d8f527bc9b2ddd56ad4bfc363db5fffe7e19b7`),
and its adjacent `-build`, `-run`, `-generate` logs and guard receipts. This
evidence is outside the runtime seal plan; ARM/Maps validation remains pending.

The unchanged historical strict collector passed: 25 entries, 1,441,928 archive
bytes, 2,817 chunks, SHA-256
`7fbdadab49307dc202689ee445605f9bed969bd51b773aba8c1d222c19d2901f`.
The exact 2,256,759-byte suffix SHA-256 is
`12be7a40e7b4a1ca55a1230c8e13e7b3dbacbb22f89f4cfb53e567266e667f9a`;
the full 2,305,151-byte UART SHA-256 is
`3ad0c2116246839d8ac4d369ca139dfdef18d7b44aefeef97cdefb5e2b0f1dea`.
The original interval passed directly to the unchanged strict collector,
without frame removal, repair or diagnostic reconstruction. Independent review
recomputed hashes and compared the baseline prefix and captured suffix.
Snapshot and strict import guards/children exited 0 with cleanup complete.
Maximum RSS was 17,481,728 B and 26,886,144 B respectively, zero swaps.

The account receipt covers 10:30:21–10:42:20 UTC and reports GMS transport
readiness and `user-stopped-no-authentication-claim`. `broker_exit=137` and
`cleanup_survivors=2` prevent a clean guest-shutdown claim; survivors may include
unreaped entries. Private Maps/broker logs are excluded from the public archive.
Diagnostic values above come from pinned bounded GUI captures and sysrq metadata.
Host SIGTERM was requested at 10:42:59; ownership-bound `gone.json` records
absence at 10:44:56 after successful reconcile-stop. An independent process
check confirmed absence, and final UART exactly matches the snapshot.

Evidence, selected hashes, complete interaction provenance and exact command
receipts remain in `maps-native-heartbeat-runtime-audit-2026-10-27-r1` and the
frozen VM/build roots. Its reviewed `roots.txt` specifies 41 complete roots.
After a disk-space hold and recovery, the bounded streaming seal attempt
`maps-native-heartbeat-runtime-seal-2026-10-27-r1.json` stopped after 4.713 s:
observed shared disk growth 37,220,352 B exceeded its 16 MiB limit. The guard
exited 125, child 137, cleanup complete; minimum free space was 1,450,995,712 B,
above its 1 GiB reserve. The incomplete output and exact receipt are preserved.
No complete manifest or full readback is claimed. Complete sealing remains
pending; a later retry preflight found only 250,784 KiB free and did not launch.
The individual hashes, strict import and independent review above pass.
