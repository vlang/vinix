# G13 render scratch validation order

The packaged Asahi queue constructor resolves the VM and constructs the queue
before the default `reserve_render_scs` rejects nonzero layouts. Vinix follows
that order and rolls back the unpublished queue through its existing release
and orphan-owner paths.

```sh
v -o /external/close-runner tests/agx-file-close/run.v
ASAN_OPTIONS=detect_stack_use_after_return=1 /external/close-runner
MallocNanoZone=0 /external/close-runner --scs-measure
v run tests/agx-queue-scs/counterexamples.v /external/close-runner /external/fresh-negative
v run tests/agx-queue-scs/reference.v /path/to/pinned/linux /external/fresh-reference
```

`checks.v` runs 750 cases through the real DRM node/table/handlers, using the
existing injected GPU graph constructor and release outcomes. It covers header,
priority, VM, host/GPU allocation and partial-construction precedence; successful
zero-layout creation; unsupported layouts without name publication; heap logical
record disposal; and retained graph/VM/ID ownership through worker or close retry.
Three compiled mutations must fail designated assertions. Compiler failures do
not count. The macOS malloc probe measures three warmed batches of 1,000 rejected
creates each, for both immediate and retried release.

The reference runner checks the packaged source revision and byte identities,
retains the relevant Rust files, checks operation order and verifies the shared
G13 queue implementations do not override the default scratch-layout method.
It compares source; it does not execute Rust or firmware.

```sh
mkdir -p /external/state
v -o /external/native tests/agx-queue-scs/native.v
/external/native prepare /external/state
/external/native aarch64 /external/state
/external/native x86_64 /external/state
/external/native allocations /external/state
v run tests/agx-queue-scs/check.v /preceding/blob-aarch64.c /external/state/blob-aarch64.c
v run tests/agx-modern-ioctl/check.v --native /external/state/blob-aarch64.c
v run tests/agx-g13-failure/check-completion-order.v /preceding/blob-x86_64.c /external/state/blob-x86_64.c --x86
```

The isolated baseline is `d517147354c765f18b77d98d91c8be13cd4d76c1`, with
only two kernel overlays. ARM C outside the three constructor bodies and changed
helper prototype must match after normalizing compiler discard-variable path
hashes. The checker requires correct rollback/free/publication order and no
hidden allocations. The original x86 and modern-adapter checks remain unchanged.

`evidence.v` validates the named receipts, compares every allocation file/kind
and architecture total against the preceding baseline, seals/restores the full
new bundle, checks the preceding original archive, and binds committed feature
bytes. Keep results outside Git. The fixture's immediate-success release is
not evidence of synchronous native cleanup: native first release normally
defers context retirement. No hardware execution is qualified here.
