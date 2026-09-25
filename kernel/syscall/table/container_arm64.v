// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module table

import fs

// Install after the generic and storage tables.
pub fn init_container_syscalls() {
	syscall_table[33] = voidptr(fs.syscall_mknodat) // __NR_mknodat
	syscall_table[41] = voidptr(fs.syscall_pivot_root) // __NR_pivot_root
	syscall_table[51] = voidptr(fs.syscall_chroot) // __NR_chroot
	syscall_table[90] = voidptr(syscall_linux_capget) // __NR_capget
	syscall_table[91] = voidptr(syscall_linux_capset) // __NR_capset
	syscall_table[97] = voidptr(fs.syscall_unshare) // __NR_unshare
	syscall_table[167] = voidptr(syscall_container_prctl) // __NR_prctl (extended)
	syscall_table[268] = voidptr(fs.syscall_setns) // __NR_setns
	syscall_table[277] = voidptr(syscall_linux_seccomp) // __NR_seccomp
}
