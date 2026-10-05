// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

// sync(2), fsync(2) and syncfs(2) on both architectures. What there is to
// flush is the architecture's: see storage_flush_everything() in
// storage_arm64.v and storage_amd64.v.

import errno
import file
import proc

fn storage_sync(_ voidptr) (u64, u64) {
	if !storage_flush_everything() { return errno.err, errno.eio }
	return 0, 0
}

fn storage_fsync(_ voidptr, fdnum int) (u64, u64) {
	// The descriptor's own sync is what folds a shared file mapping back into
	// the inode; a flush driven from the cache registry cannot find those pages.
	// It also performs the EBADF and EINVAL checks fsync(2) owes its caller.
	// Each resource owns its backing-store flush. An unrelated disk failure
	// must not turn a successful tmpfs/file sync into an I/O error.
	return file.syscall_fsync(unsafe { nil }, fdnum)
}

fn storage_syncfs(_ voidptr, fdnum int) (u64, u64) {
	mut fd := file.fd_from_fdnum(proc.current_thread().process, fdnum) or { return errno.err, errno.get() }
	defer { fd.unref() }
	return storage_sync(unsafe { nil })
}

