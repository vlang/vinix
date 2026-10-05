# Hypervisor checks

`sh tests/hypervisor/run.sh` checks the public ioctl layout. Run
`python3 tests/hypervisor/check-vmx.py` for the production V control helpers
and ARM no-op ABI under ASan/UBSan. The host fixture checks 7,680 cases,
including every byte-valued failure status, 64-bit operands and VMREAD output
preservation. Only privileged instructions are adapted in the host control
fixture; production x86 assembly is separately cross-compiled and inspected
for immediate CF/ZF capture, operand order, memory barriers and allocation
imports. `--original /path/to/pre-port/vmx.c` also verifies that every VM-entry
instruction byte matches the former global assembly block.

After building an isolated kernel, boot it with:

```
python3 tests/hypervisor/run-vm.py --arch x86_64 --kernel-dir /path/to/kernel
python3 tests/hypervisor/run-vm.py --arch aarch64 --kernel-dir /path/to/kernel
```

The guest reports whether VT-x was available. An absent `/dev/hypervisor`
checks boot integration and native syscalls, without claiming VM-entry
coverage. When available, it creates five VMs, checks all guest GPRs across
IO/HLT exits and closes each session. `--require-vmx` requires that execution
marker; use it on an x86 setup with nested VT-x. The local macOS ARM host's
x86 QEMU TCG setup cannot provide that coverage.
