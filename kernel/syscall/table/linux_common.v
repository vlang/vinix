// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module table

// The Linux syscalls whose handling is the same on every architecture: the
// arguments mean the same thing and the structures they point at have the same
// layout on arm64 and on x86-64. Each architecture's table maps its own
// syscall numbers onto these.

import errno
import file
import fs
import futex
import krandom
import net
import proc
import sched
import stat
import time
import usercopy


// Linux futex(uaddr, futex_op, val, timeout/val2, uaddr2, val3).
fn syscall_linux_futex(_ voidptr, uaddr u64, futex_op u64, val u64, timeout u64, uaddr2 u64, val3 u64) (u64, u64) {
	// FUTEX_PRIVATE_FLAG does not change the lookup: futexes are keyed by their
	// physical address already. FUTEX_CLOCK_REALTIME selects the clock used by
	// absolute FUTEX_WAIT_BITSET deadlines.
	op := futex_op & 0x7f
	match op {
		0, 9 { // FUTEX_WAIT, FUTEX_WAIT_BITSET
			if op == 9 && val3 == 0 {
				return errno.err, errno.einval
			}
			if timeout == 0 {
				return futex.wait(uaddr, int(val))
			}

			mut duration := time.TimeSpec{}
			if !usercopy.copy_from_user(voidptr(&duration), timeout, sizeof(time.TimeSpec)) {
				return errno.err, errno.efault
			}
			if duration.tv_sec < 0 || duration.tv_nsec < 0 || duration.tv_nsec >= 1000000000 {
				return errno.err, errno.einval
			}

			// FUTEX_WAIT has a relative timeout. FUTEX_WAIT_BITSET names an
			// absolute deadline, so turn it into the relative duration used by
			// the Vinix timer queue.
			if op == 9 {
				clock_id := if futex_op & 0x100 != 0 {
					time.clock_type_realtime
				} else {
					time.clock_type_monotonic
				}
				now := time.clock_now(clock_id) or { return errno.err, errno.einval }
				if duration.sub(now) {
					return errno.err, errno.etimedout
				}
			}
			return futex.wait_timeout(uaddr, int(val), duration)
		}
		1, 10 { // FUTEX_WAKE, FUTEX_WAKE_BITSET
			return futex.wake(uaddr), 0
		}
		5 { // FUTEX_WAKE_OP
			// Decode FUTEX_OP(op, oparg, cmp, cmparg). In particular Qt's
			// QSemaphore uses OR 0 / NE 0 to wake paint worker completions.
			code := u32(val3)
			operation := (code >> 28) & 0xf
			comparison := (code >> 24) & 0xf
			mut operand := i32(code << 8) >> 20
			compare_arg := i32(code << 20) >> 20
			if operation & 7 > 4 || comparison > 5 {
				return errno.err, errno.einval
			}
			if operation & 8 != 0 {
				if operand < 0 || operand >= 32 {
					return errno.err, errno.einval
				}
				operand = i32(u32(1) << u32(operand))
			}
			old := usercopy.futex_atomic_op_u32(uaddr2, operation & 7, u32(operand)) or {
				return errno.err, errno.efault
			}
			woken := futex.wake(uaddr)
			matched := match comparison {
				0 { i32(old) == compare_arg }
				1 { i32(old) != compare_arg }
				2 { i32(old) < compare_arg }
				3 { i32(old) <= compare_arg }
				4 { i32(old) > compare_arg }
				else { i32(old) >= compare_arg }
			}
			if matched {
				return woken + futex.wake(uaddr2), 0
			}
			return woken, 0
		}
		3, 4 { // FUTEX_REQUEUE, FUTEX_CMP_REQUEUE
			// Moving waiters over to uaddr2 would need a real wait queue.
			// Waking them instead is heavier but still correct: pthread_cond
			// waiters recheck their sequence and contend for the mutex, which
			// is exactly what the requeue would have made them do.
			woken := futex.wake(uaddr)
			if uaddr2 != 0 {
				futex.wake(uaddr2)
			}
			return woken, 0
		}
		else {
			return u64(-1), errno.enosys
		}
	}
}

struct LinuxIOVec {
mut:
	base u64
	len  u64
}

const linux_iov_max = 1024

// The most writev(2) gathers into one kernel buffer: one byte more than the
// longest message a socket takes, so that a datagram too long to send is
// refused by its family rather than cut in two.
const linux_writev_max = u64(1024 * 1024) + 1

