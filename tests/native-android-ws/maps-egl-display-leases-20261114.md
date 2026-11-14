# Shared EGL display ownership

r80's ordered trace showed the renderer successfully binding its context and
window, then other threads terminating the same display before the renderer's
swap found null current context/surface. Android
[reference-counts successful display initializations](https://android.googlesource.com/platform/frameworks/native/+/be3c3e4/opengl/libs/EGL/egl_display.cpp),
so one client's balanced initialize/terminate pair must not destroy another
client's active display.

The adapter now retains display initialization leases under its existing mutex.
The first successful provider initialization stores its actual version; repeat
initializations return that version and increment the lease count. Intermediate
terminations release only their lease. The final successful provider termination
clears the reusable record and runs the existing deferred window cleanup.
Failed initialization adds no lease; failed termination keeps the last lease.
Unknown/already-terminated displays retain provider validation and return values.
Thread release does not consume initialization leases. The swap binding guard
remains intact.

Storage is a static 16-record table, with a checked u32 count and EGL_BAD_ALLOC
on table/count exhaustion. The generated C was checked for static storage,
stack-local version outputs, bounded lookup and mutex unlocks on every return.
There is no new heap allocation or window-free path. Existing bindings continue
to retain window resources through their normal deferred destruction.

The fixture producer accepts --shared-display to add the regression to the full
signed API probe. While the main thread owns a current pbuffer/context, a worker
initializes and terminates that display once. The main thread must still query
the surface, retain a context, swap and pass the existing shader/pixel checks.
After final release, a vendor query must report EGL_NOT_INITIALIZED and repeated
termination must succeed. Worker completion is joined with a 10-second bound.
Existing default, certificate-network and TLS-lifetime fixture modes remain.

The exact same signed APK failed before the fix and passed after it:

* r81 / unchanged native e5336e7a…: runner failure, private child AssertionError
  "shared EGL display lost active surface" at EglSharedDisplayProbe.check.
  No full API pass or failure-export import is claimed. The raw data image and
  complete child/serial logs retain the failure. The VM was synced, owned PID
  21157 stopped and verified absent before offline child extraction.
* r82 / repaired native 37542395…: complete signed ARM API pass as UID/GID 10160,
  with EGL-SHARED-DISPLAY-PASS, EGL-SHARED-TERMINATE-PASS, the original Java EGL
  and scheduled-job checks, and CURRENT-API-PASS. Readiness/pass were observed,
  stdin closed and the runner exited 0. Diagnostic reconstruction used its
  retained zero-removal plan, without replacing any historical strict auditor.

Source changes in this commit follow c6b96523b. Builds used available V 0.5.2
9a38ec5, executable SHA256
f52821ef2d15507ef5238e36a5237c909dfbdbc09786671c5d87a3feb1ed843c.
All generated artifacts remain under `/Users/alex/.local/state/vinix/android/`:

| Artifact | SHA256 |
| --- | --- |
| current-api-shared-display-20261114-r2/probe.apk (both runs) | 723769dc8f2f694c1f0d7da4ab8ffd7c2388ec2af3c013c3db0fc08f25434668 |
| current-native-egl-display-leases-20261114-r1/native/libvinix-android-native.so | 375423954af78a45194a3072a25bcafdf2eae93f4eb494fcf9f1af8e45e68ad0 |
| maps-current-20261114-r81/child.retained.log | 4561095ed47571c953609086f738e94548cffc8c1e7ab3df37b5025234ce7511 |
| r81 final serial.log | 6b34b657c0b7bbcacabef9726ed90ad88af52ffed774a21cd60b6b33d464882f |
| r81 final app-data.ext2 | e2e4831648044663b6c2ea12b185ba66c2e8f5b5898a0685050f1be81f7b3e6f |
| shared-display-baseline-uart-20261114-r1/full.log | e67643e728fc48495a4ecf7f13c4d541ff0d0f01268dcc40604168825c09be38 |
| Baseline snapshot receipt | 83b84a219bd322575265c95b479cc4e160a4473a70f8b51ba51ebe290075f166 |
| shared-display-fixed-api-uart-20261114-r1/full.log | 61bf9b0a6a3b515863bea029959225e365a84866a13bad4869c0f604d9490960 |
| Fixed snapshot receipt | dced8112b4a95bc464014b441342349d7c9f09b5dfd9aaf258c32ad4ac8b2175 |
| shared-display-fixed-api-readback-20261114-r1/archive.json | d8ec93e53118615a0be852772412414f4189d5a8b9533ed45711b8ecaa402a1b |
| shared-display-fixed-api-child-20261114-r1/child.log | 99e18ebf8eab7f2cfdde3920b839cdd31e45ed92773cf7911619a0afd9bb8cf8 |

The native build passed original explicit caps (RSS 629145600 bytes, wall
300000 ms, reserve 1073741824 bytes, growth 536870912 bytes, output 4194304 bytes):
21228 ms, peak sampled RSS 480542720 bytes, shared growth 174444544 bytes,
exit 0/0 and complete cleanup. Its .guard.json/.log and selected sources,
generated C and headers remain beside the native build. The signed fixture
producer inputs and emitted C remain in maps-shared-display-inputs-20261114-r2
and maps-shared-display-tools-20261114-r2; the earlier r1 fixture lacking the
final-release assertion remains retained but was not used for these two runs.

Fresh r81/r82 disks passed UUID inspection, read-only e2fsck and initial hashes.
r82 UUID d1f31d5970324b7194a8a9871bf5f7a4 staging passed the same caps: 9325 ms,
RSS 38846464 bytes, growth 220319744 bytes, exit 0/0, cleanup complete. Both
guests retain 12 GiB/four CPUs. r82 uses the unchanged job-importance SDK,
latest qualified controller and paired protocol/core/TLS artifacts from r80.

Actual Maps rendering with the repaired lifetime is pending. The isolated and
full API passes do not establish map tiles, route geometry or Google sign-in.
