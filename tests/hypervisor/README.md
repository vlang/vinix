# Hypervisor checks

`sh tests/hypervisor/run.sh` checks the public ioctl layout. Run
`tests/hypervisor/check-vmx` for the production V control helpers
and ARM no-op ABI under ASan/UBSan. The host fixture checks 7,680 cases,
including every byte-valued failure status, 64-bit operands and VMREAD output
preservation. Only privileged instructions are adapted in the host control
fixture; production x86 assembly is separately cross-compiled and inspected
for immediate CF/ZF capture, operand order, memory barriers and allocation
imports, including the INVEPT helper. `--original /path/to/pre-port/vmx.c` also
verifies that every VM-entry instruction byte matches the former global assembly block.

After building an isolated kernel, boot it with:

```
tests/hypervisor/run-vm --arch x86_64 --kernel-dir /path/to/kernel
tests/hypervisor/run-vm --arch aarch64 --kernel-dir /path/to/kernel
```

The guest reports whether VT-x was available. An absent `/dev/hypervisor`
checks boot integration and native syscalls, without claiming VM-entry
coverage. When available, it creates five VMs, checks all guest GPRs across
IO/HLT exits and closes each session. `--require-vmx` requires that execution
marker; use it on an x86 setup with nested VT-x. The local macOS ARM host's
x86 QEMU TCG setup cannot provide that coverage.

The maintained guest fixture is `guestfixture/core.v`. Its 15 assertions and
failure line numbers remain those of the original independent C fixture.
`tests/hypervisor/host-test --state-dir /new/isolated/directory`
compares both versions under ASan/UBSan in 19 success/failure cases. The host
model checks the complete public ABI sequence and all 15 register values for
each of five VMs; its Darwin ARM variadic entry uses an instruction-only native
adapter. These model checks complement the native guest checks and do not
claim physical VMX execution.

## Guest memory and session lifetime

Build an isolated x86 kernel with `VFLAGS='-d hv_memory_selftest -d hv_memory_fixture'`
and run the V controller:

```
tests/hypervisor/run-memory /path/to/isolated/kernel /path/to/new/state
```

The opt-in early kernel test uses the real PMM before other CPUs or the
scheduler start. It checks sizes from one byte through 1 GiB, page rounding,
zeroed frames, EPT flags, unaligned copies across 4 KiB/2 MiB boundaries,
overflow refusal and idempotent teardown. It injects allocation failures at
root, leaf-table, RAM and FPU allocation boundaries and measures exact physical
free bytes after rollback and 100 VM lifetimes.

The test-only device uses the same allocation path and keeps VM entry disabled.
The V guest creates a 1 GiB VM and checks its last byte through the public API,
then checks 100 sessions, size limits, file I/O, shared mappings
after final close and fork, concurrent CREATE_VM, ordinary-user denial and
rejection of private/out-of-bounds mappings. It warms the workload and waits
eight seconds past deferred retirement before comparing live slab counts.
The controller owns a 2 GiB QEMU TCG guest and retains the ISO, fixture, serial
transcript and SHA-256 receipt in the new state directory. It copies the input
kernel before preparing the ISO. Production kernels enable neither tag;
their device still requires a successful hardware VM-entry self-test.
