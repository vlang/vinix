# Maps controller diagnostic: panic and absent export

Maps reached onboarding. Retained `maps-after-skip.png` still shows that screen;
the host operator reports the preceding Skip action. Broker screenshots show
authenticator `ANDROID-SERVICE-READY` alongside Phenotype
`Service without Chimera impl` and Chimera
`InvalidConfigException: not migrated with user locked` errors. Readiness does
not establish successful account initialization or authentication.

`broker-terminal-outcome.png` shows controller PID/TID `0xd280` (53888),
`malloc_noscan(0x195)`, a V memory-allocation panic, unavailable backtrace
symbols and return to the shell. This panic is not in UART. Its cause and any
connection to the configuration errors are not established. There is no
complete UART export or imported public result, and no working map, browser
workflow or Google login proof.

External paths below are relative to `/Users/alex/.local/state/vinix/android/`.
The complete closed VM is `maps-controller-vm-r1`; its immutable producer is
`maps-controller-r1`. This audit issued no VM action or compilation.

## Inputs and lifecycle

Controller fix revision: `d6d72faa07e30faf9e441cd7ed57242d28bd1960`.
Complete producer `maps-account-guest-build-2026-10-27-r6` has manifest
`1b8e4555a67eae4c3b1c109f3d94064c96eba65dd3fd3c88d72649b5fdbc9106`;
controller executable is
`894e57f0eaf773777b3107100068edf1f9b57b427b565756767c576a0de8c6b6`.
The [stager](maps-controller-stage.md) retains exactly three overlay files and
changes only two controller executable hashes in deployment metadata. All eight
prior FAT modules, APKs, framework, startup-budget JNI, launcher and fourteen
inherited role bundles remain pinned to `maps-startup-r1`.

| Retained producer or tool closure | Manifest SHA-256 |
| --- | --- |
| `maps-controller-r1` | `3026dfd0e7d69fe81d0b8ba4d504d952fd14fa34d20c9b4cdf6d0b98cc9d857a` |
| `maps-startup-r1` | `f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332` |
| protected-storage framework r2 | `67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938` |
| startup-budget native r1 | `a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20` |
| controller kernel patcher seal | `6150b0b6de62ce91e4ea9bbfafcdfe659aa95f931dc6c3082c5adb849d4c42a3` |
| validated daemon-runner closure | `711c05cc23e68cf81039e37ea0d3d5a92fb52bed8ab083cedaef79cf6153de2f` |

Stager revision is `1d0dc5da7063893dcf9db86d457a09bcf827b777`; executable is
`19d98e797ca4c1ceda5a26d1720c83e1369292dc8d422293fc2fc39f9087525c`.
The dedicated `--maps-controller` patcher is
`715922e210e3d120ac747337a4451875f75629fcf77b943098cd4f9d79467977`,
source `8fe47f2c2b0d5bde73de414491a1a7e214b71ca53396d5dc90009ace16271fe2`.
The complete patcher and frozen PIDFD kernel remain retained.

Owned QEMU PID 3944 launched at 2026-10-27 00:30:36 UTC with 12 GiB and four
CPUs. SIGTERM was recorded at 00:40:22 UTC. The operator reports that the first
stop wrote `stop.json`, then rejected changed live identity during exit.
Reconciliation recorded an absent-PID snapshot at 00:40:36 UTC in `gone.json`.
QMP socket and pid file are
absent; `qemu.log` records signal 15 from PID 44877. No QEMU wait/reap status is
asserted. There is no adjacent stop/reconciliation log; actual receipts remain
inside the VM tree.

| Closed VM receipt | SHA-256 |
| --- | --- |
| `stage-before-kernel.json` | `4b87a00701d732297b702a9dc25326807934053ad224857f6eb8652482f6943c` |
| `kernel-patch.json` | `1cd3e6ac83362e38444d18a987f1a2df69278adbc1824afd94f33c94b7370d45` |
| `stage.json` | `0f81e88c27806ac910804e12fb2630724f1c117e72eabccc68a44872851f2ac1` |
| `launch.json` | `f4ecbab14b2df68cfe4d5fd3c7ff6a785b20bd5742b3b658d4be024169293315` |
| `stop.json` | `ac5453df0de6a03e622d860002848497cbaff2b8a5b47dcaad054f18a84c9502` |
| `gone.json` | `924ec707c17555bbad34f8d76bd9436b990ac7349d23d6d9aef27ba39eead84b` |

Copied runner source/executable match the validated daemon closure:
`c13a45576372481b911e0623dda7b0080438c7c5ba54b668c681459d57b67e12` /
`2419d0760fa92a3e9caa3e60c5596836400616cad8205ca8e6118ade14979908`.
Copied `sha256.json` retains its pre-kernel meaning; the new inventory binds
actual final media bytes.

## Failed collection and observations

Final UART: 48,383 bytes, SHA-256
`c1eed6bfb7c9af154bb84d292eccb127f1b2b4954299f00f7bcc64ec186cdce9`.
It contains no export frame. Automatic account launch failed the SQLite
single-link check at serial line 333; later UI observations come from the manual
diagnostic workflow.

