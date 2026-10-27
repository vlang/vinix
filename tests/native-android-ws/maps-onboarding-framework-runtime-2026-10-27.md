# Onboarding framework runtime, 2026-10-27

The ARM child-attachment and Settings.Global fixtures passed. Play Services
attached, and Maps rendered onboarding, but an unoccluded Skip attempt left
onboarding visible. The input/callback route remains unresolved; no working
map screen or Google authentication is established.

All artifact names below are beneath
`/Users/alex/.local/state/vinix/android/`. Stage `maps-onboarding-framework-r1`
records source revision `b64291c5bba76c5799136982c7fd48ef459ffd5c` and inventory
SHA-256 `fcba5511b0cc2d305ee6e3ba48081bf6bc40fd6117cd91abc691fb2fd7ad01cf`.
It contains the child-attachment fix (`f908b4c92`) and Settings.Global.putInt
compatibility fix (`c2347e9c9`). Framework JAR SHA-256 is
`e7d7d590da1ae5f9eb8f9f27aae0c003a30f10f5d79effc0c63f463f958263fd`;
frozen kernel SHA-256 is
`a54505e3725e11bb2f769d62c1260f0b447a4d9fbcde21ba7f9119e08ba75151`.
No equivalence to later checkout changes is claimed.

The fixed-12-GiB VM is `maps-onboarding-framework-vm-r1`. Its adjacent clone
receipt SHA-256 is
`a9ad232ce4bc3f8d8721ac8ca18e2251cbb0e4e4c8d70893c57562485ca743ec`;
`kernel-patch.json` is
`06d19f04dd0f881e42c963ffb70b42f24c847130a0a701478d4bbd472f53735f`.
Complete preparation tools, source closures and commands remain in the stage,
`maps-onboarding-framework-build-2026-10-27-r1` and
`maps-onboarding-framework-runtime-build-2026-10-27-r1`.

Fixture setup initially failed for missing dedicated identity 10117, then
missing executable-memory mount policy. Both failures were retained. After
provisioning and the existing scoped runtime policy, both fixtures returned
wait status 0 under UID/GID 10117. Their public receipts passed all eleven
source-defined checks: one PASS and READY, bounded output, input lifetime,
EOF drain, clean exit, isolation, explicit activity/environment, descriptor
closure and unchanged pinned inputs. This validates the fixture contracts,
without establishing SettingsProvider persistence or account authentication.

| Fixture | Exact UART interval SHA-256 | Derived archive SHA-256 |
| --- | --- | --- |
| child-attach | `886465827f76a28b866044bb10eef509809e618594e9f507ed599e5d5afe819e` | `09fa68e0c067eed4808d1b4f28bec3c30258d9eb19f41cbb1b9019604867f9cc` |
| settings-global | `0e867dfb044acfb888cc027e14f480004bc842dc90a0fb8ee7ccacdda37d2b49` | `c500cc3625fbdeee0e3be530c8702684a5bb2738488fec44514855616b1400c2` |

These used the committed no-removal plan writer (`f983dec15`) and unchanged
v2 diagnostic derivation with `removals: []`. No byte repair occurred. The
historical strict collector lacks this fixture export mode, so no strict
fixture import was attempted; the derivation's historical strict-failure
scope text is not a new failure here. Four guarded commands passed; maximum
RSS was 3,915,776 B with zero swaps. Independent review checked both
receipt contracts, pins, interval/archive chains and command results.

An initial broker attempt failed because the fixture runtime remained mounted
read-only; its separate interval is preserved. After unmount/retry, the final
public account receipt covers 09:48:54–10:03:52 UTC, reports
`service_ready=true`, empty nontruncated initialization failure lists, and
`user-stopped-no-authentication-claim`. Readiness establishes transport
attachment. The public launch receipt literally selects
`--vinix-app=vinix-android-calculator`; fresh GUI captures show Maps. Its
desktop/apphost executable SHA-256 is
`6a48bc4174eccc330606629b99cd266989c80bde894e7ff7beed07f67b45c2c2`.

The operator raised Maps at 09:57:52 UTC and clicked Skip at (576,149) at
09:58:05. The 09:58:29 capture still shows onboarding; the later exact INPUT
query showed no output. These are bounded GUI observations, not proof of a
delivered callback or a diagnosed cause. The earlier TLS sample was historical
and does not establish a current blocker.

| Screenshot in VM root | SHA-256 |
| --- | --- |
| `maps-raised-01.png` | `df66952d1d50f2bbfceb04d4853f1c3bb83e42bcaff3d8c7c95b5112d8998c9d` |
| `maps-raised-skip-01.png` | `d6acb4e6b88f30ee811a6f82bebd039495a9252ff0f822fe2e0988aea1b19995` |
| `maps-raised-input-query-01.png` | `b950c5c54e1e04f96680bf5912dff854759bfbe9cc41735ca7b228016d522d53` |

The final account export completed before host VM stop, with no Terminal input
during export. The unchanged historical strict collector passed: 25 entries,
1,442,378 archive bytes, 2,818 chunks, archive SHA-256
`49db80a002ee791530aaf5707b86f56b3e2291d1610493cbdff06d65d0e2a2dd`.
The exact 2,238,442-byte interval SHA-256 is
`66c02aba1c78b5415d82ae60c65d17812a1ff8652a9e4455a0d7c53dd4823440`.
Strict import took 1.00 s, 27,459,584 B maximum RSS, zero swaps; guard and child
exited zero. Snapshot child exit was zero, but its outer guard exited 125
because the RSS monitor timed out. That failure is retained; complete hashes,
independent suffix comparison and strict import verify the capture.

Guest cleanup is a separate limitation: `broker_exit=137` followed SIGKILL
cleanup, and `cleanup_survivors=2` caused guest-controller exit 1. This count
can include unreaped/zombie entries; it does not prove two running processes.
No clean guest shutdown or zero-survivor result is claimed.

Host `stop.json` requested SIGTERM for PID 64489 at 10:06:15 UTC. The first
runner call exited 1 during post-signal ownership reconciliation. QEMU logged
SIGTERM from PID 64894, whose identity is unverified. Existing reconcile-stop
then passed without another signal; ownership-bound `gone.json` records
10:06:43. A separate process check confirmed absence; no reap status is claimed.
Final UART remains exactly 2,340,825 bytes, SHA-256
`53944a4b03192421cad51bfa185a8ba77c8c673d65329bf567e04b5f6b9c4509`.
The post-stop delta capture correctly refused because no bytes had appended.

Complete evidence and exact command receipts remain in
`maps-onboarding-framework-runtime-audit-2026-10-27-r1`. All GUI captures and
interaction command provenance are retained in the complete VM/tool roots.
The complete seal is
`maps-onboarding-framework-runtime-sealed-2026-10-27-r1/manifest.json`, SHA-256
`8c51bbdaae1e16286f5689b4ebb6097533071360dd454100a33a80a8cbb7304a`.
It binds 40 nonoverlapping complete roots and 17,657 typed entries. Streaming
sealing and internal full readback passed in 20.18 s, 27,721,728 B maximum RSS,
zero swaps. A separate agent's complete readback passed in 14.26 s,
23,330,816 B maximum RSS, zero swaps. Exact commands, limits, exit status and
log hashes are retained in the adjacent `-execution.txt` record, SHA-256
`4f3afe3739f2776cc24ffcc0866941da09feb381f98f69352e6964d7eeac08d8`.
