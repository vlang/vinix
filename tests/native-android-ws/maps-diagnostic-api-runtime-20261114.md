# EGL/notification diagnostic API qualification

Source c7d84b05d adds bounded native EGL/notification diagnostics and the
queued cancellation regression. Fresh guest maps-current-20261114-r78 passed
the full signed ARM API regression under UID/GID 10160 with that exact native
library and fixture. This establishes API compatibility, not complete Maps
rendering or Google authentication.

The reconstructed private child log contains CURRENT-API-PASS and
NOTIFICATION-CANCEL-PASS after both queued cancellations, together with the
existing Java EGL, network-validation, key-authentication and job-network
checks. The runner observed readiness and pass once, closed stdin, and exited
with status 0. The diagnostic UART reconstruction retains its original
zero-removal plan and complete export; it is not a substitute for a historical
strict-import qualification.

Evidence remains under `/Users/alex/.local/state/vinix/android/`:

| Artifact | SHA256 |
| --- | --- |
| notice-cancel-api-uart-20261114-r1/full.log | 0cb8e7af4b764e46eb3bb17da8d53ce97157ec964ca246367446bcf236b4e7dc |
| Snapshot receipt | c3f44568b579fd1460aad8cc12908e8f657a9ed4163f5a6dbae23fcb8960d16c |
| notice-cancel-api-readback-20261114-r1/archive.json | 5b5af11471db94268d7ea45db1ae391fbda8fc5629f666a65abe55546f81bccf |
| notice-cancel-api-child-20261114-r1/child.log | 93f2b676da9fb7f030deb88fea147e488ff07450509ae9609a2bfb3fd957322d |

The guest uses framework-job-network-keygen-20261113-r1, native
current-native-egl-notice-trace-20261113-r1 and signed fixture
current-api-notice-cancel-20261113-r1. Exact library/APK/build receipt checksums
are in [the build report](maps-egl-notification-diagnostics-20261113.md).
The retained builds used the then-available V 0.5.2 6f888d6 without a compiler
revision pin. The shared compiler now reports V 0.5.2 9a38ec5; no rebuild or
runtime result with that newer executable is claimed here.

Fresh VM staging passed the original explicit limits: RSS 629145600 bytes,
wall 300000 ms, reserve 1073741824 bytes, growth 536870912 bytes and output
4194304 bytes. It returned exit 0/0 with complete cleanup in 11446 ms, peak
sampled RSS 37666816 bytes and no observed shared disk growth. The initial
app-data volume passed identity inspection, read-only e2fsck and its initial
hash check before launch: UUID a31ccb7f31ff42da97779ccd501402f6. Guest resources
remain 12 GiB and four CPUs.

The subsequent Maps retry reached onboarding only just before the existing
15-minute broker deadline. Its early launch before broker readiness was
correctly refused for a certificate input that was not yet immutable. After
readiness, the launcher completed deployment integrity checks and started
Maps. The application advanced through black and white windows to onboarding;
the session deadline then stopped its owned application processes. No search,
route or sign-in interaction was qualified in this attempt.

All three sampled surface states still had surfaceIsBad=false and K/L=null.
Two EGL pixel samples showed uniform opaque beige 480x640 frames. Neither the
EGL error logger nor the notification-failure logger emitted a failure before
the deadline. This does not explain or repair r76's later bad surface. The
retained Maps/GMS logs contain no uncaught/FATAL/NoSuchMethodError or numeric
auth-pump/service-exit failure marker from the checked patterns. Delayed input
also dropped characters in attempted terminal log commands; their malformed
paths are retained and are not evidence of absent application logs.

The 600220 ms storage watch completed with minimum guest free space 7330443264
bytes and available memory 6489888 KiB. The broker's complete UART export is
retained, with BEGIN/END SHA256
fcb2850561f4074f6826cd675ce3d12193ddbd58d8e5651507e895c08dc5055e
(1428274 bytes, 2790 chunks); no import pass is claimed for that export.
After it finished, sync returned to an actual terminal prompt. Only the
verified r78 QEMU PID 86516 was terminated; it was verified absent before
offline debugfs extraction. All test VMs from this continuation are stopped.

Complete runtime evidence remains in maps-current-20261114-r78:

| Artifact | SHA256 |
| --- | --- |
| maps.retained.log | a28325a700caa94f3d664acce40b045958700846ccf8c139211d3a2bbcd9c0e6 |
| broker.retained.log | dd69315c8ad18e8010a7d61f8e5b4317b4ea6fb9180eb546fa6629df32d0580c |
| receipt.retained.json | 8bc2d99d2f2642ae5e93a21f250156b909fd089d46758778d84fcd53ea35fbba |
| maps-launch.retained.json | 603e0116317b0deebe26e0d75c609a2ee1c06d7943d7a3b20683065e553e0b59 |
| serial.log | d13cfb8a9a73742e08fbceb30ba8d2baae85de54d5962674415030d667af4c8f |
| final app-data.ext2 | 2b850a0e857db153b0df2fd2b2467387daaa34b7d420b47f8efa9fc4e5e7f3fd |

The newer-V controller attempt latest-controller-build-20261114-r1 passed its
host self-tests but was stopped during the ARM build: observed shared disk
growth 548872192 bytes exceeded the original 536870912-byte allowance after
76104 ms. Peak sampled RSS was 506396672 bytes, exit 125/137, cleanup complete.
Its retained directory was 32 MiB; this does not attribute the shared growth
to a particular host writer. No ARM build/runtime pass is claimed for it.

API success does not establish that Maps' bad-surface or late notification
transport failures are fixed. Tiles, route geometry and authentication remain
pending.
