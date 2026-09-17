// SPDX-License-Identifier: GPL-2.0-or-later
module table

import file
import memory.mmap

fn mmap_aslr_eligible(addr voidptr, flags u32) bool {
	return addr == unsafe { nil }
		&& flags & u32(mmap.map_fixed | mmap.map_fixed_noreplace) == 0
}

fn syscall_vinix_mmap_aslr(gpr_state voidptr, addr voidptr, length u64,
	prot_and_flags u64, fdnum int, offset i64) (u64, u64) {
	flags := u32(prot_and_flags & u64(0xffffffff))
	mut hint := addr
	if mmap_aslr_eligible(addr, flags) {
		hint = randomized_mmap_hint(length)
	}
	return file.syscall_mmap(gpr_state, hint, length, prot_and_flags, fdnum, offset)
}

fn syscall_linux_mmap_aslr(gpr_state voidptr, addr voidptr, length u64, prot int,
	flags int, fdnum int, offset i64) (u64, u64) {
	mut hint := addr
	if mmap_aslr_eligible(addr, u32(flags)) {
		hint = randomized_mmap_hint(length)
	}
	packed := (u64(u32(prot)) << 32) | u64(u32(flags))
	return file.syscall_mmap(gpr_state, hint, length, packed, fdnum, offset)
}

// Install last so the Linux-compat table cannot overwrite the hardened mmap
// entry after the native table has selected it.
pub fn init_mmap_aslr_syscalls() {
	syscall_table[1] = voidptr(syscall_vinix_mmap_aslr)
	linux_syscall_table[9] = voidptr(syscall_linux_mmap_aslr)
}
