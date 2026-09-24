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
	pid     i32
}

struct CapUserData {
mut:
	effective   u32
	permitted   u32
	inheritable u32
}

fn cap_target(local_pid int) &proc.Process {
	if local_pid == 0 {
		return proc.current_thread().process
	}
	pid := proc.kernel_id(local_pid)
	proc.lock_table()
	mut target := proc.process_at(pid)
	proc.unlock_table()
	if target != unsafe { nil } {
		return target
	}
	// capget/capset name a thread, not a thread group: their "pid" is really a
	// tid. A runtime applying its own caps passes gettid(), which is not the
	// group leader's, so resolve it through the thread as well.
	thread := proc.get_thread(pid)
	if thread != unsafe { nil } {
		owner := thread.process
		proc.unpin_thread(thread)
		return owner
	}
	return unsafe { nil }
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
	target := cap_target(int(header.pid))
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
	// capset(2) only ever changes the caller. Its "pid" is a tid, though, and a
	// runtime applying its own caps passes gettid() rather than 0, so accept any
	// thread of this process and refuse only a genuinely different one.
	mut process := proc.current_thread().process
	if header.pid != 0 {
		target := cap_target(int(header.pid))
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
		if voidptr(target) != voidptr(process) {
			return errno.err, errno.eperm
		}
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

const seccomp_set_mode_strict = u32(0)
const seccomp_set_mode_filter = u32(1)
const seccomp_get_action_avail = u32(2)
const seccomp_filter_flag_tsync = u32(1)
const seccomp_filter_flag_log = u32(2)
const seccomp_filter_flag_spec_allow = u32(4)
const seccomp_filter_flag_tsync_esrch = u32(16)

// seccomp(operation, flags, args); see proc/seccomp.v. Programs are the
// process's, so TSYNC holds already. There are no listeners to hand user
// notifications to, so SECCOMP_FILTER_FLAG_NEW_LISTENER, like every flag
// Linux does not know, is refused: libseccomp probes each flag this way and
// leaves out what the kernel refuses.
fn syscall_linux_seccomp(_ voidptr, operation u32, flags u32, args u64) (u64, u64) {
	match operation {
		seccomp_set_mode_strict {
			if flags != 0 || args != 0 {
				return errno.err, errno.einval
			}
			return seccomp_set_strict()
		}
		seccomp_set_mode_filter {
			known := seccomp_filter_flag_tsync | seccomp_filter_flag_log | seccomp_filter_flag_spec_allow | seccomp_filter_flag_tsync_esrch
			if flags & ~known != 0 {
				return errno.err, errno.einval
			}
			return seccomp_install(args)
		}
		seccomp_get_action_avail {
			mut action := u32(0)
			if !usercopy.copy_from_user(voidptr(&action), args, sizeof(u32)) {
				return errno.err, errno.efault
			}
			match action {
				proc.seccomp_ret_kill_process, proc.seccomp_ret_kill_thread, proc.seccomp_ret_trap,
				proc.seccomp_ret_errno, proc.seccomp_ret_trace, proc.seccomp_ret_log,
				proc.seccomp_ret_allow {
					return 0, 0
				}
				else {
					return errno.err, errno.eopnotsupp
				}
			}
		}
		else {
			return errno.err, errno.einval
		}
	}
}

fn seccomp_set_strict() (u64, u64) {
	mut process := proc.current_thread().process
	if process.seccomp_mode != proc.seccomp_mode_disabled {
		return errno.err, errno.einval
	}
	process.seccomp_mode = proc.seccomp_mode_strict
	return 0, 0
}

// Install the program struct sock_fprog at `prog` describes. Only a process
// that cannot gain privileges by exec, or one that holds CAP_SYS_ADMIN, may.
fn seccomp_install(prog u64) (u64, u64) {
	mut process := proc.current_thread().process
	if process.seccomp_mode == proc.seccomp_mode_strict {
		return errno.err, errno.einval
	}
	if !process.no_new_privs && !proc.current_has_capability(proc.cap_sys_admin) {
		return errno.err, errno.eacces
	}
	// struct sock_fprog: an unsigned short length, then the pointer.
	mut header := [2]u64{}
	if !usercopy.copy_from_user(voidptr(&header[0]), prog, 16) {
		return errno.err, errno.efault
	}
	length := int(header[0] & 0xffff)
	if length == 0 || length > proc.bpf_max_instructions {
		return errno.err, errno.einval
	}
	mut instructions := []proc.SockFilter{len: length}
	if !usercopy.copy_from_user(voidptr(&instructions[0]), header[1], u64(length) * sizeof(proc.SockFilter)) {
		unsafe { instructions.free() }
		return errno.err, errno.efault
	}
	if !proc.seccomp_check(instructions) {
		unsafe { instructions.free() }
		return errno.err, errno.einval
	}
	if !proc.seccomp_attach(mut process, instructions) {
		unsafe { instructions.free() }
		return errno.err, errno.enomem
	}
	return 0, 0
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
const pr_get_seccomp = 21
const pr_set_seccomp = 22

fn syscall_container_prctl(gpr_state voidptr, option int, arg2 u64, arg3 u64, arg4 u64, arg5 u64) (u64, u64) {
	mut process := proc.current_thread().process
	match option {
		pr_get_seccomp {
			return u64(process.seccomp_mode), 0
		}
		pr_set_seccomp {
			match int(arg2) {
				proc.seccomp_mode_strict {
					return seccomp_set_strict()
				}
				proc.seccomp_mode_filter {
					return seccomp_install(arg3)
				}
				else {
					return errno.err, errno.einval
				}
			}
		}
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
