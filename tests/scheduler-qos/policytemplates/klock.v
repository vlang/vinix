module klock
pub struct Lock { pub mut: busy bool }
pub fn (mut l Lock) acquire() { assert !l.busy; l.busy = true }
pub fn (mut l Lock) release() { assert l.busy; l.busy = false }
pub fn (mut l Lock) test_and_acquire() bool { if l.busy { return false }; l.busy = true; return true }
