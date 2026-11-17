# Modern Asahi sync lists beyond 64 records

Modern submission uses inline storage through 64 records per direction and
fallible owned spans beyond it. The syscall frees both temporary spans. Pending
work owns an independent input copy until final retirement. Legacy staging keeps
its 64-record limit. The combined modern count is checked as u32 before copying.

```sh
v -o /external/async-runner tests/agx-async/run.v
ASAN_OPTIONS=detect_stack_use_after_return=1 /external/async-runner
MallocNanoZone=0 /external/async-runner --measure-large-sync
v run tests/agx-sync-storage/counterexamples.v /external/async-runner /external/fresh-negative
v run tests/drm-syncobj-wait/run.v
v run tests/agx-sync-storage/reference.v /path/to/pinned/linux /external/fresh-reference
```

`checks.v` tests all 64 input/output combinations of 0, 1, 63, 64, 65, 128, 129
and 1,025 records through staging, copying and the actual pending scheduler.
The last input gates work after userspace bytes are freed and the syncobj is
replaced; the last output receives the completion fence. Another 320 injected
allocation/copy/lookup failures and 140 backend/stop/detach/immediate-completion
cases check every storage owner. Huge-allocation refusal is injected before
calling host malloc. The five negative variants must compile and then fail
their designated assertions; compilation errors do not qualify.

The macOS malloc probe measures only temporary sync buffers and their pending
copy, with stable metadata owners. Each 65/1,025-input-and-output case runs three
warmed batches of 1,000 operations. It does not measure complete submissions or
native slab retention. Existing syncobj/fence metadata retention remains open.

```sh
mkdir -p /external/state
v -o /external/native tests/agx-sync-storage/native.v
/external/native prepare /external/state
/external/native aarch64 /external/state
/external/native x86_64 /external/state
/external/native allocations /external/state
v run tests/agx-sync-storage/contracts.v /external/state
v run tests/agx-sync-storage/check.v /preceding/blob-aarch64.c /external/state/blob-aarch64.c
v run tests/agx-modern-ioctl/check.v --native /external/state/blob-aarch64.c
v run tests/agx-g13-failure/check-completion-order.v /preceding/blob-x86_64.c /external/state/blob-x86_64.c --x86
```

Native builds pin `f8d2c9d85bb78c34e97b26bdee880c2ca12656ed` plus six kernel
overlays. The contract runner uses that same isolated source, with the updated
accessor/cleanup contracts, excluding concurrent event edits. The new C guard
checks seven allocation-sensitive bodies, transfer/cleanup ordering and thirteen
unchanged owning/poll bodies. The original modern-adapter and x86 checkers keep
their contracts. Existing allocation-allowance failures are not waived.

`evidence.v` validates receipts, retains baseline/current sources and C/ELFs,
checks the preceding complete archive, restores the full new archive and binds
committed bytes. Keep artifacts outside Git. This removes a count limit; native
contiguous allocation and OOM/fault precedence still differ from Asahi's KVec
allocation. Timeline chains, purge backing and hardware acceptance remain open.
