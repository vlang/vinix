# Modern native Asahi ioctl entry points

The native driver registers the legacy Mesa interface and eleven modern
operations from the packaged Linux-Aurora header. The first driver request
that reaches a handler selects its file's dialect, including when that handler
returns an error. Generic DRM operations do not select a dialect. Canonical
GET_PARAMS requests distinguish the formats by their size/direction. Selection
is serialized per file; construction of the file is serialized by the registry.

Run the production node/table/adapter and mapping cases with
`v run tests/agx-file-close/run.v`. Run the actual modern packet-to-pending
path with `v run tests/agx-async/run.v`. Both use ASan/UBSan and kernel GC mode;
set `ASAN_OPTIONS=detect_stack_use_after_return=1` for stack lifetime checks.
The surrounding suites retain their original legacy lifecycle coverage.
VM creation and mmap authorization are injected in the transport fixture;
VM_BIND, GEM creation, queue creation/capture/destruction, timestamp ownership,
submission and pending retirement run their production handlers.

On macOS, `MallocNanoZone=0 v run tests/agx-async/run.v --measure-modern-sync`
measures retained malloc blocks/bytes in three 1,000-operation batches, both
without syncs and with one binary input/output. Owners and namespace storage
are warmed once. This isolates sync staging, not whole-driver/native slab rates.
`--modern-sync-source FILE` accepts a retained baseline without modifying the
kernel module. The initial by-reference builder retains two records per call;
the value-snapshot implementation retains zero.

Build the two runners to external executables, then run
`counterexamples.v ASYNC_RUNNER CLOSE_RUNNER FRESH_EXTERNAL_DIR`. Four compiled
variants must fail designated assertions for scratch cleanup, captured USC
state, whole-batch copying and ABI selection. Compile errors do not qualify.
Each runner retains the negative executable and C before executing it.

`native.v prepare STATE` creates a private worktree at the recorded baseline
and overlays only seven kernel files. It excludes concurrent event changes.
Run `native.v aarch64 STATE`, `native.v x86_64 STATE` and
`native.v allocations STATE` sequentially. Builds keep two jobs, use MP on
ARM, and retain sources, generated C, ELFs and diagnostics. `checkpoint` preserves
the earlier diagnostic builds before a source correction; `refresh` refuses
to replace a retained successful build.

`check.v --native ARM_C` guards 18 modern/dispatch bodies against hidden V
allocations and checks temporary ownership, copy ordering, USC capture and
native table registration. `--selftest ARM_C` rejects six C mutations.
`check-allocations.v CURRENT_LOG BASELINE_LOG` compares every reported
file/kind count, allowing only the four new source files. The original strict
x86 checker remains `tests/agx-g13-failure/check-completion-order.v BASELINE_C
CURRENT_C --x86`. No allowance list or historical checker is changed.

The paired Mesa/image migration, GEM_MADVISE and native timeline-chain behavior
remain open. Zero-point timeline outputs return EOPNOTSUPP before publication;
input/output sync arrays retain the native 64-record bound. VM_BIND still uses
the existing contiguous/repeated-page backing and busy-VM policy. These are
kernel migration components, not a full-parity or hardware-acceleration sign-off.

`evidence.v --seal STATE` retains complete sources/results and verifies the
archive's full restoration. `--bind STATE COMMIT` checks the exact feature paths
and committed bytes against that sealed bundle. See
[the report](../../docs/m1-agx-modern-dispatch.md).
