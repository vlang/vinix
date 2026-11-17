# Deferred private collection during normal G13 teardown

`v run tests/agx-teardown-gc/run.v` extracts the four production teardown
functions, scene/slot release and shared-buffer backing release. It runs real
heap and channel/cache-barrier code with ASan/UBSan, `-gc none -manualfree`.
Use `ASAN_OPTIONS=detect_stack_use_after_return=1` for fake-stack checking.

The 512 cases cover render-buffer, queue, render-job and compute-job teardown,
both supported firmware ABIs, below/above-threshold garbage, published/unpublished
cleanup and repeated calls. A failed or skipped pre-teardown barrier must not be
bypassed by cleanup. Private/GPU-read-only records remain pending; shared classes
retire immediately. Physical-release tokens and driver-buffer masks reject double
release. Refused cleanup retains ownership, then a retry succeeds. A later
immediate/delayed acknowledgement collects exactly the captured prefixes; failed
send, timeout, state/fault changes and full/corrupt rings retain them. Releases
injected after the snapshot remain reserved. Live pins survive throughout.

UAT invalidation, driver buffers, events and physical release are instrumented
host services. These tests exercise production control flow and allocator/cache
policy, not native firmware execution. The backing helper's external page-size
binding is renamed to avoid V's cross-module name collision in host builds.
The TVB slot-count constant is extracted from the real firmware definition.

`AGX_TEARDOWN_C` and `AGX_TEARDOWN_BINARY` retain artifacts externally.
`--source FILE` selects an alternative `g13.v`. Temporary fixtures are removed
before successful or failed exit. `counterexamples.v RUNNER BASELINE_SOURCE
FRESH_OUTPUT` compiles the actual baseline and each of the six reintroduced
private GC calls. All seven binaries must fail the pending-owner assertion;
compiler errors do not qualify as detected counterexamples.

`check.v --native CURRENT_ARM_C BASELINE_ARM_C` restores the exact six removed
calls in the four C bodies and requires equality. Thirty-seven existing heap,
backing, UAT, cache, completion, shutdown and initialization bodies must match.
String IDs resolve by value and numbered return/array temporaries are renamed
consistently. `--selftest` rejects four premature-GC mutations plus backing and
stopped-state mutations. Source guards preserve initialization/stopped drains.

`qualify.v STATE` verifies the preceding complete bundle's preparation source,
reuses its two-job native runner and overlays only `g13.v`. After all checks,
`evidence.v --seal STATE` retains complete sources/results, records the typed
inventory and checks a full archive restoration. Following commit, `--bind
STATE COMMIT` verifies exact paths/bytes; `--cleanup STATE` removes only the
private worktree and verified restore. Historical checkers remain unchanged.

Idle pending metadata/VA can remain reserved until the next allocator borrow or
shutdown. Retention can produce allocation failure while collection is unsafe.
See [the report](../../docs/m1-agx-teardown-gc.md) for evidence and limits.
