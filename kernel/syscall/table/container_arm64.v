// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The syscalls a container runtime reaches for beyond the file and process
// surface: capabilities, seccomp, the namespace calls, chroot/pivot_root and
// mknod. Registered after the generic table so a stub cannot shadow them.
@[has_globals]
module table

import errno
import fs
import proc
import usercopy

// capget/capset data layout. Version 3 splits each 64-bit set into two 32-bit
// words, low then high, across two struct entries.
const linux_capability_version_3 = u32(0x20080522)
const linux_capability_version_1 = u32(0x19980330)
const linux_capability_version_2 = u32(0x20071026)

struct CapUserHeader {
mut:
	version u32
	pid     int
}

struct CapUserData {
mut:
	effective   u32
	permitted   u32
	inheritable u32
}

fn cap_target(pid int) &proc.Process {
	if pid == 0 {
		return proc.current_thread().process
	}
	proc.lock_table()
	defer { proc.unlock_table() }
	return proc.process_at(pid)
}

fn syscall_linux_capget(_ voidptr, header_ptr u64, data_ptr u64) (u64, u64) {
	mut header := CapUserHeader{}
	if !usercopy.copy_from_user(voidptr(&header), header_ptr, sizeof(CapUserHeader)) {
		return errno.err, errno.efault
	}
	entries := if header.version == linux_capability_version_1 { 1 } else { 2 }
	// A probe with a zero pid and null data asks which version we speak.
	if header.version != linux_capability_version_1 && header.version != linux_capability_version_2
		&& header.version != linux_capability_version_3 {
		header.version = linux_capability_version_3
		usercopy.copy_to_user(header_ptr, voidptr(&header), sizeof(CapUserHeader))
		return errno.err, errno.einval
	}
	if header.pid < 0 {
		return errno.err, errno.einval
	}
	if data_ptr == 0 {
		return 0, 0
	}
	target := cap_target(header.pid)
	if target == unsafe { nil } {
		return errno.err, errno.esrch
	}
	caps := target.caps
	mut data := [2]CapUserData{}
	data[0] = CapUserData{
		effective:   u32(caps.effective)
		permitted:   u32(caps.permitted)
		inheritable: u32(caps.inheritable)
	}
	data[1] = CapUserData{
		effective:   u32(caps.effective >> 32)
		permitted:   u32(caps.permitted >> 32)
		inheritable: u32(caps.inheritable >> 32)
	}
	if !usercopy.copy_to_user(data_ptr, voidptr(&data[0]), u64(entries) * sizeof(CapUserData)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn syscall_linux_capset(_ voidptr, header_ptr u64, data_ptr u64) (u64, u64) {
	mut header := CapUserHeader{}
	if !usercopy.copy_from_user(voidptr(&header), header_ptr, sizeof(CapUserHeader)) {
		return errno.err, errno.efault
	}
	entries := if header.version == linux_capability_version_1 { 1 } else { 2 }
	if header.version != linux_capability_version_1 && header.version != linux_capability_version_2
		&& header.version != linux_capability_version_3 {
		return errno.err, errno.einval
	}
	// capset(2) only ever changes the caller, or a single-threaded process
	// that is the caller. A non-zero pid naming another process is refused.
	mut process := proc.current_thread().process
	if header.pid != 0 && header.pid != process.pid {
		return errno.err, errno.eperm
	}
	mut data := [2]CapUserData{}
	if !usercopy.copy_from_user(voidptr(&data[0]), data_ptr, u64(entries) * sizeof(CapUserData)) {
		return errno.err, errno.efault
	}
	mut effective := u64(data[0].effective)
	mut permitted := u64(data[0].permitted)
	mut inheritable := u64(data[0].inheritable)
	if entries == 2 {
		effective |= u64(data[1].effective) << 32
		permitted |= u64(data[1].permitted) << 32
		inheritable |= u64(data[1].inheritable) << 32
	}
	mut caps := process.caps
	// The rules Linux enforces: no capability may be added to permitted that
	// was not already there, effective must stay within permitted, and
	// inheritable may not exceed permitted plus the bounding set. Root already
	// holds every capability, so a runtime dropping some always satisfies them.
	if permitted & ~caps.permitted != 0 {
		return errno.err, errno.eperm
	}
	if effective & ~permitted != 0 {
		return errno.err, errno.eperm
	}
	if inheritable & ~(caps.inheritable | caps.permitted) != 0 {
		return errno.err, errno.eperm
	}
	caps.effective = effective
	caps.permitted = permitted
	caps.inheritable = inheritable
	process.caps = caps
	return 0, 0
}

// seccomp(operation, flags, args). Vinix does not filter syscalls, so a filter
// is accepted and does nothing; a runtime that sets one still runs, it is just
// not confined by it. SECCOMP_GET_ACTION_AVAIL answers that an action is known.
fn syscall_linux_seccomp(_ voidptr, operation u32, flags u32, _args u64) (u64, u64) {
	match operation {
		0, 1 {
			// SECCOMP_SET_MODE_STRICT and SECCOMP_SET_MODE_FILTER. A new-listener
			// filter expects a descriptor back, which we cannot supply.
			if flags & 0x8 != 0 { // SECCOMP_FILTER_FLAG_NEW_LISTENER
				return errno.err, errno.enosys
			}
			mut process := proc.current_thread().process
			process.no_new_privs = true
			return 0, 0
		}
		2 {
			// SECCOMP_GET_ACTION_AVAIL: the action is in *args; report it known.
			return 0, 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

// The extra prctl operations a container runtime uses. Anything else falls
// through to the base handler.
const pr_capbset_read = 23
const pr_capbset_drop = 24
const pr_set_securebits = 28
const pr_get_securebits = 27
const pr_set_keepcaps = 8
const pr_get_keepcaps = 7
const pr_cap_ambient = 47
const pr_set_child_subreaper = 36
const pr_get_child_subreaper = 37

fn syscall_container_prctl(gpr_state voidptr, option int, arg2 u64, arg3 u64, arg4 u64, arg5 u64) (u64, u64) {
	mut process := proc.current_thread().process
	match option {
		pr_capbset_read {
			if arg2 > u64(proc.cap_last_cap) {
				return errno.err, errno.einval
			}
			return if process.caps.bounding & (u64(1) << arg2) != 0 { u64(1) } else { u64(0) }, 0
		}
		pr_capbset_drop {
			if arg2 > u64(proc.cap_last_cap) {
				return errno.err, errno.einval
			}
			if !proc.has_capability(process, proc.cap_setpcap) {
				return errno.err, errno.eperm
			}
			process.caps.bounding &= ~(u64(1) << arg2)
			return 0, 0
		}
		pr_set_keepcaps {
			process.caps.keep = arg2 != 0
			return 0, 0
		}
		pr_get_keepcaps {
			return if process.caps.keep { u64(1) } else { u64(0) }, 0
		}
		pr_cap_ambient {
			// arg2: 1 raise, 2 lower, 3 is_set, 4 clear_all.
			match arg2 {
				4 {
					process.caps.ambient = 0
					return 0, 0
				}
				1, 2 {
					if arg3 > u64(proc.cap_last_cap) {
						return errno.err, errno.einval
					}
					bit := u64(1) << arg3
					if arg2 == 1 {
						if process.caps.permitted & bit == 0 || process.caps.inheritable & bit == 0 {
							return errno.err, errno.eperm
						}
						process.caps.ambient |= bit
					} else {
						process.caps.ambient &= ~bit
					}
					return 0, 0
				}
				3 {
					if arg3 > u64(proc.cap_last_cap) {
						return errno.err, errno.einval
					}
					return if process.caps.ambient & (u64(1) << arg3) != 0 {
						u64(1)
					} else {
						u64(0)
					}, 0
				}
				else {
					return errno.err, errno.einval
				}
			}
		}
		pr_set_securebits {
			return 0, 0
		}
		pr_get_securebits {
			return 0, 0
		}
		pr_set_child_subreaper {
			process.child_subreaper = arg2 != 0
			return 0, 0
		}
		pr_get_child_subreaper {
			value := i32(if process.child_subreaper { 1 } else { 0 })
			if !usercopy.copy_to_user(arg2, voidptr(&value), sizeof(i32)) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		else {
			return syscall_linux_prctl(gpr_state, option, arg2, arg3, arg4, arg5)
		}
	}
}

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
