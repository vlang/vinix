// SPDX-License-Identifier: GPL-2.0-or-later
module proc

import errno
import katomic
import memory.mmap

// A Vinix extension: query=0, audit=1, enforce=2, violation-count=3.
// A process may only strengthen its mode until exec installs a new image.
pub const pr_vinix_stack_policy = 0x56490001

pub fn stack_policy_control(mut process Process, action u64, pointer u64) (u64, u64) {
	if action == 0 { return u64(katomic.load(&process.stack_policy_mode)), 0 }
	if action == 3 { return katomic.load(&process.stack_policy_violations), 0 }
	if action > 2 { return errno.err, errno.einval }
	if action == 2 && !mmap.stack_pointer_valid(process.pagemap, pointer) {
		return errno.err, errno.eperm
	}
	for {
		current := katomic.load(&process.stack_policy_mode)
		if action < current { return errno.err, errno.eperm }
		if katomic.cas(mut &process.stack_policy_mode, current, u32(action)) { return 0, 0 }
	}
}

// True permits the call. Audit counts invalid entries without changing the
// Linux ABI; enforce asks the architecture entry hook to terminate the caller.
pub fn syscall_stack_allowed(mut process Process, pointer u64) bool {
	mode := katomic.load(&process.stack_policy_mode)
	if mode == 0 || mmap.stack_pointer_valid(process.pagemap, pointer) { return true }
	katomic.inc(mut &process.stack_policy_violations)
	return mode != 2
}
