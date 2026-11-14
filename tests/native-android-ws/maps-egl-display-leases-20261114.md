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

Actual Maps r82, with source fix 760972921, now renders map geometry. Explore
showed North America, water, coastlines and labels; searching Louvre returned a
detailed map with museum buildings, streets and labels, alongside real place
details, reviews and photos. Screenshots explore-wait.png (08:42:56 UTC) and
resume-current.png (08:49:21 UTC) retain these observations. No rejected EGL
binding, EGL error, missing-method exception, notification failure or numeric
auth-pump failure marker was found in the retained Maps/broker logs. The bounded
session ended at 08:49:49 before the Directions interaction completed. Route
geometry and Google sign-in remain unqualified; this run made no sign-in attempt.

The complete UART export has matching BEGIN/END SHA256
6b7fd7626a436f84883ecb1e46e39f53b194fa183c224fe9431a24f5e7879775,
1428267 bytes and 2790 chunks. The 600150-ms storage watch retained at least
7245754368 guest disk bytes and 4630128 KiB available memory. After export,
sync returned to the actual guest prompt; owned QEMU PID 46599 was stopped and
verified absent before offline extraction. The receipt records the normal
bounded-session end, no authentication claim and two cleanup survivors, all
terminated with the owned VM. Complete evidence remains in
maps-current-20261114-r82, including retained.sha256:

| r82 runtime artifact | SHA256 |
| --- | --- |
| maps.retained.log | 818e1f11cdf9b32376c44dd49e11250a2b426f0d79805afa276c99a630f190a2 |
| broker.retained.log | 8060d3132ecd74fba1c013c7ff181be6d646bcdf1ed8d6afab7f73fc12eadb2c |
| receipt.retained.json | 13acb9afc5aa0a70c0623a8a9b551ad8ce6baf2dc88a38b1eb8b75c583d7d246 |
| maps-launch.retained.json | 75f9c1f9c6d8bbe5a2f9676e31f8f97937c6296a3a62ac49a16598e0680cc4e6 |
| final serial.log | f2b46cd971902488a7a77840ab83b6651ab082c357e33bf88b375ed8166070bb |
| final app-data.ext2 | 480356691d2bbfe6fe02a2441829b3f46810a10f4676bd33438a22e0cd97e55b |
| explore-wait.png | 2d48c1d44e8f8cf541b558d8cd3d90a20dc859cddd53b5d16210940a170e20dd |
| resume-current.png | 9937151cdd46c462183c14770a8a15923849410fdb7c5772c872e3aa953bdca5 |

Fresh r83 reused those exact ARM-qualified artifacts, without rerunning the
unchanged full API fixture. Staging passed the same explicit caps: 17718 ms,
RSS 38354944 bytes, shared growth 264773632 bytes, exit 0/0 and complete cleanup
(maps-r83-stage.json/.log outside the generated root). UUID inspection
34ba186b61704e859fa0e121542d567b, read-only e2fsck and initial image hash passed.
The available compiler still reported V 0.5.2 9a38ec5; no compiler pin was added.

This retry omitted the optional tree/surface diagnostics. It again rendered
North America, then focused search. UI input was very slow: an approximately
70-character root-terminal command delivered at 150 ms per character took more
than two minutes to appear completely in the guest. Separate host observations
at 09:03 and 09:07 showed one-minute load averages 97.74 and 133.75; this is
concurrent contention evidence, not proof of the latency's cause. The Louvre
query did not produce an observed result before the fixed deadline. The receipt
records bounded-session-ended-no-authentication-claim at 09:10:55, rather than a
new runtime failure. No missing-method, fatal native signal, ANDROID-WS-FAIL,
numeric auth-pump failure or service-exit marker was found in either private log.
Finalizer lock warnings remain; their connection to input latency is unproven.
No sign-in was attempted. Route geometry, authentication and responsive use
remain unqualified. JIT remains disabled; no new JIT improvement is claimed.

The 600543-ms storage watch retained at least 7257001984 guest disk bytes and
4805552 KiB available memory. Complete UART export BEGIN/END agree on
886c2a7b9bbb50477e42649117eae0bb48fd3f1f77da162e1df69c4444fa013d,
1427772 bytes and 2789 chunks. Sync returned to the actual prompt before owned
PID 30327 was stopped and verified absent. All r82/r83 test VMs are now stopped.
The complete r83 bundle remains in maps-current-20261114-r83, with checksums
in retained.sha256 and app-data.final.sha256:

| r83 artifact | SHA256 |
| --- | --- |
| maps.retained.log | 84a30c1c6222ba041553d5139f7887eea4b43a67e8f4fd2c09d71c32237ad82e |
| broker.retained.log | 7a434028425bde3e03f8f3715530f4d960ce5ef1bc1da6100457a85d4086517e |
| receipt.retained.json | b8c04d1587a26cdc0b4c50bd8a2fbdf965dc904bfef0987de9d1aac4939cbbfb |
| maps-launch.retained.json | 49a87f4e7d1d0d4fc561161c3e703ece1883bebcdac454d135e28f09ab293c48 |
| serial.log | 43bec4e7977744f1759c8fcf716f401613a5273fcb2087ec99646b7856031ff2 |
| final app-data.ext2 | bccbf5b5fde72ad464849b1351fce5454860ba4234ba84ec6a7668fee0c37d6e |
| skip-last-check.png (rendered map) | 03d65abbbda569ebdf96316c5480f05ef45742835b44a639305b1a62ad2aca1c |
| search-late.png (focused search) | 282bb5d802af73f24a58bf26f6d377443097e9d6417e34fa80c07d664f082440 |
