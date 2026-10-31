module klock

pub struct Lock {
pub mut:
	held bool
}

pub fn (mut guard Lock) acquire() {
	assert !guard.held, 'recursive queue lock or inverted lock ordering'
	guard.held = true
}

pub fn (mut guard Lock) release() {
	assert guard.held
	guard.held = false
}

pub fn (mut guard Lock) test_and_acquire() bool {
	if guard.held { return false }
	guard.held = true
	return true
}
