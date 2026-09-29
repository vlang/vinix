module syscall

import x86.cpu.local as cpulocal
import proc
import userland

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
