# Protected surface-field selection

r75 now returns place details/photos and a route/turn preview without its
previous main-looper failure, but the map remains blank. The native read-only
surface-field diagnostic already exists. The desktop launcher closes its
environment, so an ambient terminal setting cannot select that diagnostic for
Maps without bypassing the compositor's verified launch path.

The controller now accepts --trace-surface-fields=PATHS with --broker, records
the selection in its protected session and receipts, and revalidates it before
passing it through the ordinary Maps desktop launch. For example:

```text
maps-account-guest --broker --trace-surface-fields=b.a.K,b.a.L
```

The default clears the diagnostic environment variable, including ambient
settings and legacy sessions. Explicit fields enable sampled tree inspection,
without enabling thread or TLS traces. The native reader remains unchanged:
at most three surface samples, no field writes or lifecycle hooks, and bounded
output to the private Maps log. Values remain excluded from the public archive;
receipts retain only the selected paths.

The selector accepts at most 16 paths, 255 bytes/path, 16 components/path,
4095 bytes total, ASCII Java field identifiers of at most 128 bytes, and
canonical list/array indices from 0 through 65535. Empty components, oversized
paths, malformed indices, punctuation and duplicate CLI options are rejected.
Invalid persisted selections clear the field variable and cannot enable tree
inspection by themselves. Existing launch identity, surface ownership, account
authority, session deadlines, sample limits and resource guards are unchanged.

Evidence under `/Users/alex/.local/state/vinix/android/`, available V 0.5.2
6f888d6. surface-fields-controller-build-20261113-r2 passed its host self-tests
and static AArch64 ELF64 build: 20706 ms, peak sampled RSS 514490368 bytes,
shared growth 42262528 bytes, exit 0/0 and complete cleanup. The explicitly
retained caps are RSS 629145600, wall 300000 ms, reserve 1073741824,
growth 536870912 and output 4194304. Controller SHA256:
3d0750b8a7093d1eac8f7bfaf77c64f0bc3ee8a753eebf824fa45bc47a8600da.
r1 stopped on observed shared disk growth of 666435584 bytes after 3579 ms;
its directory retained 28 MiB. It is not a pass or an attributed host-write trace.

Tests cover boundary-sized valid selections, malformed names/indices, duplicate
options, independent diagnostic combinations, legacy/default behavior, ambient
clearing, JSON session/launch round trips, invalid persisted input and private
log exclusion. The existing polling scratch-memory test also remains intact.

Fresh r76's controller self-tests passed on ARM after app-data volume mount,
including the same 256-iteration, 64-process scratch-memory checks. Snapshot
surface-fields-selftest-uart-20261113-r1 full SHA256:
382aa031dbb43c486f9831ed7630710ecf7295295f01a5c55f199a761b8362ab;
receipt 83a1423ade228028d415741e113c8df463d958a7092341ea1e7af24bf348d6ac.
The guest reuses r75's unchanged, signed-API-qualified SDK/native/protocol/core/TLS
combination, with the new controller. Staging passed its original guard;
volume identity ba7e292f24d44f72826016c4bb8710cc, inspection, read-only e2fsck
and initial hash passed before launch.

r76 captured all three bounded samples (48 field records). K/L were null in
the first sample, then non-null in the second and third; the later viewport
and camera dimensions were 480x640. Those later samples exclude a persistent
null-camera/viewport early return, but do not establish successful rendering.
The surface's surfaceIsBad flag changed from false in the first two samples
to true in the third. Exactly one EGL pixel sample was logged: a uniform
opaque beige 480x640 frame. Subsequent compositor samples still showed that
frame. The retained trace does not identify the failing EGL call or error.

Explore remained blank. Sign-in reached Google's server communication error
page. Maps subsequently lost its main looper to IllegalStateException from
NotificationManager.nativeCancel. Several earlier absent-broker cancellations
had returned without failure; no notification-service response error was
logged. This is not evidence that all cancellation failures may be ignored.
The next diagnostic build is described in
[the EGL/notification investigation](maps-egl-notification-diagnostics-20261113.md).

The 600142 ms storage watch completed with at least 7238406144 bytes of guest
disk space and 3894672 KiB of available memory. The test VM was synced, stopped
and its owned PID 5250 verified absent before offline log extraction.
The protected receipt reports bounded-session-ended-no-authentication-claim.
It does not qualify local-expiry crossing or successful account authentication.

Complete evidence remains in maps-current-20261113-r76 under the state root
above. Source: controller a4e654561 with r75's unchanged qualified SDK/native.
SHA256 values:

| Artifact | SHA256 |
| --- | --- |
| maps.retained.log | 5d24d873fb45c1dea69110751812264efc96cd9fb8a7fbdcfd4301b041c692cc |
| broker.retained.log | 65add41280b1e2447f2ab174dddfc23554124278bcb1556829fea251431e6776 |
| receipt.retained.json | bccd78acbaa6792b9fbfd7178a33f4a7ebcd78e0a37063d9e293a840f04ce958 |
| maps-launch.retained.json | e078749f342f78d46df5a2c4a82ba8ee880b20c5e5c803558e9d1ab1c1fbfefb |
| serial.log | 865eb9919387d17881f2279d17180b816d9025beae8fea27f6f52b85b2eada7a |
| final app-data.ext2 | 01aea0160fcd4b5ad87bb81bfdaf44d3d1c350c1fecb34960c45d565e8a2b769 |

This tool does not fix or qualify map rendering or authentication.
