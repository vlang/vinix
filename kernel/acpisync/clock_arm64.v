module acpisync

import aarch64.timer

@[export: 'vinix_acpi_sync_clock_ns']
pub fn clock_ns() u64 {
	return timer.get_ns()
}

fn spin_hint() {
	asm volatile aarch64 {
		yield
		; ; ; memory
	}
}
