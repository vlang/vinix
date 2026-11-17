// SPDX-License-Identifier: GPL-2.0-or-later
module gem

// The caller owns a reference across this operation. Private objects cannot
// be exported through PRIME. Current contiguous backing stays resident even
// after DONTNEED; advice alone never frees pages or invalidates GPU mappings.
pub fn advise_private(object &GemObject, dontneed bool) ?u32 {
	if object == unsafe { nil } || object.vm_private_identity == 0 || object.external { return none }
	mut owned := unsafe { object }
	owned.lock.acquire()
	defer { owned.lock.release() }
	owned.advice_dontneed = dontneed
	return 1
}
