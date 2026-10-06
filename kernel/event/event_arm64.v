module event

import aarch64.cpu
import proc

@[inline]
fn interrupt_state() bool {
	return cpu.interrupt_state()
}

// Preserve the existing ARM context contract; native IRQ accounting is separate.
fn wait_context_allowed() bool {
	return cpu.interrupt_state()
}

@[inline]
fn interrupt_toggle(state bool) bool {
	return cpu.interrupt_toggle(state)
}

// A thread leaving for good needs nothing more here: the current thread is
// found through TPIDR_EL1, which proc.set_current_thread keeps.
fn leave_for_good(_ &proc.Thread) {}
