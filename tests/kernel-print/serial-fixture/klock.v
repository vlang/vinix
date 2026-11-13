@[has_globals]
module klock

#include <assert.h>
fn C.assert(bool)

pub struct Lock {
mut:
	held bool
}

pub fn (mut this Lock) acquire() {
	C.assert(!this.held)
	this.held = true
}

pub fn (mut this Lock) release() {
	C.assert(this.held)
	this.held = false
}
