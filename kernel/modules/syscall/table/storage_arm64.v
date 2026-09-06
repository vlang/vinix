// SPDX-License-Identifier: GPL-2.0-or-later
module table

import apple.ans
import file
import resource
import proc
import stat
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

fn storage_sync(_ voidptr) (u64, u64) {
	if !ans.flush() { return errno.err, errno.eio }
	return 0, 0
}

fn storage_fsync(_ voidptr, fdnum int) (u64, u64) {
	mut fd := file.fd_from_fdnum(proc.current_thread().process, fdnum) or { return errno.err, errno.get() }
	defer { fd.unref() }
	if fd.handle.flags & resource.o_path != 0 { return errno.err, errno.ebadf }
	mode := fd.handle.resource.stat.mode
	if !stat.isreg(mode) && !stat.isdir(mode) && !stat.isblk(mode) { return errno.err, errno.einval }
	// ANS is write-through; tmpfs has no persistent writeback. Flush all ANS
	// namespaces rather than inventing an unimplemented per-filesystem cache.
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
	// Vinix's Process has no credential/capability model yet. Restrict this
	// path to init (PID 1), rather than pretending every caller has CAP_SYS_BOOT.
	if proc.current_thread().process.pid != 1 { return errno.err, errno.eperm }
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
