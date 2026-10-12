// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import katomic

// Linux 6.12's four behavior/lock pairs. These belong to the calling task,
// independently of the process-wide capability sets currently kept by Vinix.
pub const secbit_noroot = u32(1)
pub const secbit_no_setuid_fixup = u32(4)
pub const secbit_keep_caps = u32(16)
pub const secbit_keep_caps_locked = u32(32)
pub const secbit_no_cap_ambient_raise = u32(64)
const secure_all = u32(255)
const secure_locks = u32(170)

// Borrowed from the running caller, a constructor source, or a pinned task.
pub fn securebits_state(task &Thread) u32 {
	if task == unsafe { nil } { return 0 }
	return katomic.load(&task.securebits)
}

// Only the owning task changes these flags; there is no cross-task setter.
pub fn set_securebits(value u64) bool {
	if value & ~u64(secure_all) != 0 || !current_has_capability(cap_setpcap) { return false }
	mut task := current_thread()
	old := securebits_state(task)
	locks := old & secure_locks
	if ((locks >> 1) & (old ^ u32(value))) != 0 || (locks & ~u32(value)) != 0 { return false }
	katomic.store(mut &task.securebits, u32(value))
	return true
}

// Value validation precedes the lock check in the syscall handler.
pub fn set_keepcaps(value bool) bool {
	mut task := current_thread()
	old := securebits_state(task)
	if old & secbit_keep_caps_locked != 0 { return false }
	katomic.store(mut &task.securebits, (old & ~secbit_keep_caps) | if value { secbit_keep_caps } else { u32(0) })
	return true
}

pub fn securebits_after_exec() {
	mut task := current_thread()
	// Exec clears KEEP_CAPS even when locked; its lock and every other bit stay.
	katomic.store(mut &task.securebits, securebits_state(task) & ~secbit_keep_caps)
}
