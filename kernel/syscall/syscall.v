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

// The actual SYSCALL entry point is kernel/asm/x86_64/syscall_entry.S, not V
// code -- see that file's own comment for why. It calls back into
// syscall_is_linux() and leave() above by their linker symbol names, which
// V's whole-program compiler cannot see: neither @[export] nor @[markused]
// on either function survived having zero V-visible callers once the only
// call site (formerly V's own inline asm, in the same translation unit)
// moved to a separate .S file -- both were silently absent from the
// generated C entirely, a clean link-time undefined-symbol error rather
// than a runtime surprise, but still a real gap. A global initialised with
// their addresses at declaration time did not fix it either; only
// assigning to it as a real statement inside a function V proves reachable
// from main() did, matching how interrupt_table's own entries are
// populated (a runtime assignment inside sched.initialise(), not the
// array's own initializer) rather than how it looked like it should work
// from that pattern alone.
__global (
	keep_syscall_entry_callees [2]voidptr
)

pub fn pin_syscall_entry_callees() {
	keep_syscall_entry_callees[0] = voidptr(syscall_is_linux)
	keep_syscall_entry_callees[1] = voidptr(leave)
}
