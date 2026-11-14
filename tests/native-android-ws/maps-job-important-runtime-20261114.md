# Job importance metadata and rejected EGL binding diagnostics

r79 exited on a GMS worker's missing setImportantWhileForeground(boolean).
The SDK now stores that requested flag, defaults it to false, returns the same
builder from the setter and exposes isImportantWhileForeground(). Reusing a
builder produces separate JobInfo snapshots of all admitted scalar/reference
fields, so subsequent setters cannot rewrite earlier built jobs. Nested extras
are still reference-valued; this is not a deep-copy change to bundle contents.

The builder rejects foreground-important jobs after minimum-latency or periodic
configuration, including an explicit zero delay, at build time. Clearing the
importance flag allows the existing metadata to be built. A deadline alone
does not trigger this early-constraint rejection. This follows the relevant
[Android JobInfo builder behavior](https://android.googlesource.com/platform/frameworks/base/+/f08f9d4bd782cd3b1693176e07624a398c527e23/core/java/android/app/job/JobInfo.java).
The latency-only scheduler gains no foreground privilege, doze bypass or new
constraint engine. Other existing scheduler limitations remain.

The native adapter additionally records up to 64 lifecycle argument/result
records and 16 rejected-swap binding records per process, only with protected
tree diagnostics selected. The latter include requested/current display and
draw surface, current context and thread identity. Lifecycle logging consumes
no EGL error; current-state queries at rejection do not clear the error state.
The swap guard, provider calls, resource lifetimes and return values remain
unchanged. These logs investigate r79's observed adapter EGL_BAD_SURFACE;
they are not a rendering repair.

The complete signed ARM API regression passed in fresh r80 as UID/GID 10160.
The private child log contains JOB-IMPORTANT-PASS for default, fluent toggling,
independent built metadata, identity/service preservation, both orderings of
importance/latency, rejected zero/positive delays and periodic configuration,
deadline allowance and builder isolation. Existing scheduled callbacks and
Java EGL/error/thread checks also passed. The runner observed readiness/pass,
closed stdin and exited with status 0. Its complete export was reconstructed
with the retained zero-removal plan; no historical strict-import pass is
substituted for that diagnostic derivation.

Sources in this commit follow d64a5db08. Builds used available V 0.5.2 9a38ec5,
executable SHA256 f52821ef2d15507ef5238e36a5237c909dfbdbc09786671c5d87a3feb1ed843c,
with no compiler revision pin. Complete artifacts remain under
`/Users/alex/.local/state/vinix/android/`:

| Artifact | SHA256 |
| --- | --- |
| framework-job-important-20261114-r1/api-impl.jar | 9635a51178ae4941314ae8062e5033fc9f4c1207dacea84a63206d916e8e3c71 |
| current-api-job-important-20261114-r1/probe.apk | 71839a2048d43b5811a543e50b11ac5b8e3f3781a894bd28e0afb5ed768a7b34 |
| current-native-egl-binding-trace-20261114-r1/native/libvinix-android-native.so | e5336e7ae1efd29b3ac77c16ea2bcc13f78f5de4a549482ae68178847ac7bdcf |
| job-important-api-uart-20261114-r1/full.log | bb61cdf5e631d45d68b651563d0859ff0c1034b8482da83bfb76c6a3b75dd907 |
| Snapshot receipt | e4694400880c5bef25a8c2801d51cbe23e4bdddddf5611d97188ab973b2f0528 |
| job-important-api-readback-20261114-r1/archive.json | 5296677eb6799227f0c044542d609485278df4a0bf0bb3d2a793919bf9af3bec |
| job-important-api-child-20261114-r1/child.log | 13850962e2edfb78bdb12756e52c493a2b8f6cab32bfde81cc64ff3877a89f06 |

All successful phases below explicitly retained RSS 629145600 bytes, wall
300000 ms, reserve 1073741824 bytes, growth 536870912 bytes and output 4194304
bytes, and returned exit 0/0 with complete cleanup. Each prefix retains its
external .log/.guard.json:

| Phase / prefix | Elapsed ms | Peak sampled RSS bytes | Shared growth bytes |
| --- | ---: | ---: | ---: |
| maps-job-important-builder-emit-20261114-r1 | 4274 | 453787648 | 42270720 |
| maps-job-important-builder-cc-20261114-r1 | 1010 | 137920512 | 112201728 |
| framework-job-important-20261114-r1 | 5438 | 464502784 | 37269504 |
| maps-job-important-fixture-emit-20261114-r1 | 2976 | 262127616 | 19083264 |
| maps-job-important-fixture-cc-20261114-r2 | 695 | 96092160 | 4423680 |
| current-api-job-important-20261114-r1 | 1597 | 178520064 | 10199040 |
| current-native-egl-binding-trace-20261114-r1 | 21484 | 493191168 | 118128640 |
| maps-current-20261114-r80.stage | 14959 | 37715968 | 322273280 |

SDK producer/fixture source inputs and emitted C remain in
maps-job-important-inputs-20261114-r1 and maps-job-important-tools-20261114-r1.
The native root retains the actual selected source copies/generated C and
headers. The first fixture C link failed because a forced native header
conflicted with the emitter's standalone declarations; its failed log remains.
The successful link uses V's native signal-stack runtime as a separate source
unit, without forcing that header into the standalone fixture translation unit.

r80's initial data volume (UUID d9a575f42b0148edacb30ab5c8813db2) passed identity,
read-only e2fsck and initial hash checks before launch, with 12 GiB/four CPUs.
The subsequent Maps retry reached Explore, returned fresh Louvre details and
photos (4.7 stars/382644 reviews), an Eiffel Tower-to-Louvre drive estimate of
eight minutes, and a route preview with the instruction to head toward Pont
d'Iéna. The map and route geometry remained blank. No sign-in attempt was made.
Unlike r79, the retained Maps/GMS logs have no NoSuchMethodError, uncaught-handler,
bounded notification transport failure or numeric auth-pump/service-exit marker
in the checked patterns. The broker reached its unchanged session deadline;
this does not qualify Google authentication or the local-expiry crossing fix.

The new selected EGL trace records the renderer initializing the shared display
and successfully binding its window/context. Another thread then initializes
that same display, creates/unbinds temporary contexts and successfully terminates
it. A further thread repeats that sequence. The renderer's rejected swap later
reports the same current display but null current draw surface and context.
The complete ordered records are in maps.retained.log (renderer initialization/
bind near lines 8932/8933, first other-thread termination near 10558, second near
15704, and the rejected binding later). This supports the shared-display
lifetime investigation; a separate isolated regression is still required
before attributing a rendering repair to reference counting.

The 600183 ms watch completed with at least 7243669504 bytes of guest free space
and 4708880 KiB of available memory. The complete broker UART export BEGIN/END
digest is 1ea0d00d65cf44ef627072b20df69d9cb3b22a281153c1a338c58bd968c41a65
(1428271 bytes/2790 chunks). After export finished, sync returned to an actual
prompt; owned QEMU PID 86198 was stopped and verified absent before offline
extraction. Complete r80 evidence remains in maps-current-20261114-r80:

| Artifact | SHA256 |
| --- | --- |
| maps.retained.log | fe541ed6c2e052f4029cd0627ea829b392a4e9b8d3a66632f3f429324244ed71 |
| broker.retained.log | 7e3f5408da632f9fc12485b4c6593125d912d2a8dd65dc4909bd62b52a1547f5 |
| receipt.retained.json | e39838becaa625476b6070cfc9dddd699c25c6ff2fffaa4ebb9bccaef4c426a9 |
| maps-launch.retained.json | 6c59ae072ec69b8b4a0722887c65595f58dbd6a4eed6bc100a62b31c09ecf7cb |
| serial.log | 3fc2701edaa6eebffa3f40f3f0666d02e34d8ed97af11f25cde11dd041fdbb3e |
| final app-data.ext2 | 96dc6295b60f46ae4055ae7c4ff76fd20a1d7c4567d742d3a899db01041a5b30 |

Tiles, route geometry and Google sign-in remain pending.
