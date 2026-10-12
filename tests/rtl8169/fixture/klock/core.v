module klock

pub struct Lock {
mut:
	held bool
}

pub fn (mut l Lock) acquire() {
	assert !l.held
	l.held = true
}

pub fn (mut l Lock) release() {
	assert l.held
	l.held = false
}

pub fn (mut l Lock) test_and_acquire() bool {
	if l.held { return false }
	l.held = true
	return true
}
