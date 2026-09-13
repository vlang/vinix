// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

import apple.ans
import file
import pagecache
import proc
import errno
import aarch64.cpu

// Install after the architecture's generic syscall table, so compatibility
// stubs cannot silently override durability or shutdown operations.
pub fn init_storage_syscalls() {
	syscall_table[81] = voidptr(storage_sync)
	syscall_table[82] = voidptr(storage_fsync)
	syscall_table[83] = voidptr(storage_fsync) // fdatasync: stronger full flush
	syscall_table[267] = voidptr(storage_syncfs)
	syscall_table[142] = voidptr(storage_reboot)
}

// Push every cached write to its device. Block-backed filesystems keep dirty
// pages in a shared write-back cache that is otherwise only drained when the
// LRU evicts a page, so skipping this loses small writes across a restart.
// ANS is write-through, but its controller still needs an explicit Flush.
fn storage_flush_everything() bool {
	// Both halves always run: a failing ANS controller must not leave a
	// healthy block device's pages in memory, or the reverse.
	caches_flushed := pagecache.sync_all()
	return ans.flush() && caches_flushed
}

fn storage_sync(_ voidptr) (u64, u64) {
	if !storage_flush_everything() { return errno.err, errno.eio }
	return 0, 0
}

fn storage_fsync(_ voidptr, fdnum int) (u64, u64) {
	// The descriptor's own sync is what folds a shared file mapping back into
	// the inode; a flush driven from the cache registry cannot find those pages.
	// It also performs the EBADF and EINVAL checks fsync(2) owes its caller.
	ret, code := file.syscall_fsync(unsafe { nil }, fdnum)
	if ret != 0 { return ret, code }
	return storage_sync(unsafe { nil })
}

fn storage_syncfs(_ voidptr, fdnum int) (u64, u64) {
	mut fd := file.fd_from_fdnum(proc.current_thread().process, fdnum) or { return errno.err, errno.get() }
	defer { fd.unref() }
	return storage_sync(unsafe { nil })
}

fn storage_reboot(_ voidptr, magic1 u32, magic2 u32, command u32, _arg voidptr) (u64, u64) {
	if magic1 != 0xfee1dead || (magic2 != 0x28121969 && magic2 != 0x05121996
		&& magic2 != 0x16041998 && magic2 != 0x20112000) { return errno.err, errno.einval }
	if command != 0x01234567 && command != 0xcdef0123 && command != 0x4321fedc {
		return errno.err, errno.einval
	}
	// Linux gates this on CAP_SYS_BOOT. Vinix has no credential model, so every
	// process already holds the privilege such a check would look for, and
	// demanding PID 1 instead only made reboot(2) unreachable: on the desktop
	// image init execs the compositor, so nothing a terminal runs is ever pid 1.
	// The magic numbers above remain the guard against a stray call.
	//
	// Nothing restarts a machine with unwritten data. A reset that dropped the
	// page cache is exactly the reboot that loses the file just created, so a
	// failed flush refuses the transition rather than completing it.
	if !pagecache.sync_all() { return errno.err, errno.eio }
	if !ans.shutdown() { return errno.err, errno.eio }
	if command == 0x01234567 {
		cpu.psci_call(cpu.psci_system_reset)
	} else {
		cpu.psci_call(cpu.psci_system_off)
	}
	// A successful power transition does not return. Do not tell init that
	// a failed/unsupported PSCI call powered the machine off.
	return errno.err, errno.eio
}
