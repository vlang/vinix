module syscall

import x86.cpu.local as cpulocal
import proc
import sched
import userland

fn C.vinix_linuxkpi_test_maskable_user_return()

// Called by syscall_entry in asm/x86_64/syscall_entry.S on the way back to
// userspace, with the saved GPR frame, as syscall/common.v's leave() is on
// arm64.
@[export: 'syscall_leave']
fn leave(context &cpulocal.GPRState) {
	if cpulocal.maskable_irq_depth() != 0 {
		panic('x86: syscall return inherited maskable IRQ context')
	}
	$if linuxkpi ? {
		C.vinix_linuxkpi_test_maskable_user_return()
	}
	userland.flush_owed_sync()
	userland.settle_owed_memory()
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
