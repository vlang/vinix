# Imageless ART runtime qualification

The incremental ART build and library staging are recorded in
[the native build report](maps-art-native-build-20261114.md). The candidate
libart.so SHA256 is d33dfac4adadddf8642927dd798a94e15e713bd3a63e65bac01b22a830ad7ba7.
Its source change skips futile module AOT launches without a loaded boot
image, retaining cached-OAT selection and DEX verification/JIT fallback.

Fresh r86 loaded this candidate with the existing JIT adapter, job-importance
SDK, signed shared-display fixture, protocol and mandatory core/TLS jars.
The guest's selected libart.so SHA256 was read back through the console and
matches the artifact. The standalone signed ARM API regression passed as
UID/GID 10160: exactly one readiness/pass marker, stdin closed after both,
complete EOF drain and clean exit. EGL shared-display/termination, real HTTPS
204 validation, job metadata and CURRENT-API-PASS remain in the child log.

External evidence under /Users/alex/.local/state/vinix/android:

| Artifact | SHA256 |
| --- | --- |
| maps-art-api-uart-20261114-r1/full.log | 16a3675b6c898fd1ff06a34c1e9575868a7fd08545e4820c4081dd52abdaf512 |
| maps-art-api-readback-20261114-r1/archive.json | b0b406870eb938357180e138f8cf794971476974752197edce5afdfede792d0d |
| API exported receipt | 1a6c46903b0a267e40c0fdaf6eddef3e45449d7767e0163a77f013833c324353 |
| maps-art-api-child-20261114-r1/child.log | 016719a3c42e2c7d6f75d043f845eb0569877805cab8331c5554f1124eb832a0 |

These diagnostic derivations preserve the full UART and use a zero-removal
plan. They do not replace or weaken any historical strict auditor.

Actual Maps r86 reached onboarding and Add account, then exited. No Google
credential form or authenticated account was reached. The checked stop
completed with status user-stopped-no-authentication-claim, no controller
error and one cleanup survivor, subsequently contained by stopping the owned
VM. The complete public export is retained: BEGIN/END agree on archive
5c5cb813f18dbed3e1e0910db1db1d28c574c4ba43e0c6fa69824a216a65b0d1,
1429313 bytes and 2792 chunks. Its receipt SHA256 is
90969d441b70bc49ffa6a25b159a5f6262fbb683d1a24feae12befed58828c83.
The complete final UART snapshot SHA256 is
e46676ef07003f9e87b34daf0e883c5dbda5327895703fa3dfa1a20e872d47aa;
the exact appended interval is
562a3b1581adb768465c01432e9db490621009f6b02adf4888100c67c19b416a.

This Maps retry has an operator setup defect: the separate data volume was
not mounted before broker provisioning. App data and the intended private-log
copies went into RAM. After sync returned to the prompt, owned QEMU26784 was
stopped and confirmed absent before offline access; the ext2 root contains
only lost+found. Private maps.log/broker.log and the partial storage watch were
therefore lost at shutdown. The public archive deliberately excludes those
logs. It is not a complete private audit bundle, and this run cannot establish
the cause of the app exit or the effect on dynamic AOT attempts. No memory,
performance or sign-in improvement is claimed. Failed snapshot/plan attempts
remain retained, including a rejected wrong receipt hash and a rejected mixed
API/Maps input; the valid account derivation uses the snapshot's exact appended
interval, preserving both complete exports.

The controller now checks explicitly selected data-image metadata before
SQLite preparation or app provisioning. It requires protected metadata and
probe files, the selected probe's exact digest, successful --check execution
and one proof matching the selected UUID/mount and write/sync/rename/readback.
Missing preparation fails before app data can enter the RAM fallback. Images
without selected volume metadata retain their prior behavior. The operator
must run /opt/current-api/data-volume --mount first; this verifies UUID,
geometry, mount flags, ownership, space and actual write/readback.

Host self-tests cover successful proof and missing/duplicate/wrong UUID/wrong
mount/incomplete-write/failed-process refusals. The updated controller's host
suite and static ARM64 build passed with available V 0.5.2 7d74206 under the
original host caps, all 0/0 with complete cleanup. Producer evidence is
data-volume-controller-build-20261114-r1 (34190 ms, sampled RSS 527400960,
growth 200708096). ARM executable SHA256 is
f72c5eba137066fc0024e5341e62c71fdeaf2b024ef7f12235e725f69e1ff22e.
An earlier compile was refused before launch below the 1-GiB reserve; space
subsequently recovered. Guest validation and a correctly mounted Maps retry
remain required.
