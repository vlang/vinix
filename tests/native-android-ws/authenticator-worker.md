# Authenticator worker dispatch, 2026-10-29

The Maps diagnostic captured `IllegalStateException: BlockingServiceConnection.getService()
called on main thread` during GMS `addAccount`, followed by terminal error 1.
Commit `553980683` moves Java authenticator calls from the service main Looper
to one Binder-style worker. Activity launches and service lifecycle callbacks stay on
main. Native account-list and token-invalidation operations also stay on main:
an authenticator can synchronously request them while its Java call is blocked.

The worker has an eight-command waiting FIFO and one active command. Saturation
returns a per-request busy error instead of terminating unrelated sessions.
Only the exact worker pthread, during its synchronous authenticator call, can
use the synthetic broker UID/PID and `ACCOUNT_MANAGER` permission. Main and
unrelated app threads retain their own identities.

Commands own copied transport values. The daemon-attached JNI worker owns its
retained Binder and uses a local frame per command; cancellation and shutdown
share the slot-publication lock. Shutdown drains queued work without an
unbounded join. An active call retains its context until it returns or the
service process exits, since it may need main-Looper callbacks to finish.
`native-entry.v` exits the process immediately after service entry returns.
Worker exceptions remain private; the main pump receives a finite failure code.

Commit `f2bd50b8c` replaces the native producer's bootstrap process with its
verified compiled producer. This releases bootstrap allocations while preserving
the PID, selected arguments, environment, standard streams and exit status.

## Completed host checks

The final worker check executes extracted production code with real pthreads
and instrumented JNI boundaries. Normal and AddressSanitizer runs passed FIFO,
worker-only identity, overload reply, queued/active cancellation, shutdown and
exactly-once ownership cases. It also exercises native list/invalidation through
the production main pump while the authenticator is blocked, plus pending-JNI
exception cleanup. This is not an ART run.

Artifacts below are relative to `/Users/alex/.local/state/vinix/android` (`S`).

| Check | Artifact | Seconds | Peak sampled RSS, bytes |
| --- | --- | ---: | ---: |
| Final worker, normal and ASAN | `auth-worker-checks-2026-10-29-r1/worker-check-r6` | 6.368 | 205,996,032 |
| Callback/permission regression | `auth-worker-legacy-checks-2026-10-29-r1/service-r1` | 3.683 | 382,238,720 |
| Retained-graph interaction regression | `auth-worker-legacy-checks-2026-10-29-r1/interaction-r2` | 1.283 | 179,847,168 |
| Native store, 20 negative mutations | `auth-worker-legacy-checks-2026-10-29-r1/store-r1` | 20.578 | 199,000,064 |
| Token dispatch, 15 negative mutations | `auth-worker-legacy-checks-2026-10-29-r1/token-r1` | 16.986 | 311,230,464 |
| Final pump, 9 negative mutations | `auth-worker-pump-main-store-check-2026-10-29-r1/check` | 3.170 | 184,844,288 |
| Producer process replacement | `native-producer-handoff-check-2026-10-29-r1/check-r1` | 14.169 | 363,757,568 |

Passing guards recorded exit/child status zero, complete cleanup and zero swaps
under 600 MiB aggregate RSS, 300 seconds, 512 MiB observed shared-volume growth
and a 1 GiB reserve. Earlier worker-harness compiler failures, a pump-model
mutation assertion mismatch and a missing interaction-test store stub remain
preserved beside the passing attempts. The earlier pump pass predates the final
native-operation split; the separate final pump artifact above validates that
split. No guard was increased to obtain these passes.

Final worker inputs match the committed production source:

| Source | SHA-256 |
| --- | --- |
| `nativews/account_service.v` | `7369030274a40f2c9b4abafbd854c61fe9f48b29152dd0de7e78dce1df56bae6` |
| `nativews/account_worker.v` | `db0f426089da7b3397662a1dcf93a1de37aa32979e4edfa746a63b01855a1c5c` |
| Real-pthread checker | `87bc8927f2003e563eff3a860c82064ae39460c9ded76e1f82cc0184307ecd62` |

## Native build and remaining validation

The full canonical native producer passed at
`S/current-native-build-2026-10-29-auth-worker-r1` (`P`), with controls in
`S/native-auth-worker-build-2026-10-29-r1`. It recorded source revision
`f2bd50b8cd6eb18238da5f5f7a2b156eeacbded4`. The producer guard exited zero with
complete cleanup after 45.637 seconds, at 619,266,048 bytes peak sampled RSS
and 392,368,128 bytes observed shared-volume growth, with zero swaps. Limits
were 600 MiB aggregate RSS, 300 seconds, 2 GiB observed growth and a 1 GiB
reserve. Shared-volume measurements do not isolate producer-owned allocation.

| Native output | SHA-256 |
| --- | --- |
| `P/sha256.json` | `048602ab4aa188111bad295a5af9d1b47c6cceee0fd82f0eb73858689b22a921` |
| `P/build.json` | `3e7d063ed01484a91ae9ef02bb78b648168dc815700a28522adf88d622aed2d9` |
| `P/native/libvinix-android-native.so` | `0ef0acd98c148b9b972f754e5fb1e23683e8dc7d0b56f05d2f0a4c7792206136` |

The six evidence roots above are bound in place by
`S/auth-worker-evidence-2026-10-29-r1/sealed/manifest.json`, SHA-256
`3c9aa5842953ff85a0d61cc0e2422e1602b9ca4a41f11ed99285fa604b76c771`.
Seal and separate fresh-process full readback passed for 2,222 entries, with
exit/child status zero and complete cleanup. They took 0.803/0.530 seconds and
peaked at 23,019,520/22,904,832 bytes sampled RSS, under 600 MiB RSS, 900 seconds,
64 MiB observed growth and a 1 GiB reserve. Adjacent guard receipts retain the
measurements. Keep all six closed roots unchanged; this report does not replace
the complete bundle.

The worker fix has not yet run in guest ART or the real Maps account flow.
Google authentication and usable map imagery remain unverified.
