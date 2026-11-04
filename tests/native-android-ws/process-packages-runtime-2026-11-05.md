# Process package-list ARM pass and GMS Global string-write failure

The signed process-package regression **passed on ARM** against the prepared
SDK/native pair. The receipt and complete child log passed independent review.
The separate GMS retry reached readiness, then exited on the missing
`Settings.Global.putString(ContentResolver,String,String)Z` API. No manual Maps
launch followed. This report establishes no GMS stability, Maps rendering,
imagery or authentication result.

The [prepared image and exact clone](process-packages-preparation-2026-11-05.md)
are committed in `bde6cee61`. Preparation source is
`5b80e7f7b1c82f1f215fb1b6fe11923e0d9b356f`; the closed prepared root is
`S/maps-process-packages-r1`, manifest
`9e032c999e8d57b7ce205841c53146ed653996be037deaf0e82cfd4b1262b535`.
The inherited frozen kernel remains unchanged. Paths use
`S=/Users/alex/.local/state/vinix/android`.

Runtime evidence is at `S/maps-process-packages-runtime-audit-2026-11-05-r1`
(`A`), fixture controls at
`S/maps-process-packages-live-controls-2026-11-05-r1` (`C`), runtime clone at
`S/maps-process-packages-vm-2026-11-05-r1` (`VM`) and transfer output at
`S/process-packages-api-transfer-live-2026-11-05-r1`. Keep complete UART,
screenshots, clone sidecars, controls and raw results outside Git. The prepared
image, original host/tool bundles and historical auditors remain required.

Qualified coexistence admission started owned VM6224 at 21:27:08 UTC on
November 4, with 12 GiB/four CPUs. Launch snapshots at 21:27:06/21:27:08 UTC
identify separate CI23708 at 16 GiB/four CPUs, 128 GiB host RAM, 18 logical CPUs
and normal pressure, under the explicitly authorized 64 GiB/half-host policy.
This is snapshot admission, not continuous monitoring. `C/admit.guard.json`
passed 0/0 with complete cleanup in 221 ms, sampled RSS 5,455,872 bytes and
observed growth 32,419,840 bytes. CI was neither signalled nor accessed through
its guest interfaces.

The isolated UID/GID10157 fixture child14545 exited zero. Receipt
`A/fixture-diagnostic/exported-receipt.json` selects `process-packages`, retains
the 180/20-second deadlines and 4 MiB log limit, and contains all eleven unchanged
checks. Its SHA-256 is
`72a3b5f0b718efdc9c7fcaec729f22eaa9a4cf741f7498f189ec23d071ddf389`.
All six input identities match the qualified delivery and prepared runtime:

| Input | SHA-256 |
| --- | --- |
| `/opt/input/process-packages-run` | `725710de6957816c0ece03008c54bf3ca78bc31635d9495c18a04a922f12d21f` |
| `/opt/input/process-packages.apk` | `db555d086522f003e912e3de5fcf0905d3079025c92397c7b92c6ba714d497e7` |
| Runtime `usr/bin/run-android` | `1b4d3e3d2dbc2eb5ae95343847218d4afd44d64aeb9d52cc0b07cb8f9c37b112` |
| Runtime `usr/bin/vinix-android-native` | `b1061601ebbcd5bc4c81c68d354704e58ff472a2bc9c8666fad6a588a614b98d` |
| Runtime `usr/lib/art/libvinix-android-native.so` | `b69c62304448c1aa0fd5f0cc660acf81cfdd8614b280dad691f53a07d8abcc5f` |
| Runtime `usr/lib/java/dex/android_translation_layer/api-impl.jar` | `875f854ddf662dcaf55ebe05df06f5833eb5ca1e15f94066ffdf0fef18e829a8` |

Runtime paths above are under `/opt/process-packages-runtime`. The complete
`A/fixture-child/child.log` is 10,984 bytes/114 lines, SHA-256
`f029dd3367406c8c4725857890d229eaff6023224a7513a3bad54ff31c61dda1`.
It has the sole exact PASS at99, sole native READY at108 and normal
pause/stop/destroy through114. There is no fixture FAIL or uncaught marker.
The exact PASS is:

```text
PROCESS-PACKAGES-PASS public-instance-field default-null actual-self package-not-process fresh-arrays caller-memory-state bounded-worker
```

This measures the public mutable instance `String[] pkgList` field and null
default, direct nullable/empty/caller-array writes, real self PID/UID and parsed
package/process metadata, fresh records and arrays, mutation isolation,
`getMyMemoryState` preserving caller-owned package arrays, and bounded queries
on a plain worker without a Looper. The fixture's declared process is
`org.vinix.bootstrap:process_packages`, distinct from its package. This covers
Vinix's supported primary-process metadata, not global process enumeration or
companion-process liveness.

Guest input stayed idle through export END. Immutable fixture snapshots are
`A/fixture-before` and `A/fixture-after`; their receipt hashes are
`bfe65a7868f24f0cff81f9ff24282d519785a168999eba674b9a1f4c2ccd4db4`
and `9a347d20f10f8e3024c92a87bd1bafd81f4b23afa635c424b4e7d2bcb3f20b6d`.
The exact interval starts at byte97,067 and spans 27,953 bytes, SHA-256
`aece21dd1ebb999626d48c4549ae40616dfe59f9fc40cb86f97fa3856502ea95`.
The unchanged no-removal plan retains `removals: []`; diagnostic reconstruction
preserved two entries, 35 chunks and 17,591 bytes, archive SHA-256
`9ab77e88f168cade8713ba2842a4cd0675c3ae2a3f3d7e2a640bfb3a697dac8c`.
This diagnostic import does not extend strict fixture-protocol qualification;
no protocol, health or input-identity check was waived.

