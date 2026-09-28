module syscall

import x86.cpu.local as cpulocal
import proc
import syscall.table
import userland

// The x86-64 port predates Vinix's Linux-compatible arm64 ABI, so its native
// libc puts the syscall number in rdi and receives errno in rdx. Alpine uses
// the Linux register convention instead. Keep that choice on the process so
// exec can switch ABIs without breaking the existing amd64 desktop/userland.
@[export: 'syscall_is_linux']
fn syscall_is_linux() u64 {
	return if proc.current_thread().process.linux_abi { u64(1) } else { u64(0) }
}

// Called by syscall_entry on every syscall's way in, with the saved GPR frame.
// Answers which ABI the process speaks and, for a pledged process, 0 or the
// errno pledge(2) refuses the call with. The same pair of registers carries
// both back, as it carries a handler's result and errno.
@[export: 'syscall_enter']
fn syscall_enter(frame &cpulocal.GPRState) (u64, u64) {
	process := proc.current_thread().process
	linux := if process.linux_abi { u64(1) } else { u64(0) }
	if process.pledge == 0 {
		return linux, 0
	}
	return linux, table.pledge_amd64_entry(frame, process.linux_abi)
}

// Called by syscall_entry in asm/x86_64/syscall_entry.S on the way back to
// userspace, with the saved GPR frame.
@[export: 'syscall_leave']
fn leave(context &cpulocal.GPRState) {
	userland.flush_owed_sync()
	// A call that broke a pledge(2) promise has unwound and holds nothing;
	// the process dies here, before it can run another instruction.
	if proc.pledge_violation_pending() {
		userland.exit_on_pledge_violation()
	}
	asm volatile amd64 {
		cli
	}

	userland.dispatch_a_signal(context)
}
