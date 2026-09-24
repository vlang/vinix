module syscall

import x86.cpu.local as cpulocal
import proc
import userland

// The x86-64 port predates Vinix's Linux-compatible arm64 ABI, so its native
// libc puts the syscall number in rdi and receives errno in rdx. Alpine uses
// the Linux register convention instead. Keep that choice on the process so
// exec can switch ABIs without breaking the existing amd64 desktop/userland.
@[export: 'syscall_is_linux']
fn syscall_is_linux() u64 {
	return if proc.current_thread().process.linux_abi { u64(1) } else { u64(0) }
}

// Called by syscall_entry in asm/x86_64/syscall_entry.S on the way back to
// userspace, with the saved GPR frame.
@[export: 'syscall_leave']
fn leave(context &cpulocal.GPRState) {
	asm volatile amd64 {
		cli
	}

	userland.dispatch_a_signal(context)
}
