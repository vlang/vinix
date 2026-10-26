# Main-looper service stop regression361

Fix `7079baa11b9f728951037213c5699811f056a7fb` moves worker-thread
`Context.stopService` execution onto the main looper. The existing service lookup,
started-state update and bound-service destruction logic remain together in
`ATLLoadedApp.vinixStopServiceMain`. Main-thread callers execute it directly.
Worker callers snapshot the Intent, enqueue a `FutureTask`, and wait for its
actual boolean result. Interrupted waits finish the accepted operation and
restore the caller's interrupt flag. Exceptions are rethrown as the original
cause, preserving identity.

The earlier Maps teardown failure reached service lifecycle code on a worker
thread. [Maps360](maps360-permission-metadata-replay.md) later used the main-thread
path and did not reproduce that failure. This focused regression exercises the
worker path independently; a further Maps replay remains separate evidence.

## Source and host validation

The fixture starts a service, then stops it from a preinterrupted worker. Every
lifecycle callback asserts the main looper. Later stages check queued start and
bind ordering, retention of a stopped bound service until unbinding, repeat-stop
results, restart and destruction counts, restored interruption, and exception
identity. The APK contains only Main and four service-stop fixture classes.

The host source check tests duplicate application and four malformed/destination
guard cases without output mutation, verifies that the original stop body is
retained as the main-thread helper, and assembles/disassembles six API28 classes.
Its complete 666-file bundle is
`/Users/alex/.local/state/vinix/android/service-stop361-source-2026-10-26`, manifest
`3734d705ca46ae3415d244671d59a73f54bfea15fb048e873ce0d4141395a537`.
Root's complete readback exited 0 with every hash and the exact file set matching.

The framework builder is `99ce265dae08f13860e2b2cb571e9db5197853c8`; the same-APK
ART harness is `b522c51b580ff669e84f3907097d3acec6273cad`. The harness compiled
with an explicit private353 VROOT, retained source and generated C, and equal
270-input source closures before and after compilation. Its synthetic semantic
tests passed, including rejection of incorrect, missing, repeated or reordered
markers and wrong failure classifications. The complete 644-file bootstrap
bundle is
`/Users/alex/.local/state/vinix/android/service-stop361-run-bootstrap-build-attempt2-2026-10-26`,
manifest `8374e023aaa71711acc532969e39ad278b0639c6b160212601b9dc7a19aabc91`;
its recorded complete-bundle readback exited 0.

| Source or host input | SHA-256 |
| --- | --- |
| `androidtools/framework_service_stop.v` | `6e1f8379f7acc770fe93e2b3c80df9b480777883a477e2652246667944028445` |
| `startupfixture/service_stop.v` | `f954df1b61d1646c2239debb22eca9d8420a9429f7d8ac35f8cf42a2bf0ca0de` |
| `service-stop-source-check.v` | `98d9637588a4e8317ffedcc454f6b06cb020fd08b86eeaf4a452e952dbc49636` |
| `service-stop-framework-build.v` | `18bda1dc9c95ab10727828c5149fcefb068c6add04b63c6f5c30364b85a7f1b4` |
| `service-stop-run.v` | `09f8a7b3a0fa4e4388907618d12bd89cd96f95b1466753c7a70b7bce23ec4e36` |
| Bootstrap harness executable | `7b39817552484512abf04b22853ec765f0e32f9d7f58e9415c34694fb52c3ed2` |
| Frozen V compiler | `109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e` |
| Complete-bundle checker290 | `52c03dc3952acf9a51c5288c12784162171c1fa83522cd1cd5ae268d79092004` |

## Complete framework build

The sealed framework bundle is
`/Users/alex/.local/state/vinix/android/service-stop361-framework-build-2026-10-26`.
It retains the complete qualified359 bundle and its complete353 baseline.
Original, cloned and post-build baseline readbacks passed. Frozen builder and
driver source closures matched before and after compilation. Compiler, C linker,
Java and Smali tool identities are retained in the bundle; SDK/JDK libraries
remain environmental inputs.

Complete DEX comparison changes only `android/atl/ATLLoadedApp`, adds only
`android/atl/VinixServiceStop`, and removes no classes: 2,073 become 2,074. Only
`classes.dex` changes among the regular JAR members. Duplicate and malformed
provider guards leave all 2,073 baseline Smali files unchanged. Builder, root
and independent complete readbacks exited 0, verifying all 23,865 file hashes
and the exact file set. The independent receipt is adjacent to the bundle as
`service-stop361-framework-peer-readback-2026-10-26.json`, SHA-256
`ee508ea70fa35d36bc068505139b5474a1b246af89a496d88436600e898f3735`.

