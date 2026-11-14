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
subsequently recovered.

## Correctly mounted retry, r87

Fresh maps-current-20261114-r87 selected this ART candidate and the f72c5e
controller above. The data-volume probe mounted the actual /dev/vda ext2
volume at /var/lib/vinix/apps, UUID 8aa84786a7234219a799f5367a94c9fc.
Its sync/rename/readback proof passed before broker provisioning, the broker
printed DATA-VOLUME-VERIFIED for that UUID, and a second terminal independently
checked the mount. The controller's ARM self-test passed, including its
256-iteration polling-memory check. The selected-data-volume gate is now
positively exercised on ARM.

Maps eventually rendered onboarding and Add account. Selecting Add account
did not reach a credential form. Its private log records an uncaught
UnsupportedOperationException from AccountManager.vinixAccounts/getAccountsByType
on a GMS intent-operation executor, followed by killProcess and System.exit(0).
The old message, "account query failed or timed out", does not distinguish a
transport/protocol rejection from the five-second deadline. No dex2oat text
appears in either retained private log; this observation does not establish a
controlled startup-speed improvement. Host load was high, and no cause of the
latency is claimed.

The storage watch completed 600214 ms, with minimum available data-volume
space 7954210816 bytes and minimum reported guest MemFree 4090656 KiB.
These are sampled minima, not a full memory-leak qualification. Checked stop
returned user-stopped-no-authentication-claim, empty controller error and one
cleanup survivor. The private result directory was copied to the verified
ext2 mount and synced before stopping owned QEMU95028. The process and open
disk handles were confirmed absent before read-only debugfs extraction. Both
private log hashes match private-log-sha256.json. Unlike r86, the private
diagnostics and completed storage watch survive offline.

Evidence under /Users/alex/.local/state/vinix/android:

| Artifact | SHA256 |
| --- | --- |
| maps-current-20261114-r87/private-readback/results/maps.log | 9ab99a0d86ccad1d4be22934c5e343ccb60c744b41c30fda33abc01c04a770c7 |
| Same directory, broker.log | 0e37f816d7359d245875270c3a013f9cf1cdd0e335d2a475ccc3ecf554f1b15d |
| Same directory, receipt.json | 26f250520b7618e0ae5e90e9c48f48fdbdeec692ca4663f103a5c54d03b70e21 |
| maps-current-20261114-r87/private-readback/storage-watch.log | 02cb0cd6ed9b0d11ab7722373daad462e1fa4c787b2007d4541dd222dfe8ea9d |
| maps-art-r87-uart-20261114-r1/full.log | 1c3e57d95744bdbfdd088d4b641b1b83a17d3036288fb940a69e1ddcb518197f |
| Same snapshot directory, receipt.json | cc28ae8ba7ec6d93cb6ceab5c4c74e3b5500641b18d1b85d2e218af2a9eabb55 |

Public export BEGIN/END agree on archive
09e12d0af2f6f62f15ca144dbbfe27396b59e3e951c07cf4e5b3798d4cedff30,
1429465 bytes, 2792 chunks. However, the operator sent a volume-check console
write during export, interleaving it into a CHUNK. The unchanged empty-removal
plan writer correctly rejected it as noncanonical frame fields. Raw UART and
the failed plan guard/log are retained; no repaired export or strict-import
pass is claimed. Future volume checks must finish before export begins or
wait until its END. The independently retained private files above remain
available. A read-only fsck child exited zero, but its 64-MiB shared-growth
guard failed at 75952128 bytes; that attempt is not a guard pass.

Google authentication and fully responsive Maps remain unqualified.

## Query failure classification

The JNI query now preserves distinct fixed exception messages for deadline,
transport failure, response-identity mismatch, broker rejection and unexpected
event kind. No request/account/payload text enters them. Continued responses
still wait for a terminal account list, every path closes the client, failures
still throw, and the five-second deadline and authority checks are unchanged.
This is diagnostic preparation, not a fix or authentication claim.

The production-extracted native-store suite passed with available V 0.5.2
cbfc1be, executable SHA256
9bde2851cedea03c3e488b0793a356aeb90644d13cf49e10fae6bf5518fff000.
It verifies all five failure messages and pending/continued-to-success behavior,
alongside the existing 20 compiled negative mutations. Evidence is
account-query-checks-20261114-r2, inventory SHA256
6d562df410d1489334f8c1ecbcfbe32684581dac63cc8e488636177c27539a68.
The original guard passed 0/0 with complete cleanup: 18966 ms, peak sampled
RSS 236994560 bytes, shared growth 195358720 bytes. The checker now invokes
the current compiler path with the current compiler flags.

The full ARM native adapter build also passed 0/0 with complete cleanup in
account-query-native-build-20261114-r2: 15860 ms, sampled RSS 579026944 bytes,
shared growth 111251456 bytes, under the original caps. Its DSO SHA256 is
29fbace1c1f5f91c3a74281edc2094c6c75bab7eb200448ef8d6c925be331553.
The first build's signed-char warning remains retained; explicit &char casts
fixed the emitted C without disabling -Werror. This diagnostic adapter has
not yet executed in guest ART. No compiler version was rolled back or pinned.
