Compile `run.v` outside the checkout and run it with
`ASAN_OPTIONS=detect_stack_use_after_return=1`. It uses the production heap,
channel and cache-barrier code with `-gc none -manualfree` and ASan/UBSan.
Firmware, timer, privileged atomics and lock services are host fixtures.

The fixture checks every byte of both 48-byte cache commands, rejects unsupported
ABIs, enumerates 256 strict threshold boundaries and exercises 768 heap/ring
cases. Cases cover both trigger heaps, unequal captured counts, live pins,
releases after snapshots, immediate/delayed acknowledgement, modulo wrap,
failed doorbells racing with consumption, full/corrupt rings, timeouts, fault
transitions, startup and unsupported hardware. Additional cases inject pointer
corruption, an unexpected write pointer, a latched fault or a manager stop at
completion. Freed metadata must be poisoned. Live and later-released records
must remain accessible. Fake time supplies the acknowledgement during polling.

`AGX_HEAP_GC_C` and `AGX_HEAP_GC_BINARY` retain results externally.
`--source PATH` selects a manager-source variant; `--wire-source PATH` selects
an isolated copy of the wire source. `counterexamples.v RUNNER FRESH_DIRECTORY`
retains eleven compiled negatives and requires runtime assertion failures.

The historical bundle uses `check.v --host C`, `--selftest C` and
`--native C BASELINE_C` to verify generated C, reject five checker mutations,
and compare existing allocator, transport and
backing lifetime bodies with a retained baseline. `qualify.v --prepare STATE`
creates an isolated native worktree. `--aarch64 STATE` and `--x86_64 STATE`
build and retain kernels, C and V-source inventories; `--resume-x86_64 STATE`
can finish an interrupted build. x86 uses the explicit ELF linker.
`--allocations STATE` runs the existing repository allowance checker and retains
its report. An expected nonzero result must still be compared against baseline;
it is not a passing allowance check. No runner boots or deploys a kernel.

The new helper retains garbage after a failed barrier and collects only its
pre-barrier prefixes on success. Existing eager teardown and allocation-pressure
GC are unchanged; the fixture does not claim global scheduling equivalence,
firmware execution, hardware timing, backing-policy equivalence or slab rates.

`qualify.v --baseline-x86 STATE` generates an unmodified control with the current
compiler when a historical C comparison encounters compiler drift. Its strict
comparison still uses the original checker. `evidence.v --seal STATE` copies the
complete sources and results, records an inventory and verifies a full archive
restoration. `--bind STATE COMMIT` binds committed feature sources and reports;
`--cleanup STATE` removes only the private worktrees and verified restoration.

See [the device-control completion report](../../docs/m1-agx-device-control-completion.md)
for the current completion regression cases and native builds.