// Validate the complete vector before doing any I/O.  Linux rejects a bad
// iovcnt, pointer, or aggregate length without partially consuming the file.
fn validate_linux_iov(iov_ptr u64, iovcnt int) (u64, u64) {
	if iovcnt < 0 || iovcnt > linux_iov_max {
		return 0, errno.einval
	}
	if iovcnt == 0 {
		return 0, 0
	}
	if iov_ptr == 0 {
		return 0, errno.efault
	}

	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		mut iov := LinuxIOVec{}
		if !usercopy.copy_from_user(voidptr(&iov), iov_ptr + u64(i) * sizeof(LinuxIOVec), sizeof(LinuxIOVec)) {
			return 0, errno.efault
		}
		if iov.len > u64(0x7fffffffffffffff) - total {
			return 0, errno.einval
		}
		total += iov.len
	}
	return total, 0
}

fn read_linux_iov(iov_ptr u64, index int) ?LinuxIOVec {
	mut iov := LinuxIOVec{}
	if !usercopy.copy_from_user(voidptr(&iov), iov_ptr + u64(index) * sizeof(LinuxIOVec), sizeof(LinuxIOVec)) {
		return none
	}
	return iov
}

// Linux writev(fd, iov, iovcnt) is one write operation.  In particular, a
// protocol header and its payload must reach a stream socket together; issuing
// one resource write per iovec lets the peer consume an incomplete message and
// close before the payload is written.
fn syscall_linux_writev(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int) (u64, u64) {
	total, validation_error := validate_linux_iov(iov_ptr, iovcnt)
	if validation_error != 0 {
		return errno.err, validation_error
	}
	if total == 0 {
		mut checked_fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
			return errno.err, errno.get()
		}
		checked_fd.unref()
		return 0, 0
	}

	// One buffer and one write for anything up to linux_writev_max, which is
	// every header-and-payload a protocol sends. The vector's lengths are the
	// caller's to choose, and a buffer of their sum was a kernel allocation of
	// any size the caller liked: more than this goes out a buffer at a time.
	size := if total < linux_writev_max { total } else { linux_writev_max }
	buffer := unsafe { malloc(size) }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer {
		unsafe { free(buffer) }
	}

	mut filled := u64(0)
	mut written := u64(0)
	for i := 0; i < iovcnt; i++ {
		iov := read_linux_iov(iov_ptr, i) or {
			if written != 0 {
				return written, 0
			}
			return errno.err, errno.efault
		}
		mut taken := u64(0)
		for taken < iov.len {
			chunk := if iov.len - taken < size - filled { iov.len - taken } else { size - filled }
			if !usercopy.copy_from_user(voidptr(u64(buffer) + filled), iov.base + taken, chunk) {
				if written != 0 {
					return written, 0
				}
				return errno.err, errno.efault
			}
			filled += chunk
			taken += chunk
			if filled < size {
				continue
			}
			ret, err := fs.write_from_kernel(fdnum, buffer, filled)
			if err != 0 {
				if written != 0 {
					return written, 0
				}
				return ret, err
			}
			written += ret
			if ret < filled {
				return written, 0
			}
			filled = 0
		}
	}
	if filled != 0 {
		ret, err := fs.write_from_kernel(fdnum, buffer, filled)
		if err != 0 {
			if written != 0 {
				return written, 0
			}
			return ret, err
		}
		written += ret
	}
	return written, 0
}

