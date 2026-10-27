# Maps startup-budget diagnostic: closed run and strict import

The credential-free broker reached actual authenticator binding readiness:
`broker-binding-markers.png` shows `ANDROID-SERVICE-READY` for
`GoogleAccountAuthenticatorService`. It then failed with
`NullPointerException: A Chimera Context is required` in
`AbstractGmsTracer.<init>`, through `GmsModuleProvider` and
`ContentProviderClient.call`, and exited. The exception screenshot also shows
self-kill/System.exit/VM-exit output; its zero exit marker does not establish
successful startup. The public result is `status=failed`, `broker_exit=1`,
`cleanup_survivors=0`. Its `service_ready=true` denotes transport-listener
readiness; the separate screenshot supplies the stronger binding observation.

The automatic Maps-account launcher failed the SQLite single-link check at
serial line 319. The later controller retry failed with
`fresh compositor surface required` at line 360.
There is no `maps.log` in the 23-entry public export. No working Maps, browser
workflow or Google authentication is established. Empty initialization-failure
arrays in the public receipt do not establish successful initialization.

External paths below are relative to `/Users/alex/.local/state/vinix/android/`.
The complete closed VM is `maps-startup-vm-r1`; its immutable producer is
`maps-startup-r1`. This audit issued no VM action or compilation.

## Complete inputs and lifecycle

