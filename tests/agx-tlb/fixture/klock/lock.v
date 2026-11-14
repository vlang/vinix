module klock

pub struct Lock {
mut:
	held bool
}

pub fn (mut guard Lock) acquire() {
	assert !guard.held, 'recursive lock acquisition'
	guard.held = true
}

pub fn (mut guard Lock) release() {
	assert guard.held, 'unlock without acquisition'
	guard.held = false
}
