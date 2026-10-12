// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The syscalls a container runtime reaches for beyond the file and process
// surface: capabilities, seccomp, the namespace calls, chroot/pivot_root and
// mknod. Each architecture registers them after its generic table so a stub
// cannot shadow them.
@[has_globals]
module table

import errno
import memory
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

// Validate only the version word. Null-data capget probes do not read pid;
// an unsupported version writes back the preferred word before any pid/data
// access, and a failed write must return EFAULT instead of EINVAL.
fn cap_words(header_ptr u64) (int, u64) {
	mut version := u32(0)
	if !usercopy.copy_from_user(voidptr(unsafe { &version }), header_ptr, sizeof(u32)) {
		return 0, errno.efault
	}
	match version {
		linux_capability_version_1 { return 1, 0 }
		linux_capability_version_2, linux_capability_version_3 { return 2, 0 }
		else {
			version = linux_capability_version_3
			if !usercopy.copy_to_user(header_ptr, voidptr(unsafe { &version }), sizeof(u32)) {
				return 0, errno.efault
			}
			return 0, errno.einval
		}
	}
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
	// capget names a thread, not only a thread group. Resolve a nonleader's
	// tid to its process for the currently process-wide capability sets.
	thr := proc.get_thread(pid)
	if thr != unsafe { nil } {
		owner := thr.process
		proc.unpin_thread(thr)
		return owner
	}
	return unsafe { nil }
}

