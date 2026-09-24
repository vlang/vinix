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
