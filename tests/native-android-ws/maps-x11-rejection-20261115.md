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

Fresh guest validation is pending; account authentication and full Maps
operation remain unqualified.
