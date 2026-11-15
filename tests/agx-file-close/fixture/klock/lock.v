// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module klock

pub struct Lock {
mut:
	held bool
}

__global waiting &Lock = unsafe { nil }
__global release_wait fn () = unsafe { nil }

// Inject completion of a shutdown that owns this exact manager lock. Other
// file/list lock acquisitions must not consume the injection.
pub fn wait_once(target &Lock, release fn ()) {
	assert waiting == unsafe { nil } && target.held
	waiting = unsafe { target }
	release_wait = release
}

pub fn before_once(target &Lock, callback fn ()) {
	assert waiting == unsafe { nil } && !target.held
	waiting = unsafe { target }
	release_wait = callback
}

pub fn (mut guard Lock) acquire() {
	if voidptr(waiting) == voidptr(&guard) {
		callback := release_wait
		waiting = unsafe { nil }
		release_wait = unsafe { nil }
		callback()
	}
	assert !guard.held, 'recursive lock acquisition'
	guard.held = true
}

pub fn (mut guard Lock) release() {
	assert guard.held, 'unlock without acquisition'
	guard.held = false
}

pub fn (guard &Lock) is_held() bool { return guard.held }
