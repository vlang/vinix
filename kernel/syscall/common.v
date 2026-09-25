module syscall

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import sched
import userland

@[markused]
fn leave(context &cpulocal.GPRState) {
	cpu.interrupt_toggle(false)
	userland.exit_if_told_to()
	userland.prepare_syscall_restart(context)
	// Before a signal is dispatched, so one that arrived while the thread
	// waited is delivered once its group may run again.
	sched.park_for_cgroup()
	userland.dispatch_a_signal(context)
}

// On the way back to userspace from an interrupt. A thread that only computes
// makes no syscall, and took no signal but a fatal one: a SIGALRM that
// openssl speed times each run with, or the SIGURG Go preempts a busy
// goroutine with, waited for good. It is delivered here as at a syscall's
// end, its handler run on a frame that keeps the FP/SIMD registers the loop
// had live.
//
// A thread its process has told to exit leaves here too, as it does at a
// syscall's end. One that only computed made no syscall to leave at: the
// sibling tearing the process down waited half a second for it, then
// stopped it where it was and left its kernel stack allocated for good.
@[export: 'interrupt__leave']
fn interrupt_leave(context &cpulocal.GPRState) {
	if context.pstate & 0xf != 0 {
		return
	}
	told_to_exit := userland.told_to_exit()
	if !told_to_exit && !userland.async_signal_deliverable() {
		return
	}
	cpu.interrupt_toggle(false)
	if told_to_exit {
		userland.exit_if_told_to()
	}
	userland.dispatch_a_signal(context)
}
