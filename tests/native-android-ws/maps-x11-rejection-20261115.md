# Drain readable X11 rejection replies, 2026-11-15

The retained private diagnostics in a889d0092 identified the r109 account
layout failure as X11 admission socket failed, before engine startup. The
[complete account evidence](maps-browser-engine-20261115.md) is retained.
Vinix Unix sockets mark peer close with POLLIN|POLLHUP|POLLERR even when
received data remains queued. The browser display waiter rejected POLLERR
before checking readable data; this could discard the expected rejection
header from its wrong-cookie admission test.

The waiter now drains requested readable data before interpreting POLLERR or
POLLHUP. POLLNVAL remains fatal. Writable connection admission still rejects
POLLERR before checking readiness. The exchange still requires eight bytes,
the same absolute deadline and the existing peer-credential and X11 response
checks. A rejected cookie is still rejected; no browser sandbox or authority
checks are removed. This does not yet identify r108's later engine exit.

The seven focused connection tests passed normally and under AddressSanitizer
(detect_leaks=0, halt_on_error=1). They cover Vinix's combined readable/close
flags, invalid descriptors, writable errors, zero/one/seven/eight-byte rejection
headers followed by close, descriptor cleanup, silent peers and byte-dribbling
deadlines. The saturated-backlog case is Linux-only and skipped on macOS.

External evidence root: /Users/alex/.local/state/vinix/android. Generated C and
test binaries are in browser-failure-tools-20261115-r1; receipts/logs use
browser-x11-tests-*. The paired protocol build in browser-x11-protocol-build-
20261115-r1 passed with captured inputs and current V 0.5.2 cbfc1be under the
original RSS 629145600, wall 300000 ms, reserve 1073741824, shared growth
536870912 and output 4194304 limits: elapsed 29916 ms, sampled peak RSS
373161984, shared growth 62640128 bytes, exit/child 0/0, empty reason, cleanup
complete. Fresh static AArch64 run-android SHA256:
3346f3f2db2efc5c71a70e742537bf169fc3cd8cd79bbcbdb0f78087121db11d.

## r110 ARM and account validation

Fresh staging and the complete signed ARM suite passed, child exit 0,
readiness pass and CURRENT-API-PASS. The complete API export reconstructed
without removals: 24059 bytes / 47 chunks.

| API evidence | SHA256 |
| --- | --- |
| maps-x11-api-uart-20261115-r1/full.log | 43c53db1c12263885be3a67b1c17fffba67399c517fedb11ef8a6ef631700f68 |
| maps-x11-api-readback-20261115-r1/archive.json | 2ea63d73400342261b2463494741aa298fbf3e580106be6498a5d0ba2af05d5f |
| maps-x11-api-child-20261115-r1/child.log | f9423e31cdf8e9dd206ccec83307b46793dc38f887e3b0ec036296cd0cbe542b |

GMS PID46062 reached readiness on checked persistent volume
3609809ece464cb5bd783d0c5b7a4bf6. The descriptor snapshot mistakenly requested
PID46602 and failed; no readiness descriptor measurement is claimed. Maps
launched once, rendered onboarding and the chooser, then attempted Add account
once. Three device check-ins succeeded. This time display admission passed:
the launcher reported browser engine exited status=1, and the retained private
log identifies cannot open cookie snapshot database. It also contains two
Mesa DRI2 warnings. There is no sandbox failure in that log. Maps exited on the
account-query deadline. No credentials were entered or account authenticated.

The cookie store combines SQLite OPEN_NOFOLLOW with an intentional
/proc/self/fd directory alias. SQLite rejects symlinks in every path component.
The existing account store already uses the validated canonical path for this
reason. The cookie-store follow-up preserves no-follow, ownership, mode and
link-count guards while adopting that same canonical-path approach.

The checked stop and complete account export finished. The 1057-byte private
failure log and complete results were copied to r110-private and synced.
Mount check, copied log/receipt and prompt preceded stopping QEMU32481. PID
absence and no image handles preceded read-only extraction; e2fsck passed.
The public account export reconstructed without removals: 1429893 bytes / 2793
chunks. Its receipt compares identical to the private copy; private log hashes
match their manifest. Receipt status is user-stopped-no-authentication-claim,
cleanup_survivors=1, so complete controller cleanup remains unqualified.
All owned test guests are stopped. Full Maps operation remains unqualified.

| Account evidence | SHA256 |
| --- | --- |
| maps-r110-uart-20261115-r1/interval.log | 116766214b86bc2564195a1d5db8abeea2a1d685e1f0798315932540737a8b4a |
| maps-r110-readback-20261115-r1/archive.json | 5c65f40c798b38861300ae7f31c49e94acfb28e3001270bba5dba57393d47730 |
| Same readback/exported-receipt.json | 90a284c7e02216a4624699203690a620a9e140a751940de995e5253a81dbd112 |
| Private r110-private/results/broker.log | 76e808ee4cbb073b62c057446088d499d21cd5e7a588edca08ee66e36aed5260 |
| Private r110-private/browser-failure.log | 6e57cb699f86abcdab0e9521b846fc16e63bb22b23e69d01d1b3ac77ba2b261b |
