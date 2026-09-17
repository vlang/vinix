// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import file
import resource
import usercopy

const user_io_chunk = u64(4096)

// Backends consume kernel buffers only. The syscall boundary is responsible for
// moving bytes across the privilege boundary with checked usercopy, which is
// the prerequisite for enabling SMAP/PAN without teaching every filesystem,
// pipe, socket and device driver how to toggle supervisor user access.
pub fn syscall_read_checked(_ voidptr, fdnum int, user_buf voidptr, count u64) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
		return errno.err, errno.get()
	}
	defer { fd.unref() }

	access := fd.handle.flags & resource.o_accmode
	if access != resource.o_rdonly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	if count == 0 {
		return 0, 0
	}
	if user_buf == unsafe { nil } {
		return errno.err, errno.efault
	}

	mut bounce := [4096]u8{}
	mut total := u64(0)
	for total < count {
		mut wanted := count - total
		if wanted > user_io_chunk {
			wanted = user_io_chunk
		}
		ret := fd.handle.read(voidptr(&bounce[0]), wanted) or {
			if total != 0 {
				return total, 0
			}
			return errno.err, errno.get()
		}
		if ret < 0 || u64(ret) > wanted {
			if total != 0 {
				return total, 0
			}
			return errno.err, errno.eio
		}
		if ret == 0 {
			break
		}
		amount := u64(ret)
		if !usercopy.copy_to_user(u64(user_buf) + total, voidptr(&bounce[0]), amount) {
			if total != 0 {
				return total, 0
			}
			return errno.err, errno.efault
		}
		total += amount
		if amount < wanted {
			break
		}
	}

	if total != 0 && fd.handle.node != unsafe { nil } {
		inotify_emit(unsafe { &VFSNode(fd.handle.node) }, '', in_access, 0)
	}
	return total, 0
}

pub fn syscall_write_checked(_ voidptr, fdnum int, user_buf voidptr, count u64) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
		return errno.err, errno.get()
	}
	defer { fd.unref() }

	access := fd.handle.flags & resource.o_accmode
	if access != resource.o_wronly && access != resource.o_rdwr {
		return errno.err, errno.ebadf
	}
	if count == 0 {
		return 0, 0
	}
	if user_buf == unsafe { nil } {
		return errno.err, errno.efault
	}

	mut bounce := [4096]u8{}
	mut total := u64(0)
	for total < count {
		mut wanted := count - total
		if wanted > user_io_chunk {
			wanted = user_io_chunk
		}
		if !usercopy.copy_from_user(voidptr(&bounce[0]), u64(user_buf) + total, wanted) {
			if total != 0 {
				return total, 0
			}
			return errno.err, errno.efault
		}
		ret := fd.handle.write(voidptr(&bounce[0]), wanted) or {
			if total != 0 {
				return total, 0
			}
			return errno.err, errno.get()
		}
		if ret < 0 || u64(ret) > wanted {
			if total != 0 {
				return total, 0
			}
			return errno.err, errno.eio
		}
		if ret == 0 {
			break
		}
		amount := u64(ret)
		total += amount
		if amount < wanted {
			break
		}
	}

	if total != 0 && fd.handle.node != unsafe { nil } {
		inotify_emit(unsafe { &VFSNode(fd.handle.node) }, '', in_modify, 0)
	}
	return total, 0
}
