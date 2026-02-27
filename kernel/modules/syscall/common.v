module syscall

import aarch64.cpu
import aarch64.cpu.local as cpulocal
import userland

@[markused]
fn leave(context &cpulocal.GPRState) {
	cpu.interrupt_toggle(false)
	userland.dispatch_a_signal(context)
}