// uname(buf): struct utsname, six 65-byte fields. `version` and `machine`
// are the architecture's own.
fn linux_uname(buf u64, version charptr, machine charptr) (u64, u64) {
	mut uts := [390]u8{}
	// A container is a Linux system to what runs in it, and /proc there says
	// Linux already: /proc/sys/kernel/ostype, /proc/version. Programs that ask
	// uname(2) which system they are on get the same answer. Erlang takes its
	// os:type() from it, and RabbitMQ's disk monitor refused to start on
	// {unix,vinix}. Outside a container the kernel is Vinix.
	//
	// Its release is a Linux one too. glibc before 2.36 refuses to start on a
	// kernel older than the one it was built for -- 3.7 on arm64 -- and every
	// program in MongoDB 7's and Elasticsearch 8's images, built on Ubuntu
	// 22.04 and 20.04, died with "FATAL: kernel too old" on 0.1.0. 5.15 is a
	// long-term release programs are made to run on; what a newer kernel adds
	// they look for when they want it, and ENOSYS tells them.
	in_container := net.in_own_uts_namespace()
	sysname := if in_container { c'Linux' } else { c'Vinix' }
	release := if in_container { c'5.15.0-vinix' } else { c'0.1.0' }
	unsafe {
		C.strcpy(charptr(&uts[0]), sysname)
		C.strcpy(charptr(&uts[65]), c'vinix')
		C.strcpy(charptr(&uts[130]), release)
		C.strcpy(charptr(&uts[195]), version)
		C.strcpy(charptr(&uts[260]), machine)
	}
	net.copy_hostname(u64(&uts[65]))
	net.copy_domainname(u64(&uts[325]))
	if !usercopy.copy_to_user(buf, voidptr(&uts[0]), u64(uts.len)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// prctl(2). Only the operations that mean something here are served; the rest
// are reported as unsupported rather than answered with a fabricated success,
// so a caller checking the result learns the truth.
const pr_set_pdeathsig = 1

const pr_get_pdeathsig = 2

const pr_get_dumpable = 3

const pr_set_dumpable = 4

const pr_set_name = 15

const pr_get_name = 16

const pr_set_no_new_privs = 38

const pr_get_no_new_privs = 39

const pr_set_timerslack = 29

const pr_get_timerslack = 30

const task_comm_len = 16

fn syscall_linux_prctl(_ voidptr, option int, arg2 u64, _arg3 u64, _arg4 u64, _arg5 u64) (u64, u64) {
	mut process := proc.current_thread().process

	match option {
		proc.mac_prctl {
			return proc.mac_control(arg2, _arg3, _arg4, _arg5)
		}
		pr_set_name {
			// The name is the thread's, up to 16 bytes including the null. It
			// was made the whole process's: node's threads name themselves, and
			// its process went by the last of them -- ps showed DelayedTaskSche,
			// and pgrep node found nothing. The process goes by its first
			// thread's name, as on Linux.
			mut raw := [task_comm_len]u8{}
			if !usercopy.copy_from_user(voidptr(&raw[0]), arg2, task_comm_len) {
				return errno.err, errno.efault
			}
			raw[task_comm_len - 1] = 0
			mut current := proc.current_thread()
			old_comm := current.comm
			current.comm = unsafe { cstring_to_vstring(&raw[0]) }
			if old_comm.len > 0 {
				unsafe { old_comm.free() }
			}
			if current.tid == process.pid {
				unsafe { process.name.free() }
				process.name = current.comm.clone()
			}
			return 0, 0
		}
		pr_get_name {
			mut raw := [task_comm_len]u8{}
			current := proc.current_thread()
			own := if current.comm.len > 0 { current.comm } else { process.name }
			mut length := u64(own.len)
			if length > task_comm_len - 1 {
				length = task_comm_len - 1
			}
			unsafe { C.memcpy(&raw[0], own.str, length) }
			if !usercopy.copy_to_user(arg2, voidptr(&raw[0]), task_comm_len) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		pr_get_dumpable {
			proc.lock_table()
			value := if process.dumpable { u64(1) } else { u64(0) }
			proc.unlock_table()
			return value, 0
		}
		pr_set_dumpable {
			if arg2 > 1 {
				return errno.err, errno.einval
			}
			proc.lock_table()
			process.dumpable = arg2 == 1
			proc.unlock_table()
			return 0, 0
		}
		pr_set_timerslack {
			// Timer slack is not applied yet.
			return 0, 0
		}
		pr_get_timerslack {
			return 50000, 0
		}
		pr_set_pdeathsig {
			if arg2 > 64 {
				return errno.err, errno.einval
			}
			process.pdeathsig = int(arg2)
			return 0, 0
		}
		pr_get_pdeathsig {
			value := i32(process.pdeathsig)
			if !usercopy.copy_to_user(arg2, voidptr(&value), sizeof(i32)) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		pr_set_no_new_privs {
			if arg2 != 1 {
				return errno.err, errno.einval
			}
			process.no_new_privs = true
			return 0, 0
		}
		pr_get_no_new_privs {
			return if process.no_new_privs { u64(1) } else { u64(0) }, 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

fn syscall_linux_prlimit64(_ voidptr, local_pid int, res int, new_rlim u64, old_rlim u64) (u64, u64) {
	pid := proc.kernel_id(local_pid)
	if res < 0 || res >= proc.rlimit_nlimits {
		return errno.err, errno.einval
	}
	mut caller := proc.current_thread().process
	mut process := caller
	mut held_process := &proc.Process(unsafe { nil })
	defer {
		if held_process != unsafe { nil } { proc.unpin_process(held_process) }
	}
	if pid != 0 && pid != caller.pid {
		// A container runtime sets its init's limits from the parent, so
		// prlimit has to reach another process, not only the caller.
		if pid < 0 || pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		proc.lock_table()
		target := proc.process_in(caller.numbered_in, local_pid)
		if target == unsafe { nil } {
			proc.unlock_table()
			return errno.err, errno.esrch
		}
		if !proc.mac_peer_allowed(caller, target) {
			proc.unlock_table()
			return errno.err, errno.eperm
		}
		// Linux allows this with CAP_SYS_RESOURCE or a matching real/effective
		// user; root, which every container runtime runs as here, has both.
		if caller.euid != 0 && caller.euid != target.euid {
			proc.unlock_table()
			return errno.err, errno.eperm
		}
		// This synchronous call continues after dropping the lookup lock.
		// Its pin keeps the target and limits lock alive through all errors.
		proc.pin_process(target)
		held_process = target
		process = target
		proc.unlock_table()
	}

	process.rlimits_lock.acquire()
	defer { process.rlimits_lock.release() }
	old := process.rlimits[res]
	if old_rlim != 0 {
		if !usercopy.copy_to_user(old_rlim, voidptr(&old), sizeof(proc.RLimit)) {
			return errno.err, errno.efault
		}
	}

	if new_rlim != 0 {
		mut wanted := proc.RLimit{}
		if !usercopy.copy_from_user(voidptr(&wanted), new_rlim, sizeof(proc.RLimit)) {
			return errno.err, errno.efault
		}
		if wanted.cur > wanted.max {
			return errno.err, errno.einval
		}
		if wanted.max > old.max && process.euid != 0 {
			return errno.err, errno.eperm
		}
		if res == proc.rlimit_nofile && wanted.max > u64(proc.max_fds) {
			return errno.err, errno.eperm
		}
		if res == proc.rlimit_nproc && wanted.max >= u64(proc.max_pid) {
			return errno.err, errno.eperm
		}
		process.rlimits[res] = wanted
		if res == proc.rlimit_cpu { proc.set_cpu_limit(mut process, wanted) }
	}

	return 0, 0
}

fn syscall_linux_gettid(_ voidptr) (u64, u64) {
	current := proc.current_thread()
	return u64(proc.own_tid(current)), 0
}

// sendfile(out, in, offset, count).  A page-sized bounce buffer keeps the
// transfer bounded; an explicit offset leaves the input descriptor position
// alone, while a null offset consumes it just like read(2).
fn syscall_linux_sendfile(gpr_state voidptr, out_fd int, in_fd int, offset_ptr u64, count u64) (u64, u64) {
	mut input_offset := i64(0)
	positioned := offset_ptr != 0
	if positioned {
		if !usercopy.copy_from_user(voidptr(&input_offset), offset_ptr, sizeof(i64)) {
			return errno.err, errno.efault
		}
		if input_offset < 0 {
			return errno.err, errno.einval
		}
		// Check that the offset is writable before consuming either descriptor.
		if !usercopy.copy_to_user(offset_ptr, voidptr(&input_offset), sizeof(i64)) {
			return errno.err, errno.efault
		}
	}

	// Linux validates both descriptors even for a zero-byte transfer.
	mut input_fd := file.fd_from_fdnum(unsafe { nil }, in_fd) or {
		return errno.err, errno.get()
	}
	input_fd.unref()
	mut output_fd := file.fd_from_fdnum(unsafe { nil }, out_fd) or {
		return errno.err, errno.get()
	}
	output_fd.unref()
	if count == 0 {
		return 0, 0
	}

	buffer := unsafe { malloc(page_size) }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer {
		unsafe { free(buffer) }
	}

	mut total := u64(0)
	for total < count {
		mut chunk := count - total
		if chunk > page_size {
			chunk = page_size
		}

		got, read_error := if positioned {
			file.pread_to_kernel(in_fd, buffer, chunk, input_offset)
		} else {
			fs.read_to_kernel(in_fd, buffer, chunk)
		}
		if read_error != 0 {
			if total > 0 {
				break
			}
			return got, read_error
		}
		if got == 0 {
			break
		}

		written, write_error := fs.write_from_kernel(out_fd, buffer, got)
		if written < got && !positioned {
			// read() already advanced the shared input position.  Put back the
			// suffix the output did not accept.
			fs.syscall_seek(gpr_state, in_fd, -i64(got - written), 1)
		}
		if write_error != 0 {
			if total == 0 {
				return written, write_error
			}
			break
		}

		total += written
		if positioned {
			input_offset += i64(written)
		}
		if written < got {
			break
		}
	}

	if positioned
		&& !usercopy.copy_to_user(offset_ptr, voidptr(&input_offset), sizeof(i64)) {
		return errno.err, errno.efault
	}
	return total, 0
}

// pread64: read at offset without changing file position.
fn syscall_linux_pread64(gpr_state voidptr, fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	return file.syscall_pread(gpr_state, fdnum, buf, count, offset)
}

// pwrite64: write at offset without changing file position.
fn syscall_linux_pwrite64(gpr_state voidptr, fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	return file.syscall_pwrite(gpr_state, fdnum, buf, count, offset)
}

// Both supported Linux ABIs use four signed 64-bit timeval words.
fn itimer_timeval_us(seconds i64, microseconds i64) ?u64 {
	if seconds < 0 || microseconds < 0 || microseconds >= 1000000 {
		return none
	}
	if u64(seconds) > (u64(0x7fffffffffffffff) - u64(microseconds)) / 1000000 {
		return none
	}
	return u64(seconds) * 1000000 + u64(microseconds)
}

fn syscall_linux_setitimer(_ voidptr, which int, new_value u64, old_value u64) (u64, u64) {
	if which < 0 || which > 2 { return errno.err, errno.einval }
	mut incoming := [4]i64{}
	// Linux's historical NULL new_value extension disarms the timer.
	if new_value != 0 && !usercopy.copy_from_user(voidptr(&incoming[0]), new_value, 32) {
		return errno.err, errno.efault
	}
	interval := itimer_timeval_us(incoming[0], incoming[1]) or { return errno.err, errno.einval }
	value := itimer_timeval_us(incoming[2], incoming[3]) or { return errno.err, errno.einval }
	mut current := proc.current_thread()
	mut previous_value := u64(0)
	mut previous_interval := u64(0)
	if which == 0 {
		v, i := sched.set_itimer_real(current, i64(value), i64(interval))
		previous_value = u64(v)
		previous_interval = u64(i)
	} else {
		v, i := proc.set_cpu_itimer(mut current.process, which, value, interval)
		previous_value = v
		previous_interval = i
	}
	if old_value != 0 {
		previous := [i64(previous_interval / 1000000), i64(previous_interval % 1000000),
			i64(previous_value / 1000000), i64(previous_value % 1000000)]!
		if !usercopy.copy_to_user(old_value, voidptr(&previous[0]), 32) {
			return errno.err, errno.efault
		}
	}
	return 0, 0
}

fn syscall_linux_getitimer(_ voidptr, which int, curr_value u64) (u64, u64) {
	if which < 0 || which > 2 { return errno.err, errno.einval }
	if curr_value == 0 { return errno.err, errno.efault }
	current := proc.current_thread()
	mut value := u64(0)
	mut interval := u64(0)
	if which == 0 {
		v, i := sched.get_itimer_real(current)
		value = u64(v)
		interval = u64(i)
	} else {
		value, interval = proc.get_cpu_itimer(current.process, which)
	}
	result := [i64(interval / 1000000), i64(interval % 1000000),
		i64(value / 1000000), i64(value % 1000000)]!
	if !usercopy.copy_to_user(curr_value, voidptr(&result[0]), 32) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// setpgid / getpgid: wait4()/waitid() select on process groups, so these have
// to be real.
fn syscall_linux_setpgid(_ voidptr, pid int, pgid int) (u64, u64) {
	if pid < 0 || pgid < 0 {
		return errno.err, errno.einval
	}

	mut caller := proc.current_thread().process
	mut target := caller
	// Both numbers are the caller's pid namespace's.
	viewer := target.numbered_in
	proc.lock_table()
	defer { proc.unlock_table() }
	if pid != 0 {
		if pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		target = proc.process_in(viewer, pid)
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
	}
	if !proc.mac_peer_allowed(caller, target) { return errno.err, errno.eperm }

	local := if pgid == 0 { proc.pid_in(target, viewer) } else { pgid }
	mut group := if pgid == 0 || local == proc.pid_in(target, viewer) {
		target.pid
	} else {
		proc.group_from_locked(viewer, local)
	}
	if group == 0 {
		// A group whose leader is alive but has nobody in it yet.
		leader := proc.process_in(viewer, local)
		group = if leader == unsafe { nil } { 0 } else { leader.pid }
	}
	if group == 0 {
		return errno.err, errno.eperm
	}
	target.pgid = group
	if proc.numbers_own(target.numbered_in) {
		target.ns_pgid = local
	}

	return 0, 0
}

fn syscall_linux_getpgid(_ voidptr, pid int) (u64, u64) {
	caller := proc.current_thread().process
	mut target := caller
	viewer := target.numbered_in
	proc.lock_table()
	defer { proc.unlock_table() }
	if pid != 0 {
		if pid < 0 || pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		target = proc.process_in(viewer, pid)
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
	}
	if !proc.mac_peer_allowed(caller, target) { return errno.err, errno.eperm }

	return u64(proc.pgid_in(target, viewer)), 0
}

fn syscall_linux_sched_yield(_ voidptr) (u64, u64) {
	// yield(false) is the dying-thread path and never returns to the caller;
	// giving up the timeslice while staying runnable is what is wanted here.
	sched.reschedule()
	return 0, 0
}

// dup(oldfd) via fcntl(oldfd, F_DUPFD, 0)
fn syscall_linux_dup(gpr_state voidptr, oldfd int) (u64, u64) {
	return file.syscall_fcntl(gpr_state, oldfd, 0, 0)
}

// struct statx, the 256-byte form statx(2) fills. Its timestamps and its
// split-out device numbers mean it cannot share the struct stat conversion.
const statx_basic_stats = u32(0x7ff)

fn write_statx_timestamp(dst u64, sec i64, nsec i64) {
	unsafe {
		*&i64(dst + 0) = sec
		*&u32(dst + 8) = u32(nsec)
		*&i32(dst + 12) = 0
	}
}

fn convert_stat_to_statx(src &stat.Stat, user_dst u64) bool {
	mut buf := [256]u8{}
	dst := unsafe { u64(&buf[0]) }
	unsafe {
		C.memset(voidptr(dst), 0, 256)

		*&u32(dst + 0) = statx_basic_stats // stx_mask: what we filled in
		*&u32(dst + 4) = u32(src.blksize)
		*&u64(dst + 8) = 0 // stx_attributes
		*&u32(dst + 16) = u32(src.nlink)
		*&u32(dst + 20) = src.uid
		*&u32(dst + 24) = src.gid
		*&u16(dst + 28) = u16(src.mode)
		*&u64(dst + 32) = src.ino
		*&u64(dst + 40) = u64(src.size)
		*&u64(dst + 48) = u64(src.blocks)
		*&u64(dst + 56) = 0 // stx_attributes_mask

		write_statx_timestamp(dst + 64, src.atim.tv_sec, src.atim.tv_nsec)
		write_statx_timestamp(dst + 80, 0, 0) // stx_btime: not tracked
		write_statx_timestamp(dst + 96, src.ctim.tv_sec, src.ctim.tv_nsec)
		write_statx_timestamp(dst + 112, src.mtim.tv_sec, src.mtim.tv_nsec)

		*&u32(dst + 128) = u32(src.rdev >> 32) // stx_rdev_major
		*&u32(dst + 132) = u32(src.rdev & 0xffffffff) // stx_rdev_minor
		*&u32(dst + 136) = u32(src.dev >> 32) // stx_dev_major
		*&u32(dst + 140) = u32(src.dev & 0xffffffff) // stx_dev_minor
	}
	return usercopy.copy_to_user(user_dst, unsafe { voidptr(&buf[0]) }, u64(sizeof(buf)))
}

// statx(dirfd, path, flags, mask, buf). The mask is a request, and a kernel is
// free to answer with more than was asked for as long as stx_mask says what it
// actually filled.
fn syscall_linux_statx(gpr_state voidptr, dirfd int, path charptr, flags int, _mask u32, buf u64) (u64, u64) {
	if buf == 0 {
		return errno.err, errno.efault
	}

	mut vinix_stat := stat.Stat{}
	ret, err := fs.syscall_fstatat(gpr_state, dirfd, path, unsafe { &vinix_stat }, flags)
	if err != 0 {
		return ret, err
	}

	if !convert_stat_to_statx(&vinix_stat, buf) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// readv(fd, iov, iovcnt)
fn syscall_linux_readv(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int) (u64, u64) {
	_, validation_error := validate_linux_iov(iov_ptr, iovcnt)
	if validation_error != 0 {
		return errno.err, validation_error
	}
	if iovcnt == 0 {
		mut checked_fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
			return errno.err, errno.get()
		}
		checked_fd.unref()
		return 0, 0
	}

	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		iov := read_linux_iov(iov_ptr, i) or { return errno.err, errno.efault }
		if iov.len == 0 {
			continue
		}
		ret, err := fs.syscall_read(gpr_state, fdnum, voidptr(iov.base), iov.len)
		if err != 0 {
			if total > 0 {
				return total, 0
			}
			return ret, err
		}
		total += ret
		if ret < iov.len {
			break
		}
	}
	return total, 0
}

const grnd_nonblock = 0x0001

const grnd_random = 0x0002

const grnd_insecure = 0x0004

fn syscall_linux_getrandom(_ voidptr, buf u64, count u64, flags u32) (u64, u64) {
	if flags & ~u32(grnd_nonblock | grnd_random | grnd_insecure) != 0 {
		return errno.err, errno.einval
	}
	if count == 0 {
		return 0, 0
	}
	if buf == 0 {
		return errno.err, errno.efault
	}

	allow_insecure := flags & u32(grnd_insecure) != 0
	if !krandom.is_ready() && !allow_insecure {
		return errno.err, errno.eagain
	}
	mut bounce := [256]u8{}
	mut written := u64(0)
	for written < count {
		mut chunk := count - written
		if chunk > bounce.len {
			chunk = u64(bounce.len)
		}
		if !krandom.fill(&bounce[0], chunk, allow_insecure) {
			return errno.err, errno.eagain
		}
		if !usercopy.copy_to_user(buf + written, voidptr(&bounce[0]), chunk) {
			// Report the bytes that did land, as the manual page requires.
			if written > 0 {
				return written, 0
			}
			return errno.err, errno.efault
		}
		written += chunk
	}
	unsafe { C.memset(&bounce[0], 0, sizeof(bounce)) }

	return written, 0
}

const prio_process = 0

fn syscall_linux_setpriority(_ voidptr, which int, local_who int, prio int) (u64, u64) {
	who := proc.kernel_id(local_who)
	if which != prio_process || who < 0 {
		return errno.err, errno.einval
	}
	mut caller := proc.current_thread().process
	target_pid := if who == 0 { caller.pid } else { who }
	mut wanted := prio
	if wanted < -20 {
		wanted = -20
	}
	if wanted > 19 {
		wanted = 19
	}

	proc.lock_table()
	defer { proc.unlock_table() }
	mut target := proc.process_at(target_pid)
	if target == unsafe { nil } {
		return errno.err, errno.esrch
	}
	if !proc.mac_peer_allowed(caller, target) { return errno.err, errno.eperm }
	if caller.euid != 0 && caller.euid != target.euid && caller.euid != target.uid {
		return errno.err, errno.eperm
	}
	if wanted < target.nice && caller.euid != 0 {
		return errno.err, errno.eacces
	}
	target.nice = wanted
	return 0, 0
}

fn syscall_linux_getpriority(_ voidptr, which int, local_who int) (u64, u64) {
	who := proc.kernel_id(local_who)
	if which != prio_process || who < 0 {
		return errno.err, errno.einval
	}
	target_pid := if who == 0 { proc.current_thread().process.pid } else { who }
	proc.lock_table()
	defer { proc.unlock_table() }
	target := proc.process_at(target_pid)
	if target == unsafe { nil } {
		return errno.err, errno.esrch
	}
	if !proc.mac_peer_allowed(proc.current_thread().process, target) {
		return errno.err, errno.eperm
	}
	// The raw syscall returns 20 - nice so every successful result is positive.
	return u64(20 - target.nice), 0
}
