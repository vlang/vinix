module syscall

import x86.cpu.local as cpulocal
import proc
import sched
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
	// Before a signal is dispatched, so one that arrived while the thread
	// waited is delivered once its group may run again.
	sched.park_for_cgroup()
	userland.dispatch_a_signal(context)
	userland.end_wait_mask()
	proc.cpu_leave_kernel()
}

// Called by the interrupt thunks in asm/int_thunks_asm.S on the way back to
// userspace, with the interrupted frame.
@[export: 'interrupt_leave']
fn interrupt_leave(context &cpulocal.GPRState) {
	userland.interrupt_return(proc.current_thread(), context)
	if context.cs & 3 == 3 { proc.cpu_leave_kernel() }
}

@[export: 'interrupt_enter']
fn interrupt_enter(context &cpulocal.GPRState) {
	if context.cs & 3 == 3 { proc.cpu_enter_kernel() }
}

// Called by syscall32_entry in asm/x86_64/segment.S for SYSCALL made from
// 32-bit code, which has no way back: the program dies of SIGILL.
@[export: 'syscall32_refused']
fn syscall32_refused(_ &cpulocal.GPRState) {
	userland.exit_with_fatal_signal(u8(userland.sigill))
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
