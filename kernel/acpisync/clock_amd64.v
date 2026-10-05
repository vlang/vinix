module acpisync

import x86.hpet as hpet_clock
import klock

@[export: 'vinix_acpi_sync_clock_ns']
pub fn clock_ns() u64 {
	return hpet_clock.nanoseconds()
}

fn spin_hint() {
	klock.spin_hint()
}
