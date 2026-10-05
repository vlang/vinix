// SPDX-License-Identifier: GPL-2.0-or-later
module table

import errno
import fs
import stat
import usercopy

// Both Linux dirent layouts fit the same bounded record: their header is at
// most 19 bytes, followed by at most 1024 name bytes and an aligned terminator.
// Allocate the scratch slots once per call. V's escape analysis can heap-box
// even a mut Dirent local, leaving a 1536-byte slab allocation per entry.
// These pointers are only consumed synchronously by readdir/copy_to_user.
fn linux_getdents(gpr_state voidptr, fdnum int, dirp u64, count u64, legacy bool) (u64, u64) {
	mut dirent := unsafe { &stat.Dirent(C.vinix_stack_alloc(sizeof(stat.Dirent))) }
	record := unsafe { &u8(C.vinix_stack_alloc(1064)) }
	mut offset := u64(0)
	for {
		unsafe { *dirent = stat.Dirent{} }
		ret, err := fs.syscall_readdir(gpr_state, fdnum, mut dirent)
		if err != 0 {
			return if offset != 0 { offset, u64(0) } else { ret, err }
		}
		if ret == errno.err {
			break
		}
		mut name_len := u64(0)
		for name_len < 1024 && dirent.name[name_len] != 0 {
			name_len++
		}
		reclen := (u64(20) + name_len + 7) & ~u64(7)
		if reclen > count - offset {
			fs.readdir_unread(fdnum)
			if offset == 0 {
				return errno.err, errno.einval
			}
			break
		}
		unsafe {
			C.memset(record, 0, reclen)
			*&u64(record) = dirent.ino
			*&u64(record + 8) = dirent.off
			*&u16(record + 16) = u16(reclen)
			if legacy {
				C.memcpy(record + 18, &dirent.name[0], name_len)
				record[reclen - 1] = dirent.@type
			} else {
				record[18] = dirent.@type
				C.memcpy(record + 19, &dirent.name[0], name_len)
			}
		}
		if !usercopy.user_range(dirp, offset + reclen)
			|| !usercopy.copy_to_user(dirp + offset, record, reclen) {
			return if offset != 0 { offset, u64(0) } else { errno.err, errno.efault }
		}
		offset += reclen
	}
	return offset, 0
}