fn syscall_linux_capget(_ voidptr, header_ptr u64, data_ptr u64) (u64, u64) {
	entries, format_error := cap_words(header_ptr)
	if data_ptr == 0 {
		if format_error == 0 || format_error == errno.einval { return 0, 0 }
		return errno.err, format_error
	}
	if format_error != 0 { return errno.err, format_error }
	mut pid := i32(0)
	if !usercopy.copy_from_user(voidptr(unsafe { &pid }), header_ptr + sizeof(u32), sizeof(i32)) {
		return errno.err, errno.efault
	}
	if pid < 0 { return errno.err, errno.einval }
	target := cap_target(int(pid))
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
	entries, format_error := cap_words(header_ptr)
	if format_error != 0 { return errno.err, format_error }
	mut pid := i32(0)
	if !usercopy.copy_from_user(voidptr(unsafe { &pid }), header_ptr + sizeof(u32), sizeof(i32)) {
		return errno.err, errno.efault
	}
	// capset only names the caller: zero or its namespace-visible tid.
	// Reject every other pid before reading data, without a target lookup.
	caller := proc.current_thread()
	mut process := caller.process
	if pid != 0 && int(pid) != proc.own_tid(caller) {
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
	// Linux ignores reserved capability bits outside its advertised set.
	effective &= proc.cap_all
	permitted &= proc.cap_all
	inheritable &= proc.cap_all
	mut caps := process.caps
	// New inheritable bits must be bounded unless already inherited. Without
	// effective CAP_SETPCAP they must also come from the old permitted set.
	// Authorization uses the caller's old effective set, not the proposed one.
	if inheritable & ~(caps.inheritable | caps.bounding) != 0 {
		return errno.err, errno.eperm
	}
	if !proc.has_capability(process, proc.cap_setpcap)
		&& inheritable & ~(caps.inheritable | caps.permitted) != 0 {
		return errno.err, errno.eperm
	}
	// Permitted cannot grow and effective must remain within new permitted.
	if permitted & ~caps.permitted != 0 {
		return errno.err, errno.eperm
	}
	if effective & ~permitted != 0 {
		return errno.err, errno.eperm
	}
	caps.effective = effective
	caps.permitted = permitted
	caps.inheritable = inheritable
	// Ambient privileges must always be a subset of both sets. Otherwise
	// dropping a capability here can silently regain it on the next exec.
	caps.ambient &= permitted & inheritable
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

// seccomp(operation, flags, args); see proc/seccomp.v. There are no listeners to hand user
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
			return seccomp_install(args, flags)
		}
		seccomp_get_action_avail {
			if flags != 0 {
				return errno.err, errno.einval
			}
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
	return proc.seccomp_set_strict()
}

// Install the program struct sock_fprog at `prog` describes. Only a task
// that cannot gain privileges by exec, or one that holds CAP_SYS_ADMIN, may.
fn seccomp_install(prog u64, flags u32) (u64, u64) {
	// struct sock_fprog: an unsigned short length, then the pointer.
	mut header := [2]u64{}
	if !usercopy.copy_from_user(voidptr(&header[0]), prog, 16) {
		return errno.err, errno.efault
	}
	length := int(header[0] & 0xffff)
	if length == 0 || length > proc.bpf_max_instructions {
		return errno.err, errno.einval
	}
	// Linux reads the header and validates its length before authorization;
	// only authorized tasks may reach instruction copying and verification.
	if proc.no_new_privs_state(proc.current_thread()) == 0 && !proc.current_has_capability(proc.cap_sys_admin) {
		return errno.err, errno.eacces
	}
	// A user-requested buffer must not use V's panic-on-OOM constructor.
	// Empty construction allocates nothing; the raw allocation has no V
	// managed-array metadata, so replace its flags before publishing/freeing.
	buffer := seccomp_instruction_allocation(u64(length) * sizeof(proc.SockFilter)) @[freed]
	if buffer == unsafe { nil } { return errno.err, errno.enomem }
	mut instructions := []proc.SockFilter{} @[freed]
	unsafe {
		instructions.data = buffer
		instructions.len = length
		instructions.cap = length
		instructions.flags = .nogrow
	}
	if !usercopy.copy_from_user(unsafe { voidptr(&instructions[0]) }, header[1], u64(length) * sizeof(proc.SockFilter)) {
		unsafe { instructions.free() }
		return errno.err, errno.efault
	}
	if !proc.seccomp_check(instructions) {
		unsafe { instructions.free() }
		return errno.err, errno.einval
	}
	ret, err := proc.seccomp_attach(instructions, flags & seccomp_filter_flag_tsync != 0,
		flags & seccomp_filter_flag_tsync_esrch != 0)
	if ret != 0 || err != 0 {
		unsafe { instructions.free() }
	}
	return ret, err
}

fn seccomp_instruction_allocation(bytes u64) voidptr {
	$if seccomp_alloc_selftest ? {
		// Fault injection exists only in explicitly built test kernels. It
		// exercises the caller's actual nil path before copying instructions.
		if bytes == u64(4095) * sizeof(proc.SockFilter) { return unsafe { nil } }
	}
	return memory.malloc_packed_fallible(bytes)
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

fn syscall_container_prctl(gpr_state voidptr, _option int, arg2 u64, arg3 u64, arg4 u64, arg5 u64) (u64, u64) {
	mut process := proc.current_thread().process
	// Linux's option is a C int; reserved NNP arguments remain unsigned long.
	option := int(i32(_option))
	match option {
		pr_get_seccomp {
			return u64(proc.seccomp_mode(proc.current_thread())), 0
		}
		pr_set_seccomp {
			match int(arg2) {
				proc.seccomp_mode_strict {
					return seccomp_set_strict()
				}
				proc.seccomp_mode_filter {
					return seccomp_install(arg3, 0)
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
			if !proc.has_capability(process, proc.cap_setpcap) {
				return errno.err, errno.eperm
			}
			if arg2 > u64(proc.cap_last_cap) {
				return errno.err, errno.einval
			}
			process.caps.bounding &= ~(u64(1) << arg2)
			return 0, 0
		}
		pr_set_keepcaps {
			if arg2 > 1 { return errno.err, errno.einval }
			if !proc.set_keepcaps(arg2 != 0) { return errno.err, errno.eperm }
			return 0, 0
		}
		pr_get_keepcaps {
			return if proc.securebits_state(proc.current_thread()) & proc.secbit_keep_caps != 0 { u64(1) } else { u64(0) }, 0
		}
		pr_cap_ambient {
			// Linux ABI: 1 is_set, 2 raise, 3 lower, 4 clear_all.
			if arg4 != 0 || arg5 != 0 || (arg2 == 4 && arg3 != 0) {
				return errno.err, errno.einval
			}
			match arg2 {
				4 {
					process.caps.ambient = 0
					return 0, 0
				}
				2, 3 {
					if arg3 > u64(proc.cap_last_cap) {
						return errno.err, errno.einval
					}
					bit := u64(1) << arg3
					if arg2 == 2 {
						if process.caps.permitted & bit == 0 || process.caps.inheritable & bit == 0
							|| proc.securebits_state(proc.current_thread()) & proc.secbit_no_cap_ambient_raise != 0 {
							return errno.err, errno.eperm
						}
						process.caps.ambient |= bit
					} else {
						process.caps.ambient &= ~bit
					}
					return 0, 0
				}
				1 {
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
			if !proc.set_securebits(arg2) { return errno.err, errno.eperm }
			return 0, 0
		}
		pr_get_securebits {
			return u64(proc.securebits_state(proc.current_thread())), 0
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
