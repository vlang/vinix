// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import proc
import resource
import usercopy

fn storage_health(mut descriptor file.FD, argument voidptr) ?int {
	access := descriptor.handle.flags & resource.o_accmode
	if access != resource.o_rdonly && access != resource.o_rdwr {
		errno.set(errno.ebadf)
		return none
	}
	descriptor.handle.mac_check(proc.mac_read)?
	// The driver touches only kernel memory. A user fault can reenter disk
	// I/O, so copy the completed report after the driver releases its lock.
	snapshot := resource.block_health(mut descriptor.handle.resource)?
	if !usercopy.copy_to_user(u64(argument), unsafe { &snapshot }, sizeof(snapshot)) {
		errno.set(errno.efault)
		return none
	}
	return 0
}