The producer/stager implementation revision is
`85cdab8c6ff830ede63e853ef499c39f7d946a2b`; retained stager source SHA-256 is
`1085f7065093dc5c4a39ef8a7ee246fac23355352302cfccbf2ca5b02ecc512a`.
The `protected-storage-map-stage-r6` executable is
`a6880d56310a565e655da5559832ab28b75c2b989fdd4bb31fc24cc63970e073`.
The producer retains the exact nine-file overlay, seven original FAT-module
identities, complete role checks and readbacks documented in
[the preparation report](protected-storage-map-stage.md#separate-service-startup-budget).
The diagnostic couples the protected-storage framework with the new JNI;
this runtime run does not isolate either input.

| Complete input | Historical manifest SHA-256 |
| --- | --- |
| `maps-startup-r1` | `f79065bc79d816f8cf35a21c72ef375369229b0ee8170165890808e3d194e332` |
| `maps-account-r5` | `9a8bf61bd526d7ec020d45920367d45e90a2ef4692c6d8fa8b87de801a14c5ca` |
| `combined-account-webview-protected-storage-framework-2026-10-27-r2` | `67e1cb450fa87305c99480133084b7f9cb684feeeaa2e0c3efa3007ab43ee938` |
| `current-native-build-2026-10-27-startup-r1` | `a62bf4a8a4ef8d1c000f82395ec64b145c9c4d6df25f12077f75d96d341e0a20` |
| `maps-account-daemon-runner-closure-2026-10-27` | `711c05cc23e68cf81039e37ea0d3d5a92fb52bed8ab083cedaef79cf6153de2f` |

Framework source revision is `8fa48d6081fbc1fa95e3e335b0c1e04bf288bc97`;
JNI source revision is `302628d15c27306e6f394237010af59fdd63a413`.
The frozen PIDFD kernel and complete startup patcher are retained. Patcher
executable SHA-256 is
`48cdde112d338f1b94575344e9b71ea2a0825e190624eecfb86648d532d40523`;
its separate seal manifest is
`24c41639ecc1f144e01cebe2ad874b2213718222c34ce1cea004bf2bf1e25cad`.

Owned QEMU PID 17583 launched at 2026-10-27 00:00:59 UTC with 12 GiB and four
CPUs. The checked SIGTERM request was recorded at 00:08:42 UTC. The first stop
wrote `stop.json`, then refused differing live identity during exit. Later
reconciliation succeeded without another signal; `gone.json` records an
absent-PID snapshot at 00:08:49 UTC. The QMP socket and pid file are absent.
`qemu.log` records signal 15 from PID 43571. There is no adjacent reconciliation
log; the retained gone receipt supplies that outcome. No wait/reaped QEMU exit
status is asserted. Launch-result code zero describes daemon launch.

| Closed-run receipt | SHA-256 |
| --- | --- |
| `stage-before-kernel.json` | `8e38e72e13aafaa52d3be03799364fc2bbb28f710158fe6762e0303b40748ca2` |
| `kernel-patch.json` | `7cd85be5272083d93c6368c17c17f3f8a121068dcac1259efc6758f3ae9370fb` |
| `stage.json` | `0433d99da6efc806a76f7ee56caedd5494a4714bbbc3e7c1f11981a9b1f938ef` |
| `launch.json` | `839f942c5106b7e7cef49974d124f79a98b874c2cd238190765d4185e7632f70` |
| `ownership.json` | `c7b22e3af7971ccfae52e24ba32cf6e849413de3a10256079005261087777a2a` |
| `stop.json` | `c995dfe9ce42ba0a02b3c4a0b446ef799c479bf25746bf1377cead79fd333322` |
| `gone.json` | `59c3c45b995f8883391928fcb116f3c133f62ab32c192acb33d29e5a0a9600c3` |

The copied VM `sha256.json` keeps its historical pre-kernel meaning. The new
streaming inventory binds the actual closed media. Copied daemon runner source
and executable match the validated closure: respectively
`c13a45576372481b911e0623dda7b0080438c7c5ba54b668c681459d57b67e12` and
`2419d0760fa92a3e9caa3e60c5596836400616cad8205ca8e6118ade14979908`,
revision `1733801d2`.

## Exact imports and observations

The final UART is 2,273,078 bytes, SHA-256
`71bed576f3c73fea198767c8b574cbf19c57d8e0f11a68bd348d0f282fd65cd7`.
BEGIN/END at serial lines 371/6001 announce the archive verified by the strict
collector: 1,440,700 bytes, 2,814 chunks, 23 entries, SHA-256
`fdebe2ae6aa1ad4f378437835b1d698ef68fc7f5d769f67018e6c71263b1cc75`.

Original `maps-startup-results-r1/import.json`, SHA-256
`551d7da107f9bf9ada5afb6967fbd4ccc1a118a28679f2a88f5576ef54f65183`,
binds an earlier UART snapshot,
`bb17014a1a9980fe87f4a7d840a292e1dfffbfc11df61ce6683ba5a760f14cd3`.
A fresh unchanged-collector rerun on the closed UART passed with the same
archive into `maps-startup-results-closed-audit-r1`; its import SHA-256 is
`d0e1064a885c90844b76dca8fabb8d34719516c341d5bf2ddc994339c76659b6`.
Both complete imports remain unchanged, with no normalization or recovery.

The reused `maps-account-collect-r2` executable SHA-256 is
`f1245b715d75ab41a6f1c8b3c0d45e1aed9158bfe3cd097c939ee845a3b1b29e`.
Retained older source is
`15e78f25a72da1a34ae8bfd7303bebaa8a20a46af4cedc10ac7a4da6bac10990`;
no fresh source-to-existing-binary equivalence is asserted. The closed rerun
took 0.36 seconds, maximum RSS 28,065,792 bytes, zero swaps. Plan-local
`closed-collect.log` / `.time` pins are respectively
`3f3f0f1991eae8c692bd17c55d68de00cd0f628b03dc37e40ccfaa076346bd2e` /
`d3eb3a5751b3e93d25c341cd98e476659ecc633f7289f25038e8c72f4466a972`.

The public export contains the private broker-log hash
`f12aac1be33f67ddf943aac5c89e30fe4f5f38e610e353446abe5df0bd9d7e27`;
the full private log was not imported. `guest-memory.png` shows
MemFree/MemAvailable 8,443,680 KiB, Slab 19,216 KiB, Swapped 0,
VinixSwapErrors 0 and VinixMemoryPressure 0. `host-memory-before-stop.txt`,
SHA-256 `83ee146b5513e520ef42add94f193d82b5205e6aeea008eefabd4e5f3c9a8ab2`,
records a 12,755,584 KiB QEMU RSS sample. These are post-failure snapshots,
not peaks or an explanation of the user's earlier host memory exhaustion.

| Retained PNG | SHA-256 |
| --- | --- |
| `broker-binding-markers.png` | `4620750583ecc5b7e6787fd3f3af1f690fd13770748165d4145219f7cd86e203` |
| `broker-exception.png` | `1d9fd52bd1c480edc914bf13bd780c089b982926eeb81c7982e6013024c6c511` |
| `guest-memory.png` | `b278c46cb06c9694f86d52f7a6d2363ca7f21d0cefc24e281406974982666033` |

All 13 PNGs remain in the complete VM inventory. A second agent independently
checked these screenshots, lifecycle links, runner identity and result scope.

## Bounded integrity closure

The maintained V sealer is from commit `39fc264743f4c211183d8c0a4dd2f75fc7668ea2`,
source SHA-256 `148932aee91df125c2fe56f1631b4c89275868232498c6b92c3530f5415b3a6c`,
executable `b12a4d0b2b133714da6876a0ed5cda623984dc72284c482d8e3ae57975304e77`.
It streams large files through a native 1 MiB buffer and holds one bounded
directory-name list per recursion level. Its unchanged mutation/self-test
passed during the preceding binding audit; no image or original input bundle
was copied for this closure.

The exact 53 nonoverlapping roots are in
`maps-startup-vm-r1-stream-plan-2026-10-27-r1/roots.txt`, SHA-256
`d17759f9bd0ce111717ec4cec8d7ab949ee088b3721c62f50d87122f41d39372`.
Independent review found no missing mandatory direct bundle or overlapping
root within the stated selected-tool scope.
They include complete original role/base/headless/request bundles, new
framework/JNI, closed runtime and both imports, every existing adjacent runtime
provenance path, compile/prepare logs, frozen kernel/patcher, daemon runner,
strict collector and selected host tools. Historical complete bundles and
checkers remain required. SDK, C-toolchain, shared-library and QEMU rebuild
dependencies are not a fully hermetic closure. Older audits remain unchanged.

The completed manifest is
`maps-startup-vm-r1-runtime-sealed-2026-10-27-r1/manifest.json`, SHA-256
`8fd2871de8f17da013ab704ca0dba9e08b8e6d146ef8d8772bf04699d846d363`.
Seal-with-internal-full-recheck and a separate pinned full check both passed
over 53 roots and 36,811 entries. The seal took 56.74 seconds, maximum RSS
34,373,632 bytes; the separate check took 21.39 seconds, maximum RSS
22,085,632 bytes. Both recorded zero swaps. These runs stayed below 33 MiB
RSS; they do not establish a universal bound for arbitrary trees. The
post-check disk sample records 8,076 KiB for generated inventory output and
40 KiB for the audit plan (`du -sk`). Original complete evidence remains
inventoried in place; no large media or role bundle was duplicated.

Adjacent execution receipts use prefix
`maps-startup-runtime-stream-2026-10-27-r1`:

| Suffix | SHA-256 |
| --- | --- |
| `.seal.log` | `40aeb8675f2061eeced9605f675fbfe009bef0a4eb66f7b85735ad6995398c4a` |
| `.seal.time` | `7bffd6a453ff688c7f939027eabe0307c7f5dfb6ff7dda2b6d066af223010b54` |
| `.check.log` | `e8767e9fc5b1c6762abe304931fe36a655a957e669c934d9eb8147fb1fb642d3` |
| `.check.time` | `386bf0e9945554f491220e07da37d5fc992c760ed3546f8cdea98af7bfd8d026` |
| `.du.log` | `324571ef69fdc40216c530bc52b55988c47e4a1a5ac8b0b2bf07df6f76996d3f` |
