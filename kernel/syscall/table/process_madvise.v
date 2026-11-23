// SPDX-License-Identifier: GPL-2.0-or-later
module table

import errno
import file
import memory
import memory.mmap
import proc
import resource

fn syscall_linux_process_madvise(_ voidptr, pidfd i32, iov u64, count u64, advice i32,
	flags u32) (u64, u64) {
	if flags != 0 || count > linux_iov_max {
		return errno.err, errno.einval
	}
	fast := C.vinix_stack_alloc(linux_iov_fast * sizeof(LinuxIOVec))
	vector := import_linux_iov(iov, int(count), fast) or { return errno.err, errno.get() }
	defer { vector.release() }
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(pidfd)) or { return errno.err, errno.ebadf }
	defer { fd.unref() }
	if fd.handle.flags & resource.o_path != 0 {
		return errno.err, errno.ebadf
	}
	mut res := fd.handle.resource
	if mut res !is proc.PidFile {
		return errno.err, errno.ebadf
	}
	mut pagemap := proc.pin_advice_pagemap(res, mmap.is_process_advice(int(advice))) or {
		return errno.err, errno.get()
	}
	defer { memory.release_inspection(pagemap) }
	mut advised := u64(0)
	for i in 0 .. int(count) {
		if advised == vector.total { break }
		entry := unsafe { vector.data[i] }
		// After the first segment, advancing a Linux iterator skips empty
		// entries. Each completed segment contributes its original byte count.
		if i > 0 && entry.len == 0 { continue }
		mmap.process_advise_range(mut pagemap, entry.base, entry.len, int(advice)) or {
			if advised != 0 { return advised, 0 }
			return errno.err, errno.get()
		}
		advised += entry.len
	}
	return advised, 0
}
