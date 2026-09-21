// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
module table

import errno

// kernel/memory/mmap uses this bit only to account the reserved brk arena
// differently from ordinary mappings. It is never part of either userspace ABI.
const vinix_private_map_brk_reservation = u64(0x20000000)

fn syscall_vinix_mmap_hardened(gpr_state voidptr, addr voidptr, length u64,
	prot_and_flags u64, fdnum int, offset i64) (u64, u64) {
	if prot_and_flags & vinix_private_map_brk_reservation != 0 {
		return errno.err, errno.einval
	}
	return syscall_vinix_mmap_aslr(gpr_state, addr, length, prot_and_flags, fdnum, offset)
}

fn syscall_linux_mmap_hardened(gpr_state voidptr, addr voidptr, length u64, prot int,
	flags int, fdnum int, offset i64) (u64, u64) {
	if u64(u32(flags)) & vinix_private_map_brk_reservation != 0 {
		return errno.err, errno.einval
	}
	return syscall_linux_mmap_aslr(gpr_state, addr, length, prot, flags, fdnum, offset)
}

// Run after the normal and ASLR syscall-table initialization so the final mmap
// entry points enforce the private-flag check while retaining randomized hints.
pub fn init_security_syscalls() {
	syscall_table[1] = voidptr(syscall_vinix_mmap_hardened)
	linux_syscall_table[9] = voidptr(syscall_linux_mmap_hardened)
}
