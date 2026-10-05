// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

import pagecache

// Push every cached write to its device. Block-backed filesystems keep dirty
// pages in a shared write-back cache that is otherwise only drained when the
// LRU evicts a page, so skipping this loses small writes across a restart.
fn storage_flush_everything() bool {
	return pagecache.sync_all()
}

// Install after the generic syscall table, as arm64's init_storage_syscalls()
// is: sync(2) and its relatives flush the page cache, as arm64's do.
pub fn init_storage_syscalls() {
	syscall_table[74] = voidptr(storage_fsync) // fsync
	syscall_table[75] = voidptr(storage_fsync) // fdatasync: stronger full flush
	syscall_table[162] = voidptr(storage_sync) // sync
	syscall_table[306] = voidptr(storage_syncfs) // syncfs
}
