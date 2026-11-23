// SPDX-License-Identifier: GPL-2.0-or-later
module mqueuefixture

const quota_uid = u32(1030)
const pr_set_dumpable = 4

fn set_queue_limit(soft u64) bool {
	unsafe {
		mut limit := [soft, u64(819200)]!
		return C.syscall(isize(C.SYS_prlimit64), 0, rlimit_msgqueue, &limit[0], nil) == 0
	}
}

fn write_text_file(path &char, value &char) bool {
	unsafe {
		fd := C.open(path, C.O_WRONLY)
		if fd < 0 { return false }
		length := C.strlen(value)
		written := C.write(fd, value, length) == isize(length)
		return C.close(fd) == 0 && written
	}
}

fn quota_namespace(nested bool) bool {
	unsafe {
		// setuid clears dumpability. Linux uses it to assign ownership of
		// these procfs files while the task installs its own ID maps.
		if C.syscall(isize(C.SYS_prctl), pr_set_dumpable, 1, 0, 0, 0) != 0 { return false }
		if C.syscall(isize(C.SYS_unshare), clone_newuser | clone_newipc) != 0 { return false }
		mapping := if nested { &char(c'0 0 1') } else { &char(c'0 1030 1') }
		return write_text_file(c'/proc/self/uid_map', mapping)
			&& (nested || write_text_file(c'/proc/self/setgroups', c'deny'))
			&& write_text_file(c'/proc/self/gid_map', mapping)
	}
}

// One 904-byte slot plus Linux's 96 bytes of accounting overhead.
fn quota_queue(mut s State, name &char) i64 {
	unsafe { return mq_open(name, o_creat | o_excl | o_rdwr, 0o600, set_attr(s.attr, 0, 1, 904, 0)) }
}

fn nested_quota(mut s State, ready i32, proceed i32) i32 {
	unsafe {
		// A higher local limit does not raise the ceiling in the initial user
		// namespace that the outer namespace captured at creation.
		if !set_queue_limit(3000) || !quota_namespace(true) { return 21 }
		if quota_queue(mut s, c'nested-charge') != -C.EMFILE { return 22 }
		if C.write(ready, c'r', 1) != 1 || C.read(proceed, s.buf, 1) != 1 { return 23 }
		q := quota_queue(mut s, c'nested-charge')
		return if q >= 0 && mq_unlink(c'nested-charge') == 0 && C.close(i32(q)) == 0 { 0 } else { 24 }
	}
}

fn wait_quota_child(child i32) i32 {
	unsafe {
		mut status := i32(-1)
		if child < 0 || C.waitpid(child, &status, 0) != child { return 90 }
		return if status & 0x7f == 0 { (status >> 8) & 255 } else { 91 }
	}
}

fn outer_quota(mut s State, ready i32, proceed i32) i32 {
	unsafe {
		if !quota_namespace(false) || !set_queue_limit(1000) { return 11 }
		q := quota_queue(mut s, c'outer-charge')
		if q < 0 || mq_unlink(c'outer-charge') != 0 { return 12 }
		child := C.fork()
		if child == 0 {
			C.close(i32(q))
			C._exit(nested_quota(mut s, ready, proceed))
		}
		C.close(ready)
		C.close(proceed)
		status := wait_quota_child(child)
		C.close(i32(q))
		return status
	}
}

fn sibling_quota(mut s State) i32 {
	unsafe {
		if !quota_namespace(false) || !set_queue_limit(1000) { return 31 }
		q := quota_queue(mut s, c'sibling-charge')
		return if q >= 0 && mq_unlink(c'sibling-charge') == 0 && C.close(i32(q)) == 0 { 0 } else { 32 }
	}
}

fn quota_tree(mut s State) i32 {
	unsafe {
		if C.setgid(quota_uid) != 0 || C.setuid(quota_uid) != 0 || !set_queue_limit(2000) { return 1 }
		host := quota_queue(mut s, c'host-charge')
		if host < 0 || mq_unlink(c'host-charge') != 0 { return 2 }
		mut ready := [2]i32{}
		mut proceed := [2]i32{}
		if C.pipe(&ready[0]) != 0 || C.pipe(&proceed[0]) != 0 { return 3 }
		outer := C.fork()
		if outer == 0 {
			C.close(ready[0])
			C.close(proceed[1])
			C.close(i32(host))
			C._exit(outer_quota(mut s, ready[1], proceed[0]))
		}
		C.close(ready[1])
		C.close(proceed[0])
		if outer < 0 || C.read(ready[0], s.buf, 1) != 1 { return wait_quota_child(outer) }
		if quota_queue(mut s, c'host-after-child') != -C.EMFILE { return 4 }
		if !set_queue_limit(3000) { return 5 }
		sibling := C.fork()
		if sibling == 0 {
			C.close(i32(host))
			C._exit(sibling_quota(mut s))
		}
		sibling_status := wait_quota_child(sibling)
		if sibling_status != 0 { return sibling_status }
		if C.close(i32(host)) != 0 || C.write(proceed[1], c'p', 1) != 1 { return 6 }
		C.close(ready[0])
		C.close(proceed[1])
		status := wait_quota_child(outer)
		if status != 0 { return status }
		if !set_queue_limit(2000) { return 7 }
		a := quota_queue(mut s, c'quota-reuse-a')
		b := quota_queue(mut s, c'quota-reuse-b')
		if a < 0 || b < 0 { return 8 }
		if mq_unlink(c'quota-reuse-a') != 0 || mq_unlink(c'quota-reuse-b') != 0
			|| C.close(i32(a)) != 0 || C.close(i32(b)) != 0 { return 9 }
		return 0
	}
}

fn quota_effective_owner(mut s State) i32 {
	unsafe {
		if !set_queue_limit(1000) { return 41 }
		root := quota_queue(mut s, c'quota-real-root')
		if root < 0 || mq_unlink(c'quota-real-root') != 0 { return 42 }
		// Real UID 0 already fills its initial account. Effective UID 1030
		// creates the namespace and has room in its own initial account.
		if C.setgid(quota_uid) != 0 || C.syscall(isize(C.SYS_setresuid), 0, quota_uid, 0) != 0
			|| !quota_namespace(false) { return 43 }
		inner := quota_queue(mut s, c'quota-effective-owner')
		if inner < 0 || mq_unlink(c'quota-effective-owner') != 0 || C.close(i32(inner)) != 0 { return 44 }
		return if C.close(i32(root)) == 0 { 0 } else { 45 }
	}
}

fn namespace_quota(mut s State) {
	unsafe {
		s.label = c'user namespace quota'
		mut child := C.fork()
		if child == 0 { C._exit(quota_tree(mut s)) }
		mut status := wait_quota_child(child)
		check(mut s, c'leaf isolation, ancestor ceilings and release on final close', status == 0, status)
		child = C.fork()
		if child == 0 { C._exit(quota_effective_owner(mut s)) }
		status = wait_quota_child(child)
		check(mut s, c'ancestor is charged to namespace creator effective UID', status == 0, status)
	}
}
