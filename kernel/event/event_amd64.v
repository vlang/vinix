module event

import proc
import x86.cpu
import x86.cpu.local as cpulocal

@[inline]
fn interrupt_state() bool {
	return cpu.interrupt_state()
}

@[inline]
fn interrupt_toggle(state bool) bool {
	return cpu.interrupt_toggle(state)
}

// A thread leaving for good yields from inside the kernel, so GS has to be
// the kernel's while it does.
fn leave_for_good(current_thread &proc.Thread) {
	mut cpu_local := cpulocal.current()
	cpu.set_gs_base(u64(&cpu_local.cpu_number))
	cpu.set_kernel_gs_base(u64(current_thread))
}