The initial `maps-controller-vm-r1-collect-r1.log` records
`complete export absent`. An independent unchanged strict-collector rerun on
closed UART exited 1 with the same diagnostic and did not create proposed
`maps-controller-results-closed-audit-r1`. The initial proposed
`maps-controller-vm-r1-collect-r1` output directory is also absent. Nothing was
decoded, normalized, recovered or imported.
Reused `maps-account-collect-r2` executable is
`f1245b715d75ab41a6f1c8b3c0d45e1aed9158bfe3cd097c939ee845a3b1b29e`;
older retained source is
`15e78f25a72da1a34ae8bfd7303bebaa8a20a46af4cedc10ac7a4da6bac10990`.
No fresh source-to-binary equivalence is asserted.

Rerun: 0.00 seconds, peak RSS 4,947,968 bytes, zero swaps. Plan-local
`closed-collect.log` / `.time` are respectively
`c428aaa7a8e61644f6d5a0c3911fcf7177049ac872e2b32750224dc8a67440aa` /
`737ff0f19d60143b7a2e92456225e0cffd0c43036fbe847a4c3b5d635f7e0985`.

| Retained PNG | SHA-256 |
| --- | --- |
| `broker-terminal-outcome.png` | `04c421e89d373e4d1a2654a850fbf0331b3807b9b8d34421388d95855b34d7ff` |
| `broker-config-cause.png` | `14d9b8d1e94b725098029d688fac615922b3cec59209b4a043aa0ae36d3056df` |
| `broker-binding-cause.png` | `d0ff86e5cfd387a69e40f0f31e47d59d10b9ffed79191f3cff149611a41d990d` |
| `maps-after-skip.png` | `69a1daed568df704cf4780f3b0d4f73b7cafac3979f400852087dcd590b2075c` |
| `guest-memory-after-controller-panic.png` | `fe67f73eb442d2097cbc0bc9eb7cc72a786f0b805db6b7b76f95b0f79cc243c6` |

Guest snapshot: MemTotal 9,068,432 KiB, MemFree/MemAvailable 4,203,312 KiB,
Slab 32,528 KiB, zero swap and memory pressure. `host-qemu-memory-final.txt`,
SHA-256 `9bf4fe3db72c8b32c6fc484704e6c030f1b8a5bfcd67b14ed487195c09e7bca1`,
records 12,756,288 KiB QEMU RSS. These post-failure samples are not peaks or
proof that the whole guest exhausted memory. Host swap counters are cumulative;
they do not prove this VM caused swapping or the earlier 92 GiB host-memory
report. All twenty PNGs remain retained.

## Bounded integrity closure

The maintained V sealer is from commit `39fc264743f4c211183d8c0a4dd2f75fc7668ea2`,
source `148932aee91df125c2fe56f1631b4c89275868232498c6b92c3530f5415b3a6c`,
executable `b12a4d0b2b133714da6876a0ed5cda623984dc72284c482d8e3ae57975304e77`.
It uses native streaming hashes with a 1 MiB buffer and one bounded directory
list per recursion level. Its unchanged tests passed in the preceding binding
audit; this run reused it without compiling or copying large evidence.

The exact 60 nonoverlapping roots are in
`maps-controller-vm-r1-stream-plan-2026-10-27-r1/roots.txt`, SHA-256
`55d4270c40f23f6b98929b8a1469ff72858a01c15889e03810c4579e6f149c62`.
Independent review passed existence, canonical paths, direct input coverage,
lifecycle, screenshots and report scope. Roots include the complete closed VM,
controller/startup producers, all sixteen direct stage bundle references, old
role/base/headless/request originals, the controller's native-base and companion
originals, stagers/build logs, clone provenance, frozen kernel/patcher, validated
daemon runner, strict collector, sealer and selected host tools.

The historical companion receipts name earlier intent-parcel/text-size producer
inputs and report retaining consumed bytes locally. This audit did not prove
recursive historical producer coverage or a hermetic SDK/C-toolchain/library/
QEMU rebuild closure. Complete original bundles and historical checkers remain
required; none was replaced by summaries or weakened. Older audits are unchanged.

The completed manifest is
`maps-controller-vm-r1-runtime-sealed-2026-10-27-r1/manifest.json`, SHA-256
`f2407f1b7b23ae6c453afef451831e5f24889eee6933f49e79d51441d7ce6da5`.
Seal with internal full recheck and a separate pinned full check both passed:
60 roots, 51,109 entries. Seal took 81.05 seconds, peak RSS 32,882,688 bytes;
the separate check took 39.61 seconds, peak RSS 22,888,448 bytes. Both exited
zero with zero swaps and stayed below 32 MiB RSS. These measured runs do not
establish a universal bound. Post-check `du -sk` records 11,124 KiB of generated
inventory and 52 KiB of audit-plan files. Large originals remain inventoried
in place.

Adjacent execution receipts use prefix
`maps-controller-runtime-stream-2026-10-27-r1`:

| Suffix | SHA-256 |
| --- | --- |
| `.seal.log` | `19a899de384a5eb0c72ced14f6deed717931ac4ad424c681d52f245302fd6b51` |
| `.seal.time` | `30864ec912202f61179f418ab9e9f7e5c4e364a1255af67b92936ab2af6e6734` |
| `.check.log` | `ed53a4e22fd32894d62e7350791204dab3d148e641765e45c82609bd4420912a` |
| `.check.time` | `33b931d8e6cc74ccb7bde5504531472b7864e66cab3ad6f600f9e88a35898f8e` |
| `.du.log` | `f98fc64b4af2a38895d7e5c9e127ed12eb3e05a5bd61d9186ec7ff20cb55e459` |
