// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module proc

import klock
import errno

pub const mac_prctl = 0x56584d41
pub const mac_domains = 16
pub const mac_types = 32
pub const mac_label_types = 29
pub const mac_ipc_type = u32(29)
pub const mac_device_type = u32(30)
pub const mac_kernel_type = u32(31)
pub const mac_inspect = u32(1)
pub const mac_read = u32(2)
pub const mac_write = u32(4)
pub const mac_execute = u32(8)
pub const mac_create = u32(16)
pub const mac_remove = u32(32)
pub const mac_metadata = u32(64)
pub const mac_ioctl = u32(128)
pub const mac_search = u32(256)
pub const mac_permissions = u32(511)
pub const cap_mac_admin = 34

__global (
	mac_lock klock.Lock
	mac_rules [mac_domains * mac_types]u32
	mac_sealed bool
)

// A staged domain is only consulted by the calling thread's executable
// loader. Ordinary operations retain the old domain until exec commits.
pub fn mac_domain_of(process &Process) u32 {
	return process.mac_domain
}

pub fn mac_current_domain() u32 {
	t := current_thread()
	if t == unsafe { nil } || t.process == unsafe { nil } { return 0 }
	if t.mac_loading && t.process.mac_next_domain != 0 { return t.process.mac_next_domain }
	return t.process.mac_domain
}

pub fn mac_trusted() bool {
	return mac_current_domain() == 0
}

pub fn mac_admin() bool {
	p := current_thread().process
	return mac_trusted() && p.euid == 0 && is_initial_namespace(p.ns.user)
		&& has_capability(p, cap_mac_admin)
}

pub fn mac_allows(domain u32, kind u32, access u32) bool {
	if domain == 0 { return true }
	if domain >= mac_domains || kind >= mac_types || access & ~mac_permissions != 0 { return false }
	// Kernel control files are not a channel through which confined root may
	// change host policy. Read-only observability can be explicitly granted.
	if kind == mac_kernel_type && access & ~(mac_inspect | mac_read | mac_search) != 0 { return false }
	mac_lock.acquire()
	allowed := mac_sealed && mac_rules[domain * mac_types + kind] & access == access
	mac_lock.release()
	return allowed
}

// Serialize a label update with policy sealing. Callers release this after
// persistence, including failures; activation cannot race an incomplete label.
pub fn mac_begin_label_change() bool {
	if !mac_admin() { return false }
	mac_lock.acquire()
	if mac_sealed { mac_lock.release(); return false }
	return true
}

pub fn mac_end_label_change() {
	mac_lock.release()
}

pub fn mac_after_exec(mut process Process) {
	if process.mac_next_domain != 0 {
		process.mac_domain = process.mac_next_domain
		process.mac_next_domain = 0
	}
}

pub fn mac_peer_allowed(caller &Process, target &Process) bool {
	return caller.mac_domain == 0 || caller.mac_domain == target.mac_domain
}

// Scheduling syscalls resolve a global thread ID several times. Check at
// each lookup, including the final read or mutation, so reuse cannot replace
// an authorized thread with one in another domain.
pub fn mac_thread_peer_allowed(tid int) bool {
	if tid <= 0 || tid >= max_pid { errno.set(errno.esrch); return false }
	lock_table()
	defer { unlock_table() }
	target := threads_by_tid[tid]
	if target == unsafe { nil } || target.process == unsafe { nil } {
		errno.set(errno.esrch); return false
	}
	if !mac_peer_allowed(current_thread().process, target.process) {
		errno.set(errno.eperm); return false
	}
	return true
}

// Fixed scalar ABI, deliberately separate from Linux's LSM interfaces.
// 0:get domain, 1:set rule, 2:seal, 3:stage next exec, 4:sealed, 5:get rule.
pub fn mac_control(command u64, arg3 u64, arg4 u64, arg5 u64) (u64, u64) {
	mut p := current_thread().process
	if command == 0 {
		if arg3 != 0 || arg4 != 0 || arg5 != 0 { return u64(-1), 22 }
		return u64(p.mac_domain), 0
	}
	if command == 4 {
		if arg3 != 0 || arg4 != 0 || arg5 != 0 { return u64(-1), 22 }
		mac_lock.acquire()
		sealed := mac_sealed
		mac_lock.release()
		return if sealed { u64(1) } else { u64(0) }, 0
	}
	if command == 5 {
		if arg3 >= mac_domains || arg4 >= mac_types || arg5 != 0 { return u64(-1), 22 }
		mac_lock.acquire()
		rule := mac_rules[arg3 * mac_types + arg4]
		mac_lock.release()
		return u64(rule), 0
	}
	if !mac_admin() { return u64(-1), 1 }
	if command == 3 {
		if arg3 == 0 || arg3 >= mac_domains || arg4 != 0 || arg5 != 0 { return u64(-1), 22 }
		// Staging in a shared address space would let a second thread execute
		// or fork a competing image. Only a single-threaded launcher may stage.
		p.threads_lock.acquire()
		one_thread := p.threads.len == 1
		p.threads_lock.release()
		if !one_thread { return u64(-1), 16 }
		mac_lock.acquire()
		if !mac_sealed { mac_lock.release(); return u64(-1), 1 }
		p.mac_next_domain = u32(arg3)
		mac_lock.release()
		return 0, 0
	}
	mac_lock.acquire()
	defer { mac_lock.release() }
	if mac_sealed { return u64(-1), 1 }
	if command == 1 {
		if arg3 == 0 || arg3 >= mac_domains || arg4 >= mac_types || arg5 & ~u64(mac_permissions) != 0 {
			return u64(-1), 22
		}
		mac_rules[arg3 * mac_types + arg4] = u32(arg5)
		return 0, 0
	}
	if command == 2 {
		if arg3 != 0 || arg4 != 0 || arg5 != 0 { return u64(-1), 22 }
		mac_sealed = true
		return 0, 0
	}
	return u64(-1), 22
}
