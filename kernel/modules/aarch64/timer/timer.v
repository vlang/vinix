@[has_globals]
module timer

// ARM Generic Timer for AArch64
// Uses CNTV (Virtual Timer) which works under both bare-metal and HVF.
// CNTFRQ_EL0 provides frequency, CNTV_TVAL_EL0 for oneshot countdown,
// CNTVCT_EL0 for monotonic counter.
// The virtual timer interrupt is PPI 27 (INTID 27).

import aarch64.cpu

__global (
	timer_freq = u64(0) // Hz (typically 24000000 on M1, varies on QEMU)
)

pub fn initialise() {
	timer_freq = cpu.read_cntfrq_el0()
	println('timer: ARM Generic Timer frequency: ${timer_freq} Hz')

	// Disable timer initially
	stop()
}

// Start a oneshot timer that fires after `us` microseconds
pub fn oneshot(us u64) {
	ticks := us * timer_freq / 1000000

	// Set the timer countdown value
	cpu.write_cntv_tval_el0(ticks)

	// Enable timer, unmask interrupt (ENABLE=1, IMASK=0)
	cpu.write_cntv_ctl_el0(1)
}

// Stop the timer
pub fn stop() {
	// Disable timer (ENABLE=0, IMASK=1)
	cpu.write_cntv_ctl_el0(0x2)
}

// Get current counter value (monotonic, never resets)
pub fn get_count() u64 {
	return cpu.read_cntpct_el0()
}

// Get current time in nanoseconds
pub fn get_ns() u64 {
	count := get_count()
	// Avoid overflow: split the calculation
	secs := count / timer_freq
	frac := count % timer_freq
	return secs * 1000000000 + frac * 1000000000 / timer_freq
}

// Get current time in microseconds
pub fn get_us() u64 {
	count := get_count()
	return count * 1000000 / timer_freq
}

// Sleep for approximately `us` microseconds (busy wait)
pub fn busywait_us(us u64) {
	target := get_count() + us * timer_freq / 1000000
	for get_count() < target {
		asm volatile aarch64 {
			yield
			; ; ; memory
		}
	}
}

// Check if timer interrupt is pending
pub fn is_pending() bool {
	ctl := cpu.read_cntv_ctl_el0()
	// ISTATUS (bit 2) indicates interrupt pending
	return ctl & (1 << 2) != 0
}
