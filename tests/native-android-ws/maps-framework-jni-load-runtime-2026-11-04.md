# ARM JNI correction and GMS replay

The unchanged signed boot-classpath fixture passed on ARM with the corrected
class-based JNI load. The separate GMS replay reached readiness, then exited
during idle because Cronet could not reflect
`android.net.TrafficStats.setThreadStatsUid(int)`. No manual Maps launch or
credentials occurred. Maps rendering, imagery and authentication remain unverified.

Preparation source was `cd8b57df0add14767e5ba89f5b2d8e87f1885ef0`; the
[prepared image and exact clone](maps-framework-jni-load-preparation-2026-11-04.md)
were recorded in `efd1bb8ce`. The SDK remained `af23c13d…`, native library
`13cf0207…` and frozen kernel `a54505e3…`. The qualified 64 GiB coexistence
runner admitted the fixed 12 GiB/four-CPU guest alongside unchanged CI.
The first launch refused an additional QEMU observed in its fresh snapshot;
the next fresh launch passed. No foreign VM was signalled or modified.

Paths use `S=/Users/alex/.local/state/vinix/android`. Complete evidence remains
in `maps-framework-jni-load-runtime-audit-2026-11-04-r1` (`A`), matching
`maps-framework-jni-load-live-controls-2026-11-04-r1`, the exact clone VM and
`bootclasspath-jni-api-transfer-live-2026-11-04-r1`.

The fixture used profile `bootclasspath-jni`, UID/GID 10155 and the pinned
runner/APK/JAR/native inputs. Its receipt confirms all six hashes, eleven
checks, drained EOF and child exit zero. The complete 15,375-byte child log
hashes to `052951e630ac4dd91179196d3f312afbf01f3c68f04d36760d972e74d5933017`.
It contains one exact BOOTCLASSPATH-PASS, one native READY and pause/stop/destroy
teardown. The zero-removal import retained 46 chunks and both archive entries;
archive SHA-256 `76c0e5c9f0178122a57e7c6f89762e38e50dbcfb4ca80c3756d2d7f1212d3bbe`.
Independent review confirmed the receipt, complete log and UART continuity.

After verified fixture mount release, the broker prepared its audited SQLite
replacement and immutable inputs. Its receipt records `service_ready=true`,
`broker_exit=1`, complete EOF drain and zero cleanup survivors. The exact strict
UART import retained 21 entries and archive SHA-256
`883b8397d58ccb722c388e2e18d2e8f20e440aefed06ab62e2f701a9bf0bdb94`.
The full private broker log was separately exported and decoded: 375,957 bytes,
SHA-256 `b0fbbeab8404cc849601e8a103e597c5fae6472790d66ca210a9ad048f326c2f`.
Guest hash/length, exported manifest, reconstruction and fresh decoder check
agree. Lines 8512–8558 show JavaCronetEngine initialization failing with
`NoSuchMethodException: setThreadStatsUid [int]`; GMS then calls System.exit(10).

The qualified stop sent SIGTERM to owned PID 97667 and wrote its stop receipt.
Immediate reconciliation encountered the disappearing process; a separate
`reconcile-stop` verified absence without another signal. CI PID 6395 remained
running. Final UART: 2,894,004 bytes, SHA-256
`7044012a2242efbe0bf66ccee132b1cf4f306786a4821e44da6583d9f6138325`.
Complete clone sidecars were copied and compared into `A/clone-evidence`.

All four closed roots passed a 376-entry seal and independent fresh readback.
Manifest at `S/maps-framework-jni-load-runtime-sealed-2026-11-04-r1/sealed/manifest.json`,
SHA-256 `b60d11c32319a2a5a16bc3f6593e28e9c837b893a81929cd7f1d1ddd4b8cfe93`.
Seal/readback took 8,323/3,070 ms, guard/child zero with complete cleanup under
the original 600 MiB RSS, 900-second, 64 MiB growth, reserve and output/file caps.
Original complete bundles and historical auditors remain required. The next
SDK change adds independent per-thread UID state and public set/get/clear
methods; unsupported kernel traffic counters and tag behavior stay unchanged.
