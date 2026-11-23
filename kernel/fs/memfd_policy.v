// SPDX-License-Identifier: GPL-2.0-or-later
module fs

import errno
import katomic
import proc

fn memfd_policy_read(buf voidptr, loc u64, count u64) i64 {
	if loc != 0 || count == 0 {
		return 0
	}
	scope := proc.memfd_noexec_scope(proc.current_thread().process.ns.pid)
	unsafe {
		out := &u8(buf)
		out[0] = `0` + u8(scope)
		if count > 1 {
			out[1] = `\n`
			return 2
		}
	}
	return 1
}

fn memfd_policy_space(byte u8) bool {
	return byte == ` ` || (byte >= 9 && byte <= 13)
}

// proc_dointvec_minmax reads one base-zero integer. In the range 0..2,
// only leading zeroes, an optional hex prefix and one final digit matter.
fn memfd_policy_value(bytes &u8, len int) ?(u32, int) {
	mut i := 0
	unsafe {
		for i < len && memfd_policy_space(bytes[i]) {
			i++
		}
		start := i
		negative := i < len && bytes[i] == `-`
		if negative {
			i++
		}
		if i + 1 < len && bytes[i] == `0` && (bytes[i + 1] == `x` || bytes[i + 1] == `X`) {
			i += 2
		}
		digits := i
		for i < len && bytes[i] == `0` {
			i++
		}
		mut value := u32(0)
		if i < len && (bytes[i] == `1` || bytes[i] == `2`) {
			value = u32(bytes[i] - `0`)
			i++
		}
		if i == digits || i - start > 20 || (negative && value != 0) {
			return none
		}
		if i < len && bytes[i] != ` ` && bytes[i] != `\t` && bytes[i] != `\n` {
			return none
		}
		for i < len && memfd_policy_space(bytes[i]) {
			i++
		}
		return value, i
	}
}

fn memfd_policy_write(buf voidptr, loc u64, count u64) ?i64 {
	process := proc.current_thread().process
	proc.lock_table()
	defer { proc.unlock_table() }
	mut ns := unsafe { process.ns.pid }
	if process.euid != 0 || !proc.has_namespace_capability(process, proc.cap_sys_admin, ns.owner_user) {
		errno.set(errno.eperm)
		return none
	}
	if loc != 0 || count == 0 {
		// With strict sysctl writes, an offset write consumes the input and
		// keeps the current effective value.
		katomic.store(mut &ns.memfd_noexec, proc.memfd_noexec_scope(ns))
		return i64(count)
	}
	len := if count < page_size { int(count) } else { int(page_size - 1) }
	value, consumed := memfd_policy_value(unsafe { &u8(buf) }, len) or {
		errno.set(errno.einval)
		return none
	}
	if value < proc.memfd_noexec_scope(ns.pid_parent) {
		errno.set(errno.einval)
		return none
	}
	katomic.store(mut &ns.memfd_noexec, value)
	return i64(consumed)
}
