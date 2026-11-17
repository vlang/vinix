module klock

pub struct Lock { mut: held bool }
pub fn (mut guard Lock) acquire() { assert !guard.held; guard.held = true }
pub fn (mut guard Lock) release() { assert guard.held; guard.held = false }
pub fn (guard &Lock) is_held() bool { return guard.held }