Clone/admission controls are `C/clone.guard.json` and `C/admit.guard.json`.
Completed fixture controls are `C/transfer.guard.json`, `C/fixture-before.guard.json`,
`C/fixture-after.guard.json`, `C/fixture-plan.guard.json`,
`C/fixture-reconstruct.guard.json` and `C/fixture-child.guard.json`, with matching
logs. Each guard/child exited zero, reason empty and cleanup complete. Transfer
retained 600 MiB RSS, 300 seconds, 512 MiB shared growth, 1 GiB reserve and
4 MiB output; snapshot/plan/reconstruction/extraction retained the same limits
with 64 MiB growth.

After the fixture pass and independent review, the dedicated runtime mount was
released; both it and the original runtime source mount were absent before the
separate GMS controller invocation. The controller ran from 21:35:00 to
21:36:23 UTC with both trace flags enabled. Receipt
`A/broker-strict/results/receipt.json`, SHA-256
`e600baaebfb9c552843aee6f69b83a3af85775a62bd994002ef448803f59e784`,
records broker18377, readiness true, failed/exit1, drained EOF/status1 with
422,757 bytes and zero cleanup survivors. Readiness establishes transport
attachment, not startup or authentication success. The broker exited during
the idle check, preventing the subsequent desktop Maps launch.

The unchanged strict collector accepted 21 entries, 2,831 chunks and 1,449,132
bytes, archive SHA-256
`f94a3c9b28e2557b8f180b40189ae2562f80df5180f419b7f76b809d6109ef56`.
Guest input stayed idle through its complete export END. The entire private
broker log was then transferred using separately captured guest byte count,
SHA-256 and canonical base64. The qualified decoder and its separate retained
decoder check passed against the exact guest pins without repair. The preserved
`A/broker-log-diagnostic/child.log` is 422,757 bytes, SHA-256
`77ca4563fc29330e842c9887d413ffc97db7bc90a3d6fba73d18453e6a7f2595`.
The input UART interval spans 578,621 bytes, SHA-256
`79f9494c844d312e7cfe058e1db142c8e814fd3d96509c5407bd5046c9b27756`.

At9862, `ANDROID-WS-UNCAUGHT` identifies the persistent intent-operation
executor. At9869 the fatal NoSuchMethodError names static
`Settings.Global.putString(ContentResolver,String,String)Z`, through `eqea.m`
source33, `eqea.o` source320 and PhenotypeConfigurationUpdateListener.
System.exit records status10 at9938. The complete frozen caller trace is
`S/gms-global-settings-write-audit-2026-11-05-r1/audit.md`, SHA-256
`845d819b96edcac2a70270226ceec71526e6033e7b0f665cbbf3e41321c6933b`.
It confirms that this caller discards the API boolean while forwarding dynamic
flag keys and string/null values. Actual runtime key/value arguments were not
captured. This identifies the next API correction without claiming a write or
changing any existing readback/persistence behavior.

The final original UART is 2,949,895 bytes, SHA-256
`8ce7bfcb52d919282dad97acb26adda12a687025d8ab679f181941eb8afc42bc`.
One owned-VM SIGTERM was requested at21:40:26 UTC. The initial stop invocation
reported an ownership/disappearance race after recording the stop; its failed
output is preserved. The qualified `reconcile-stop` path confirmed PID6224
absent at21:40:57 without another signal. QEMU records signal15; stop/gone
receipts bind the original ownership. CI23708 remained running and untouched.
No compiler or Java process was started until the owned VM was confirmed gone.

The six-root, 404-entry runtime aggregate is at
`S/process-packages-runtime-sealed-2026-11-05-r2/sealed/manifest.json`, SHA-256
`bc9774e2b836ebae732d75b163b1dd0b475346defd3a244d375cde5f7f600939`.
It retains VM, C, A, transfer output, the failed first seal and the subsequent
scoped cleanup records for the one previously approved compiler-cache directory
that had been rebuilt. Sealing and its internal complete check passed 0/0 with
complete cleanup in 4,123 ms, sampled RSS21,774,336 bytes and growth4,997,120
bytes. Original 600 MiB RSS, 900-second, 64 MiB growth and 1 GiB reserve limits
were retained.

The first aggregate attempt remains intact: observed growth67,891,200 bytes
exceeded64 MiB after1,775 ms, guard125/child137 with complete cleanup. The two
separate fresh readback attempts on the successful aggregate were then refused
before launch for `disk growth budget`, with initial free bytes1,105,698,816
and1,074,941,952. Both record guard125/child-1, PID0, zero samples/groups and
`cleanup_complete=false`. The third separate fresh readback, recorded in
`readback-r3.guard.json` with its matching log, passed 0/0 with complete cleanup
in 2,641 ms, sampled RSS12,124,160 bytes and observed growth6,725,632 bytes.
It checked the same manifest pin under the original limits. The successful
seal-time check, both refused readbacks and complete original bundles are retained.
