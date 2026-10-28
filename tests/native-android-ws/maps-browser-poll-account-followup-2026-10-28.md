# Maps account followup, 2026-10-28

Maps' onboarding Sign in button opens an Add account/Cancel chooser. Selecting
Add account then ends the run: the controller reports that the Google Play
Services broker exited, and the Maps window shows the desktop's stopped or
exited application screen. No authentication was verified or claimed. The
previous four-of-six milestone count remains unchanged; tiles and authentication
are still unverified.

Artifacts are relative to `/Users/alex/.local/state/vinix/android/`. This run uses
`maps-browser-poll-vm-r3`, a fresh 12 GiB, four-CPU VM from the same nineteen-module
stage, frozen kernel and exact browser/runner deployment pinned in
[the first runtime report](maps-browser-poll-runtime-2026-10-28.md). The followup
build and audit roots are `maps-browser-poll-followup-build-2026-10-28-r1` and
`maps-browser-poll-followup-audit-2026-10-28-r1`. Its `launch.json`, clone proof
and retained build identities establish this deployment separately from later
checkout changes.

The broker started with `--broker --trace-onboarding`. A click at (412,590) at
10:02:55 UTC produced the chooser visible at 10:03:16. The chooser is positive
evidence of the in-process sign-in flow. A click at (370,386) at 10:03:36 selected
Add account. The 10:03:52 capture shows “The application stopped responding or
exited.” The controller's public receipt records 09:58:16–10:03:38,
`status=failed`, `service_ready=true`, `broker_exit=1`, `cleanup_survivors=2` and
empty authentication/browser initialization failure lists. Readiness and the
chooser do not establish authenticator completion or a Google account.
The cleanup count alone does not establish that workers remained alive.

| Capture in VM root | Host UTC | SHA-256 |
| --- | --- | --- |
| `sign-in-first-01.png` | 10:03:16 | `aad83970ec8983f2f235f1549e83c2399f18da138dd4eb2f6497eae98478ea28` |
| `add-account-01.png` | 10:03:52 | `e1b35e8de66c5dbe3919eb15a270e95e3a3f45ce5d151e5909f83511c35ac796` |

Two window-focus clicks occurred before the host detected the archive BEGIN
marker. Terminal text queries started only after its matching END marker. The
exact interval passed the unchanged strict collector without deleting or
repairing UART bytes: 24 entries, 1,441,575 archive bytes and 2,816 chunks,
archive SHA-256
`78f21c4dd0cec0409b99cf58de5b3e147f056753ee5dff9b27d861171b29b3d0`.
The 2,236,985-byte interval has SHA-256
`ac25da2e9f1a42e2afb8b1742b225677f5051dc74c7222ae8f4ef4bffd4b0167`;
the captured full 2,285,230-byte UART has SHA-256
`55f98225745b21513b914a38b997a1b25ce2873c36ea84c9be2db15528089a87`.
The baseline receipt is pinned by
`7c7ecbe42ec28f9dd756ba3809eeaf8586b5e77699f20832843dcdd6b556d6bf`.

Snapshot and strict-import guards/children exited zero with complete cleanup.
They took 397 and 857 ms, with sampled process-tree RSS peaks of 12,206,080 and
28,950,528 bytes respectively. Limits were 600 MiB RSS, 300 seconds, 1 GiB disk
reserve, 512 MiB shared growth and 4 MiB command output. Exact commands,
receipts, original UART and strict-import results are retained in the audit;
private Maps/broker logs are excluded from the producer's public archive.

Bounded static queries found one `account input disconnected` marker and no
browser transport failure, main-looper service failure, scheduling-stop,
VM-exit, Maps/broker uncaught-exception or Chimera Context marker. Exception
class counts included startup exceptions; the final stack query supplied no
failure stack. These observations do not identify a root cause. Source tracing
narrows the broker exit to a false account-service pump result; teardown clears
the pending request before a specific reason is recorded. Any new failure-stage
diagnostics require a separate deployment and do not belong to this run.

Host SIGTERM was requested at 10:11:08 for owned PID 90993. Initial stop exited
1 during transient ownership observations, then owned `reconcile-stop` recorded
absence and a separate process check confirmed it. The final UART preserved the
earlier snapshot exactly and appended 2,886 bytes, SHA-256
`7ceb33e0fc172d2b8200980db93fa7d091e1c8ecde427b05c7b410ec72797919`.
The closed 2,288,116-byte full UART has SHA-256
`3e1567203c73c408f5ed80ed20d2a21faaa33d49e38c9c51755b9bfc6c411cf9`;
the 2,239,871-byte suffix since the original baseline has SHA-256
`57424253acaf11bc56a45f67a2c27c4eb99f944a9f7a60490a1ceee932efda0e`.
Closed receipt SHA-256 is
`2771bfe1937e5a41dff91b4e1f3865f1f7ad2e31ea1a769b84538a599757d962`.
Closed snapshot/import guards and children exited zero with complete cleanup,
202/281 ms elapsed and sampled RSS 12,189,696/27,705,344 bytes. The unchanged
strict collector again accepted the same archive and exactly 24 entries.

The complete-root seal `maps-browser-poll-followup-sealed-2026-10-28-r1` passed:
107 frozen roots, 91,483 entries, manifest SHA-256
`00a3bf72f57cfab932dd5ef464f8c485af727de857128bfc0ced36f4f1adc449`.
Its adjacent `maps-browser-poll-followup-seal-2026-10-28-r1.json`/`.log` record
guard/child exit zero, complete cleanup, 129.097 seconds, 34,996,224 bytes sampled
RSS and zero swaps. The audit's `runtime-finalization.md` has SHA-256
`5dbc58e7fe67a60fd0ffdace7a64c5c9f31ecfbd7c17bc955cda984d39662a16`;
`roots.txt` has SHA-256
`f799471820b80ae71254ddd28b4023c1deb352c3c3a48adb322cd0aa13f4d6e4`.
Independent complete readback passed with matching roots, entries and manifest.
Its adjacent `maps-browser-poll-followup-readback-peer-2026-10-28-r1.json`/`.log`
record guard/child exit zero, complete cleanup, 65.909 seconds, 35,930,112 bytes
sampled RSS and zero swaps. The receipt SHA-256 is
`9f2fc5afa4ffb93eb2768e866cab0c9aa34415f7239333a1a940bfb57d71def7`.
