# Modern timeline input point zero

`dma_fence_chain_find_seqno(..., 0)` preserves the captured fence. This regression
checks that the modern adapter passes that fence to the existing pending worker.
It does not implement cumulative chains or enable zero-point timeline outputs.

Run the complete sanitized submission fixture and the host retention probe:

```sh
v -o /external/async-runner tests/agx-async/run.v
ASAN_OPTIONS=detect_stack_use_after_return=1 /external/async-runner
MallocNanoZone=0 /external/async-runner --measure-zero-sync
v run tests/agx-sync-zero/counterexample.v /external/async-runner /external/fresh-negative
v run tests/agx-sync-zero/reference.v /path/to/pinned/linux /external/fresh-reference
```

The negative case compiles the original committed stager and requires the
publication-blocking assertion to fail. Compiler errors do not qualify. The
reference runner verifies the packaged Linux revision and source bytes, extracts
the unchanged C lookup function and executes 4,000 zero-point calls with
ASan/UBSan. Its nonzero-only helper stubs abort if called. Rust wrapper sources
are retained and checked; the Rust wrapper is not compiled by this oracle.

`checks.v` adds 160 real modern-ioctl scheduler cases, covering generic and
foreign-queue waits, own-queue elision, completed/failed inputs, immutable fence
snapshots after reset/replacement/handle reuse, and input errors independent of
the output status. Missing, empty and foreign objects still fail. The macOS malloc
probe checks pending and completed snapshots over three warmed batches each.

Build both architectures with only the kernel fix over the recorded baseline:

```sh
mkdir -p /external/state
v -o /external/native tests/agx-sync-zero/native.v
/external/native prepare /external/state
/external/native aarch64 /external/state
/external/native x86_64 /external/state
/external/native allocations /external/state
v run tests/agx-sync-zero/check.v /preceding/blob-aarch64.c /external/state/blob-aarch64.c
v run tests/agx-g13-failure/check-completion-order.v /preceding/blob-x86_64.c /external/state/blob-x86_64.c --x86
```

`native.v` fixes the baseline to `bf309feea4dc9ef2cde667d02ed83fcc5464216c`.
The ARM checker requires whole generated-C equality outside the modern stager,
after normalizing only compiler discard-variable path hashes. It also checks
the captured pointer assignment and absence of implicit allocation. The original
modern-adapter checker still applies. Allocation diagnostics must match the
preceding baseline by file/kind; existing allowance failures are not waived.

`evidence.v` seals the complete new evidence, retains the original preceding
archive check, performs full archive restoration and binds committed feature
bytes. Its expected filenames document this run's receipts. Results belong
outside Git. This host-only increment does not qualify firmware or hardware.
