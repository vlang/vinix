// SPDX-License-Identifier: GPL-2.0-or-later
module vm

// The manager owns one serialized, private pool for the kernel's lifetime.
// Hardware context numbers can be recycled; reservation identities cannot.
pub struct IdentityPool {
pub mut:
	next u64 = 1
}

pub fn (mut pool IdentityPool) allocate() ?u64 {
	if pool.next == 0 { return none }
	identity := pool.next
	pool.next = if identity == ~u64(0) { u64(0) } else { identity + 1 }
	return identity
}
