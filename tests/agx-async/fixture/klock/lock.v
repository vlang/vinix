// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module klock

pub struct Lock {
mut:
	held bool
}

__global next_lock &Lock = unsafe { nil }
__global next_callback fn () = unsafe { nil }
__global release_lock &Lock = unsafe { nil }
__global release_callback fn () = unsafe { nil }

pub fn before_once(target &Lock, callback fn ()) {
	assert next_lock == unsafe { nil } && !target.held
	next_lock = unsafe { target }; next_callback = callback
}

pub fn after_release_once(target &Lock, callback fn ()) {
	assert release_lock == unsafe { nil }
	release_lock = unsafe { target }
	release_callback = callback
}

pub fn (mut guard Lock) acquire() {
	if voidptr(next_lock) == voidptr(&guard) {
		callback := next_callback
		next_lock = unsafe { nil }; next_callback = unsafe { nil }
		callback()
	}
	assert !guard.held, 'recursive lock acquisition'
	guard.held = true
}

pub fn (mut guard Lock) release() {
	assert guard.held, 'unlock without acquisition'
	guard.held = false
	if voidptr(release_lock) == voidptr(&guard) {
		callback := release_callback
		release_lock = unsafe { nil }
		release_callback = unsafe { nil }
		callback()
	}
}

pub fn (guard &Lock) is_held() bool { return guard.held }
