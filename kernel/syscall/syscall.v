module syscall

import x86.cpu.local as cpulocal
import proc
import userland

// Called by syscall_entry in asm/x86_64/syscall_entry.S on the way back to
// userspace, with the saved GPR frame, as syscall/common.v's leave() is on
// arm64.
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
	userland.exit_if_told_to()
	userland.prepare_syscall_restart(context)
	userland.end_wait_mask_unless_interrupted(context.rax)
	userland.dispatch_a_signal(context)
	userland.end_wait_mask()
}

// Called by the interrupt thunks in asm/int_thunks_asm.S on the way back to
// userspace, with the interrupted frame.
@[export: 'interrupt_leave']
fn interrupt_leave(context &cpulocal.GPRState) {
	userland.interrupt_return(context)
}
