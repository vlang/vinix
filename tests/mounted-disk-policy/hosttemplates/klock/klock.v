module klock
fn C.host_lock(voidptr)
fn C.host_unlock(voidptr)
pub struct Lock {
pub mut:
 cell bool
}
pub fn (mut guard Lock) acquire() { C.host_lock(&guard.cell) }
pub fn (mut guard Lock) release() { C.host_unlock(&guard.cell) }
