# Authenticator expiry and root cancellation crossing

Based on 7aea50500. r70's normal account attempt reached the Google error page
after CheckinHelper's 10000 ms timeout. GMS later completed check-ins. The account
operation eventually reported cancellation code 4, followed by a transport-read
failure and service exit. The log does not retain the precise read rejection;
its causal connection to the race below remains unproven.

Inspection found a reproducible race: auth_read checked its five-minute local
deadline before consuming a queued root cancellation. It retired the session
without sending a terminal failure or preserving a completed-capability record.
Reading the legitimate queued cancellation next therefore disconnected the
authenticator as an unknown session. The new regression fails against the old
implementation in auth-expiry-repro-20261113-r1, including run2.log/exit 1.

Local expiry now queues a terminal cancellation failure, copies its capability
into the existing bounded completion window, then retires the session. The one
matching crossing cancellation can be consumed. Late response builders remain
invalid; wrong capabilities, replayed cancellations and unknown sessions still
disconnect. No authority deadline, admission limit or transport cleanup timeout
changes. The wire queue owns a copy before the source session is freed. Root
cancellation uses the same encoding helper without admitting a replay window.

Tests cover the crossing, stale response rejection, forged/replayed cancellation,
admission of another request afterward, and expiry/acknowledgement of all 32
sessions with the existing bounded output pump. Existing root cancellation,
drain limits and authority tests remain intact.

Evidence under `/Users/alex/.local/state/vinix/android/`, available V 0.5.2
6f888d6, original guard limits unchanged (RSS 629145600, wall 300000 ms,
reserve 1073741824, growth 536870912, output 4194304):

| Artifact | Elapsed ms | Peak sampled RSS bytes | Shared growth bytes |
|---|---:|---:|---:|
| auth-expiry-asan-20261113-r3, all 33 files | 76364 | 474677248 | 206942208 |
| auth-expiry-plain-20261113-r1, all 33 files | 70059 | 372375552 | 94859264 |
| auth-expiry-protocol-build-20261113-r1 | 31748 | 372146176 | 51597312 |

These exited 0/0 with complete cleanup. ASan address checks were enabled;
leak detection remains disabled for the existing manual-lifetime test fixtures.
The first broad ASan attempt stopped at the unchanged shared disk-growth cap
during VM provisioning (547823616 bytes). r2 caught a test assumption that all
32 replies flush in one iteration; the test now pumps the existing bounded
writer until every acknowledgement is verified. Neither attempt is a suite pass.
The final r3/plain/build roots retain copied source/compiler inputs and hashes,
commands, complete logs and receipts. No assertion or rejection was relaxed.

The build produced AArch64 ELF64 broker/launcher and an account DSO with the same
75 public ABI exports, depending only on libsqlite3.so.0 and libc.so:

| Artifact | SHA256 |
|---|---|
| libvinix-android-account.so | 1f690c8a044d0b500ae29f090bcdcc14e23f6c93798ea9d7ce8eada9ca5eaf6c |
| native-account-broker | 745acc59eacc7d76a4a403dac8765a15822b2ba116be6ff44f7423fef81656a8 |
| run-android | bcf0c7829f55ae47d8616d54b92a08a816e9d4b0e7cff115cccf4ee120a7a7e1 |

The pair must be deployed together. ARM runtime expiry validation remains
pending. This does not resolve or qualify the Google sign-in timeout, map tiles
or route geometry.
