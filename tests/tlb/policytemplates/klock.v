module klock
pub struct Lock { pub mut: held bool }
pub fn (mut l Lock) acquire() { assert !l.held; l.held = true }
pub fn (mut l Lock) release() { assert l.held; l.held = false }
