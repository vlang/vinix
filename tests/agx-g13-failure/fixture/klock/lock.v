@[has_globals]
module klock

pub struct Lock {
mut:
	held bool
pub mut:
	ints bool
}

__global acquire_target = unsafe { &Lock(nil) }
__global release_target = unsafe { &Lock(nil) }
__global before_acquire fn () = unsafe { nil }
__global after_release fn () = unsafe { nil }
__global simulated_interrupts_enabled = true

pub fn interrupt_state() bool { return simulated_interrupts_enabled }
pub fn set_interrupt_state(enabled bool) { simulated_interrupts_enabled = enabled }

pub fn on_next_acquire(target &Lock, callback fn ()) {
	acquire_target = unsafe { target }
	before_acquire = callback
}

pub fn on_next_release(target &Lock, callback fn ()) {
	release_target = unsafe { target }
	after_release = callback
}

pub fn (guard &Lock) is_held() bool { return guard.held }

pub fn (mut guard Lock) acquire() {
	if guard == acquire_target && before_acquire != unsafe { nil } {
		callback := before_acquire
		acquire_target = unsafe { nil }
		before_acquire = unsafe { nil }
		callback()
	}
	assert !guard.held, 'recursive lock acquisition'
	guard.ints = interrupt_state()
	set_interrupt_state(false)
	guard.held = true
}

pub fn (mut guard Lock) release() {
	assert guard.held, 'unlock without acquisition'
	guard.held = false
	set_interrupt_state(guard.ints)
	if guard == release_target && after_release != unsafe { nil } {
		callback := after_release
		release_target = unsafe { nil }
		after_release = unsafe { nil }
		callback()
	}
}
