# Binder caller identity, 2026-10-29

The worker-enabled Maps run reached a concrete rejection:
`SecurityException: Only 0p apps are allowed to call this API.`
The local GMS delegate explicitly calls `Binder.clearCallingIdentity()` before
`aqxf.i(Context)`. Its `bpbx.T(Context)` passes `Binder.getCallingUid()` to the
trust predicate. Deployed clear/restore were no-ops, so broker UID 1000 survived.

The fix preserves GMS's trust checks. On the exact active authenticator worker,
clear selects the process UID/PID and disables the synthetic permission grant.
Restore accepts only an issued snapshot from the same dispatch epoch. Two
prior-state tokens support repeated and nested restores with constant memory.
Tokens expire on return, including pending exceptions; exhaustion fails closed.
Main and unrelated app threads cannot change the worker identity. JNI reference
ownership and shutdown are unchanged. This follows AOSP's per-thread snapshots:
[Binder contract](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android10-release/core/java/android/os/Binder.java)
and [IPCThreadState](https://android.googlesource.com/platform/frameworks/native/+/refs/heads/main/libs/binder/IPCThreadState.cpp).

## Verification checkpoint

Artifacts are outside Git at
`/Users/alex/.local/state/vinix/android/auth-identity-checks-2026-10-29-r1`.
The production-worker check passed with real pthreads, normally and with ASAN.
It covers permission/clear/self/restore, repeated and nested snapshots, stale
and unissued tokens, unrelated threads, exit and pending-exception cleanup,
exhaustion, and existing queue/shutdown/ownership cases.

| Attempt | Result | Seconds | Peak sampled RSS, bytes |
| --- | --- | ---: | ---: |
| `compile-worker-r1` | pass | 1.298 | 346,275,840 |
| `worker-r1` | pass, normal and ASAN | 4.557 | 174,096,384 |
| `compile-service-r1` | refused before launch: disk growth budget | 0.002 | 0 |
| `service-r2` | pass after external space recovery | 1.140 | 154,664,960 |
| `check-store-r2` | pass, 20 compiled negative mutations | 16.604 | 196,460,544 |
| `check-token-r2` | pass, 15 compiled negative mutations | 11.452 | 149,766,144 |
| `broker-r2` | pass, integration and DEX assembly | 6.882 | 228,016,128 |
| `jni-r1` | pass, generated and compiled JNI widths | 3.086 | 203,898,880 |
| `legacy-runner-r2` | pass, preserved original invocation | 5.925 | 181,977,088 |

The worker attempt captured base revision
`691c81bbecd9900d259c465b6ce92010574467f3` plus working-tree inputs:

| Source | SHA-256 |
| --- | --- |
| `nativews/account_service.v` | `de33aa1ae37bb430942bccd1f28f629519dd9d29da866898d78130fcbf7ae8bf` |
| `nativews/account_worker.v` | `db0f426089da7b3397662a1dcf93a1de37aa32979e4edfa746a63b01855a1c5c` |
| Worker checker | `a6c96fcfac302ab59f026dba5643e288ae1b4945bdd32b9a30be7b550746272f` |

All attempts retained the 600 MiB RSS, 300 second, 512 MiB growth and 1 GiB
reserve limits. Refusal occurred with 1,607,221,248 bytes free, below the
1,610,612,736 bytes needed to back growth plus reserve. No child started;
limits were unchanged. External space subsequently recovered above 7 GiB;
separate `r2` attempts retain the same budgets and preserve the refusal.
The first isolated-runner compile also remains preserved: V3 rejected array
concatenation. Replacing it with clone/append passed without changing limits.

The framework checks preserve all original fallback bodies and reject 13
identity mutations, four context mutations and five existing fallback controls.
They exercise the normal filesystem entry point as well as the narrow identity
transformer. The historical four-native factory remains unchanged; the current
entry point appends the two identity natives and installs both Binder wrappers.
The maintained isolated runner retains the exact production assembly/capture
helper closure and input pins. The separate JNI check uses the current binding
rows and exact JNI generator, rejects three width mutations, and compiles/runs
the actual exported wrappers with a 64-bit token and boolean restore result.

Independent source review found no blocking security or lifetime defect.
Focused host checks pass. Full producer results are recorded separately; ARM
regression and Maps retry with this fix remain pending. Google login remains
unverified.

## Continuation checkpoint

Source fix `40724ff01` now has a completed, sealed
[framework successor](binder-identity-framework-2026-10-29.md) and
[native companion](binder-identity-native-2026-10-29.md). The
[image and kernel tools](maps-binder-identity-stage.md) passed their compiles,
selftests and complete framework/native audit. The
[fixture runner and transfer profiles](binder-identity-fixture-run.md) pair
those exact outputs with the authenticator regression and
[standard JSSE TLS v3 probe](maps-network-fixture.md).

Image preparation refused before launching a child: 2,998,128,640 bytes free
versus the unchanged 5 GiB backing requirement (4 GiB growth plus 1 GiB reserve).
The failure is preserved in the sealed stage evidence. The planned output
`/Users/alex/.local/state/vinix/android/maps-binder-identity-r1` is absent;
no VM is running. All reported evidence roots are closed and must stay unchanged.

Once at least 5 GiB is available, use fresh controls for guarded preparation,
verify and clone its complete image, and install the frozen kernel with the
new explicit profile. Keep the original resource guards and one 12 GiB,
four-CPU VM. Run both fixture profiles, start the account broker before Maps,
then inspect Add account and map imagery. ARM/ART execution, Google sign-in
and tile rendering with this coupled identity build still need live evidence.