| Framework or runtime input | SHA-256 |
| --- | --- |
| Qualified353 complete manifest | `22bc4e713113d41a7ab56a1809293fb9f3ccb11fd8cc8c8c589fc20afd19171f` |
| Qualified359 complete manifest | `7a2ae7763e71f702ccc1a50b3b63cf444a0e37d8b6a800e77c80866d3ba9dccc` |
| Old359 framework JAR | `88fdf06964bfbd3815d824ab5ff5517887e58de3eb3eb47986d99806fbe6c2fc` |
| Framework361 complete manifest | `9649ab0f596dcd44ce5979a2e129548ca550d2ad54b4d2995fd3c714e125f8e9` |
| New361 framework JAR | `077bb9f1784e2945accebc9043e0d8d54617bb0e01725e97824807d8cc57b10a` |
| Native351 SO | `d3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1` |
| Launcher353 | `406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0` |

## Same-APK ART result

Both variants passed their expected-result checks under
`/Users/alex/.local/state/vinix/android/service-stop361-fixture-2026-10-26`.
Preparation and both guest runs passed the unchanged 1,024/768 MiB capacity
gates. Native351, launcher353, base runtime, fixture APK and frozen native
closure are identical between variants; the old359/new361 framework JAR is the
sole runtime difference. Shared input inventories match before and after both
runs.

Old359 printed BEGIN once and failed after two seconds with exactly one
`java.lang.AssertionError: service lifecycle must run on main looper`, through
`ServiceStopProbe.mainThread`, `ServiceStopService.onDestroy`,
`ATLLoadedApp.stopService` and `ServiceStopWorker.run`. It emitted no positive
markers and exited 1. New361 printed WORKER, BOUND, RESTART, EXCEPTION and final
PASS exactly once in order, survived the full 35-second observation, and had no
failure markers. The original raw classifier's `functional_passed` remains
null; the separate semantic checks establish these results.

The checked runner's original, qualification and pre-seal semantic receipts are
equal for each variant. The sealed 25,085-file bundle has manifest
`df542fd682eb4530a895f102b29554ddadc33dd1fa7f48d351b291832e3e4582`.
Root and independent complete-bundle readbacks both exited 0, verifying every
file hash and the exact file set. They wrote adjacent receipts without changing
the sealed bundle:
`service-stop361-fixture-root-readback-2026-10-26.json`, SHA-256
`b7c25f20887f2a912ce056dc6f65a11573d09a62814e32996b23f7c41d7e6e05`, and
`service-stop361-fixture-peer-readback-2026-10-26.json`, SHA-256
`329a6216ce0bfb02dac26eaf2190b24fed169f81b9f0a96092bb3e1cd5f39745`.
The independent adjacent `-command.json` records the checker's actual exit 0;
`-inspection.json` records the separate serial, raw-result and receipt checks.

| ART artifact | SHA-256 |
| --- | --- |
| Same signed APK | `1cafc5490ebe0a5f759449f08198a30162972f7092acacd806925b4b2b761e6d` |
| Checked runner | `340538de40f4b2a5df39b95e121b48ecfd164d34534963a7d4dcf7943e468921` |
| Old serial | `ed8ca142b5ba4b930482e008f48a2ab41115fc3f78bb3e8aee1713c666fbe59a` |
| New serial | `9947839ed2ef8cf72060da9f3f07f3ede5dbefb8f8dea357f3c74de8a987dc7c` |
| Old raw results | `d1cf2667d314006c32f1bf98e23014f508f69de69c2687708db38c87b44de997` |
| New raw results | `cd8b2c856cf81317d10ed5358a0d0d3346d9c353442b20fd3e1d8826081fd796` |
| Old semantic receipt | `6d7eb184ef354a4a3a99bd6c689be1b1814f012cd2551005c73ce8e8ea34a20a` |
| New semantic receipt | `6a8780988631770fa6d4e0cc3e23f53837b26a2b15f66115bcc17ef4253fccdd` |

This verifies worker-driven service stop on ART. It does not establish that the
later Maps Parcelable failure is fixed; that requires the separate Bundle
parcel regression and another Maps replay.
