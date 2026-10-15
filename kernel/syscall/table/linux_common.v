// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module table

// The Linux syscalls whose handling is the same on every architecture: the
// arguments mean the same thing and the structures they point at have the same
// layout on arm64 and on x86-64. Each architecture's table maps its own
// syscall numbers onto these.

import errno
import katomic
import file
import fs
import futex
import krandom
import kbudget
import memory
import net
import proc
import resource
import sched
import stat
import time
import usercopy
import vmstorage


// Linux's private key only checks the canonical user range; the word need
// not be mapped for a wake on an empty queue. Shared keys resolve the word.
fn linux_futex_address_error(address u64, private bool) u64 {
	if address & 3 != 0 { return errno.einval }
	if address > memory.user_address_limit() - 4 { return errno.efault }
	if !private { usercopy.read_u32(address) or { return errno.efault } }
	return 0
}

// Linux futex(uaddr, futex_op, val, timeout/val2, uaddr2, val3).
fn syscall_linux_futex(_ voidptr, uaddr u64, futex_op u64, val u64, timeout u64, uaddr2 u64, val3 u64) (u64, u64) {
	// PRIVATE selects the address-space/virtual key even on shared mappings.
	// CLOCK_REALTIME selects the clock for absolute WAIT_BITSET deadlines.
	private := futex_op & 0x80 != 0
	// Linux receives an int op. Strip only the two defined modifier bits;
	// other bits identify an unsupported command instead of aliasing WAIT.
	op := u32(futex_op) & ~u32(0x180)
	mut duration := time.TimeSpec{}
	if timeout != 0 && op in [u32(0), 6, 9, 11, 13]! {
		if !usercopy.copy_from_user(voidptr(&duration), timeout, sizeof(time.TimeSpec)) {
			return errno.err, errno.efault
		}
		if duration.tv_sec < 0 || duration.tv_nsec < 0 || duration.tv_nsec >= 1000000000 {
			return errno.err, errno.einval
		}
	}
	if futex_op & 0x100 != 0 && op !in [u32(9), 11, 13]! { return errno.err, errno.enosys }
	match op {
		6, 8, 13 { // FUTEX_LOCK_PI, TRYLOCK_PI, LOCK_PI2.
			if op == 8 || timeout == 0 { return futex.lock_pi(uaddr, op == 8, unsafe { nil }, false) }
			return futex.lock_pi(uaddr, false, &duration, op == 6 || futex_op & 0x100 != 0)
		}
		7 { return futex.unlock_pi(uaddr) }
		0, 9 { // FUTEX_WAIT, FUTEX_WAIT_BITSET
			if op == 9 && u32(val3) == 0 {
				return errno.err, errno.einval
			}
			bitset := if op == 9 { u32(val3) } else { u32(0xffffffff) }
			address_error := linux_futex_address_error(uaddr, private)
			if address_error != 0 { return errno.err, address_error }
			if timeout == 0 {
				return futex.wait_mask_key(uaddr, int(val), private, bitset)
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
					// Compare the word before reporting expiration, just as
					// a relative zero wait does in wait_timeout_mask_key.
					duration = time.TimeSpec{}
				}
			}
			return futex.wait_timeout_mask_key(uaddr, int(val), duration, private, bitset)
		}
		1, 10 { // FUTEX_WAKE, FUTEX_WAKE_BITSET
			if op == 10 && u32(val3) == 0 { return errno.err, errno.einval }
			bitset := if op == 10 { u32(val3) } else { u32(0xffffffff) }
			address_error := linux_futex_address_error(uaddr, private)
			if address_error != 0 { return errno.err, address_error }
			return futex.wake_mask_key(uaddr, int(i32(val)), private, bitset), 0
		}
		5 { // FUTEX_WAKE_OP
			for address in [uaddr, uaddr2]! {
				address_error := linux_futex_address_error(address, private)
				if address_error != 0 { return errno.err, address_error }
			}
			// Decode FUTEX_OP(op, oparg, cmp, cmparg). In particular Qt's
			// QSemaphore uses OR 0 / NE 0 to wake paint worker completions.
			code := u32(val3)
			operation := (code >> 28) & 0xf
			comparison := (code >> 24) & 0xf
			mut operand := i32(code << 8) >> 20
			compare_arg := i32(code << 20) >> 20
			if operation & 7 > 4 {
				return errno.err, errno.enosys
			}
			if operation & 8 != 0 {
				// Linux's original WAKE_OP masks even out-of-range signed
				// shift arguments to five bits for this 32-bit operation.
				operand = i32(u32(1) << (u32(operand) & 31))
			}
			old := usercopy.futex_atomic_op_u32(uaddr2, operation & 7, u32(operand)) or {
				return errno.err, errno.efault
			}
			// A supported atomic operation happens before an unsupported
			// comparison is refused; no queues are woken on that error.
			if comparison > 5 { return errno.err, errno.enosys }
			woken := futex.wake_n_key(uaddr, int(i32(val)), private)
			matched := match comparison {
				0 { i32(old) == compare_arg }
				1 { i32(old) != compare_arg }
				2 { i32(old) < compare_arg }
				3 { i32(old) >= compare_arg }
				4 { i32(old) <= compare_arg }
				else { i32(old) > compare_arg }
			}
			if matched {
				return woken + futex.wake_n_key(uaddr2, int(i32(timeout)), private), 0
			}
			return woken, 0
		}
		3, 4 { // FUTEX_REQUEUE, FUTEX_CMP_REQUEUE
			wake_count := int(i32(val))
			move_count := int(i32(timeout))
			if wake_count < 0 || move_count < 0 { return errno.err, errno.einval }
			for address in [uaddr, uaddr2]! {
				address_error := linux_futex_address_error(address, private)
				if address_error != 0 { return errno.err, address_error }
			}
			return futex.requeue(uaddr, uaddr2, wake_count, move_count, private, op == 4, u32(val3))
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
const linux_iov_fast = 8

struct LinuxIOVector {
mut:
	data &LinuxIOVec = unsafe { nil }
	total u64
	charge kbudget.Charge
	owned bool
}

// Small vectors borrow the caller's stack; larger vectors own one bounded,
// fallible allocation and its scratch reservation until the syscall returns.
fn (vector LinuxIOVector) release() {
	if vector.owned {
		unsafe { free(vector.data) }
		kbudget.release(vector.charge)
	}
}

fn import_linux_iov(iov_ptr u64, iovcnt int, fast voidptr) ?LinuxIOVector {
	if iovcnt < 0 || iovcnt > linux_iov_max {
		errno.set(errno.einval); return none
	}
	if iovcnt == 0 { return LinuxIOVector{} }
	if iov_ptr == 0 { errno.set(errno.efault); return none }
	mut vector := LinuxIOVector{data: unsafe { &LinuxIOVec(fast) }}
	bytes := u64(iovcnt) * sizeof(LinuxIOVec)
	if iovcnt > linux_iov_fast {
		reservation := vmstorage.allocation_bytes(bytes) or { errno.set(errno.enomem); return none }
		vector.charge = proc.reserve_kernel(.scratch, reservation)?
		vector.data = unsafe { &LinuxIOVec(memory.malloc_packed_fallible(bytes)) } @[freed]
		if vector.data == unsafe { nil } {
			kbudget.release(vector.charge)
			errno.set(errno.enomem); return none
		}
		vector.owned = true
	}
	// Copy every header before any resource operation. Later user mutations
	// or unmapping cannot change the lengths and addresses we have imported.
	if !usercopy.copy_from_user(vector.data, iov_ptr, bytes) {
		vector.release(); errno.set(errno.efault); return none
	}
	// Linux rejects any length that cannot be represented by ssize_t before
	// testing payload ranges. The bounded transfer count avoids sum overflow.
	for i := 0; i < iovcnt; i++ {
		if unsafe { vector.data[i].len } > u64(0x7fffffffffffffff) {
			vector.release(); errno.set(errno.einval); return none
		}
	}
	max_count := u64(0x7fffffff) & ~(memory.page_size - 1)
	limit := memory.user_address_limit()
	for i := 0; i < iovcnt; i++ {
		iov := unsafe { vector.data[i] }
		// Linux's one-segment ITER_UBUF path truncates before access_ok.
		// Multiple segments check their original ranges, even after the
		// transfer cap has been reached and their effective length is zero.
		length := if iovcnt == 1 && iov.len > max_count { max_count } else { iov.len }
		if iov.base > limit || length > limit - iov.base {
			vector.release(); errno.set(errno.efault); return none
		}
		taken := if length > max_count - vector.total { max_count - vector.total } else { length }
		unsafe { vector.data[i].len = taken }
		vector.total += taken
	}
	return vector
}

// The most writev(2) gathers into one kernel buffer: one byte more than the
// longest message a socket takes, so that a datagram too long to send is
// refused by its family rather than cut in two.
const linux_writev_max = u64(1024 * 1024) + 1

// Linux validates descriptor access before importing even an empty vector.
// The vector caller holds the lookup reference through its final operation.
fn linux_iov_access_error(fd &file.FD, write bool) u64 {
	flags := fd.handle.flags
	access := flags & resource.o_accmode
	if flags & resource.o_path != 0 || (access != resource.o_rdwr
		&& access != if write { resource.o_wronly } else { resource.o_rdonly }) {
		return errno.ebadf
	}
	return 0
}

// Linux writev(fd, iov, iovcnt) is one write operation.  In particular, a
// protocol header and its payload must reach a stream socket together; issuing
// one resource write per iovec lets the peer consume an incomplete message and
// close before the payload is written.
fn syscall_linux_writev(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int) (u64, u64) {
	return linux_writev_flags(gpr_state, fdnum, iov_ptr, iovcnt, 0)
}

fn linux_writev_flags(_ voidptr, fdnum int, iov_ptr u64, iovcnt int, flags u32) (u64, u64) {
	// fdget takes unsigned int even when the native vector ABI uses a word.
	// The vector count retains its full native width.
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(u32(fdnum))) or { return errno.err, errno.get() }
	defer { fd.unref() }
	access_error := linux_iov_access_error(fd, true)
	if access_error != 0 { return errno.err, access_error }
	fast := C.vinix_stack_alloc(linux_iov_fast * sizeof(LinuxIOVec))
	vector := import_linux_iov(iov_ptr, iovcnt, fast) or { return errno.err, errno.get() }
	defer { vector.release() }
	total := vector.total
	if total == 0 {
		return 0, 0
	}
	// Linux ignores flags on an empty iterator. Nonempty unsupported modes
	// are refused only after validating access and importing every header.
	if flags != 0 {
		fd.handle.mac_check(proc.mac_write) or { return errno.err, errno.get() }
		return errno.err, errno.eopnotsupp
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
		krandom.explicit_bzero(buffer, usize(size))
		unsafe { free(buffer) }
	}

	mut filled := u64(0)
	mut written := u64(0)
	for i := 0; i < iovcnt; i++ {
		iov := unsafe { vector.data[i] }
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
			ret, err := fs.write_pinned_descriptor(mut fd, buffer, filled, false)
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
		ret, err := fs.write_pinned_descriptor(mut fd, buffer, filled, false)
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

fn syscall_linux_prctl(gpr_state voidptr, _option int, arg2 u64, _arg3 u64, _arg4 u64, _arg5 u64) (u64, u64) {
	mut process := proc.current_thread().process
	option := int(i32(_option))

	match option {
		proc.mac_prctl {
			return proc.mac_control(arg2, _arg3, _arg4, _arg5)
		}
		proc.pr_vinix_syscall_policy {
			if _arg4 != 0 || _arg5 != 0 { return errno.err, errno.einval }
			return proc.syscall_policy_control(mut process, arg2, _arg3)
		}
		proc.pr_vinix_stack_policy {
			if _arg3 != 0 || _arg4 != 0 || _arg5 != 0 { return errno.err, errno.einval }
			return proc.stack_policy_control(mut process, arg2, user_stack_pointer(gpr_state))
		}
		pr_set_name {
			// The name is the thread's, up to 16 bytes including the null. It
			// was made the whole process's: node's threads name themselves, and
			// its process went by the last of them -- ps showed DelayedTaskSche,
			// and pgrep node found nothing. The process goes by its first
			// thread's name, as on Linux.
			raw := unsafe { &u8(C.vinix_stack_alloc(task_comm_len)) }
			unsafe { C.memset(raw, 0, task_comm_len) }
			// Linux reads up to 15 bytes, stopping at NUL. A short name at a
			// page boundary must not depend on the following page being mapped.
			for i in 0 .. task_comm_len - 1 {
				if u64(i) > ~arg2 || !usercopy.copy_from_user(unsafe { voidptr(raw + i) }, arg2 + u64(i), 1) {
					return errno.err, errno.efault
				}
				if unsafe { raw[i] } == 0 { break }
			}
			mut current := proc.current_thread()
			new_comm := unsafe { cstring_to_vstring(&char(raw)) }
			new_process_name := if current.tid == process.pid { new_comm.clone() } else { '' }
			// Procfs readers retain either name until they release this lock.
			proc.lock_table()
			defer { proc.unlock_table() }
			old_comm := current.comm
			current.comm = new_comm
			current.comm_named = true
			if old_comm.len > 0 {
				unsafe { old_comm.free() }
			}
			if current.tid == process.pid {
				unsafe { process.name.free() }
				process.name = new_process_name
			}
			return 0, 0
		}
		pr_get_name {
			raw := unsafe { &u8(C.vinix_stack_alloc(task_comm_len)) }
			unsafe { C.memset(raw, 0, task_comm_len) }
			proc.copy_current_command(raw)
			if !usercopy.copy_to_user(arg2, raw, task_comm_len) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		pr_get_dumpable {
			return u64(proc.dumpability(process)), 0
		}
		pr_set_dumpable {
			if arg2 > 1 { return errno.err, errno.einval }
			proc.set_dumpability(mut process, u32(arg2))
			return 0, 0
		}
		pr_set_timerslack {
			t := proc.current_thread()
			katomic.store(mut unsafe { &t.timer_slack_ns }, if arg2 == 0 { u64(50000) } else { arg2 })
			return 0, 0
		}
		pr_get_timerslack {
			return proc.current_thread().timer_slack_ns, 0
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
			if arg2 != 1 || _arg3 != 0 || _arg4 != 0 || _arg5 != 0 {
				return errno.err, errno.einval
			}
			proc.set_no_new_privs()
			return 0, 0
		}
		pr_get_no_new_privs {
			if arg2 != 0 || _arg3 != 0 || _arg4 != 0 || _arg5 != 0 {
				return errno.err, errno.einval
			}
			return u64(proc.no_new_privs_state(proc.current_thread())), 0
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
		krandom.explicit_bzero(buffer, usize(page_size))
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

// Linux scalar descriptors and lseek's selector are unsigned-int arguments,
// even though the native dispatch supplies machine words. Keep byte counts
// and signed offsets full-width, and leave descriptor ownership to the callee.
fn syscall_linux_read(gpr_state voidptr, fdnum int, buf voidptr, count u64) (u64, u64) {
	return fs.syscall_read(gpr_state, int(u32(fdnum)), buf, count)
}

fn syscall_linux_write(gpr_state voidptr, fdnum int, buf voidptr, count u64) (u64, u64) {
	return fs.syscall_write(gpr_state, int(u32(fdnum)), buf, count)
}

fn syscall_linux_close(gpr_state voidptr, fdnum int) (u64, u64) {
	return fs.syscall_close(gpr_state, int(u32(fdnum)))
}

fn syscall_linux_lseek(gpr_state voidptr, fdnum int, offset i64, whence int) (u64, u64) {
	return fs.syscall_seek(gpr_state, int(u32(fdnum)), offset, int(u32(whence)))
}

fn syscall_linux_ftruncate(gpr_state voidptr, fdnum int, length i64) (u64, u64) {
	return file.syscall_ftruncate(gpr_state, int(u32(fdnum)), length)
}

// Linux receives a signed C-int size, including through readlink(2).
// Reject it before pathname lookup or destination access.
fn syscall_linux_readlinkat(gpr_state voidptr, dirfd int, path charptr, buf voidptr, limit u64) (u64, u64) {
	size := i32(u32(limit))
	if size <= 0 { return errno.err, errno.einval }
	return fs.syscall_readlinkat(gpr_state, dirfd, path, buf, u64(size))
}

// pread64: read at offset without changing file position.
fn syscall_linux_pread64(gpr_state voidptr, fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	return file.syscall_pread(gpr_state, int(u32(fdnum)), buf, count, offset)
}

// pwrite64: write at offset without changing file position.
fn syscall_linux_pwrite64(gpr_state voidptr, fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	return file.syscall_pwrite(gpr_state, int(u32(fdnum)), buf, count, offset)
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
	return proc.set_process_group(pid, pgid)
}

fn syscall_linux_getpgid(_ voidptr, pid int) (u64, u64) {
	return proc.get_process_group(pid)
}

fn syscall_linux_sched_yield(_ voidptr) (u64, u64) {
	// yield(false) is the dying-thread path and never returns to the caller;
	// giving up the timeslice while staying runnable is what is wanted here.
	sched.reschedule()
	return 0, 0
}

// Native fcntl takes unsigned-int descriptor/command words. Its third word
// names either an int value or a full-width user pointer, depending on cmd.
fn syscall_linux_fcntl(gpr_state voidptr, fdnum int, cmd int, arg u64) (u64, u64) {
	command := int(u32(cmd))
	mut value := arg
	match command {
		file.f_dupfd, file.f_dupfd_cloexec {
			value = u64(i64(i32(u32(arg))))
		}
		file.f_setfd, file.f_setfl, file.f_setown, file.f_setsig,
		file.f_setpipe_sz, file.f_add_seals, file.f_dupfd_query {
			value = u64(u32(arg))
		}
		else {}
	}
	if command == file.f_dupfd || command == file.f_dupfd_cloexec {
		process := proc.current_thread().process
		if i64(value) < 0 || value >= process.rlimits[proc.rlimit_nofile].cur
			|| value >= u64(proc.max_fds) {
			// Validate the source before refusing the minimum. Keep this
			// fcntl-only: dup still needs EMFILE when no descriptor fits.
			mut descriptor := file.fd_from_fdnum(unsafe { nil }, int(u32(fdnum))) or {
				return errno.err, errno.ebadf
			}
			descriptor.unref()
			return errno.err, errno.einval
		}
	}
	return file.syscall_fcntl(gpr_state, int(u32(fdnum)), command, value)
}

// dup(oldfd) via fcntl(oldfd, F_DUPFD, 0)
fn syscall_linux_dup(gpr_state voidptr, oldfd int) (u64, u64) {
	return file.syscall_fcntl(gpr_state, int(u32(oldfd)), 0, 0)
}

// dup3 takes C-int descriptor/flag words. Reject unknown flags before the
// existing descriptor duplication path can replace or retain either handle.
fn syscall_linux_dup3(gpr_state voidptr, oldfd int, newfd int, flags int) (u64, u64) {
	query_flags := u32(flags)
	if query_flags & ~u32(resource.o_cloexec) != 0 {
		return errno.err, errno.einval
	}
	return file.syscall_dup3(gpr_state, int(u32(oldfd)), int(u32(newfd)), int(query_flags))
}

// struct statx, the 256-byte form statx(2) fills. Its timestamps and its
// split-out device numbers mean it cannot share the struct stat conversion.
const statx_basic_stats = u32(0x7ff)
const statx_reserved = u32(0x80000000)
const statx_no_automount = u32(0x800)
const statx_sync_type = u32(0x6000)

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
fn syscall_linux_statx(gpr_state voidptr, dirfd int, path charptr, flags int, mask u32, buf u64) (u64, u64) {
	query_flags := u32(flags)
	allowed := u32(fs.at_symlink_nofollow | fs.at_empty_path) | statx_no_automount | statx_sync_type
	if mask & statx_reserved != 0 || query_flags & statx_sync_type == statx_sync_type
		|| query_flags & ~allowed != 0 {
		return errno.err, errno.einval
	}

	mut vinix_stat := unsafe { &stat.Stat(C.vinix_stack_alloc(sizeof(stat.Stat))) }
	unsafe { *vinix_stat = stat.Stat{} }
	// NULL is the descriptor-only spelling for nonnegative descriptor words.
	// It must use the held descriptor path, not a kernel string passed to the
	// user-path reader. Negative words retain the pathname EFAULT behavior.
	mut ret := u64(0)
	mut err := u64(0)
	if path == unsafe { nil } && i32(u32(dirfd)) >= 0
		&& query_flags & ~(statx_no_automount | statx_sync_type) == u32(fs.at_empty_path) {
		ret, err = fs.syscall_fstat(gpr_state, int(u32(dirfd)), vinix_stat)
	} else {
		ret, err = fs.syscall_fstatat(gpr_state, int(u32(dirfd)), path, vinix_stat, int(query_flags))
	}
	if err != 0 {
		return ret, err
	}

	if !convert_stat_to_statx(vinix_stat, buf) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// The native fstatat adapters share Linux's C-int argument widths and flag
// validation, while keeping their architecture-specific stat conversions.
// Linux fstatat accepts both sync bits; its NULL descriptor shortcut requires
// exactly AT_EMPTY_PATH, unlike statx's broader descriptor-only spelling.
fn linux_fstatat_lookup(gpr_state voidptr, dirfd int, path charptr, storage &stat.Stat, flags int) (u64, u64) {
	query_flags := u32(flags)
	allowed := u32(fs.at_symlink_nofollow | fs.at_empty_path) | statx_no_automount | statx_sync_type
	if query_flags & ~allowed != 0 {
		return errno.err, errno.einval
	}
	if path == unsafe { nil } && i32(u32(dirfd)) >= 0 && query_flags == u32(fs.at_empty_path) {
		return fs.syscall_fstat(gpr_state, int(u32(dirfd)), storage)
	}
	return fs.syscall_fstatat(gpr_state, int(u32(dirfd)), path, storage, int(query_flags))
}

// readv(fd, iov, iovcnt)
fn syscall_linux_readv(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int) (u64, u64) {
	return linux_readv_flags(gpr_state, fdnum, iov_ptr, iovcnt, 0)
}

fn linux_readv_flags(_ voidptr, fdnum int, iov_ptr u64, iovcnt int, flags u32) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(u32(fdnum))) or { return errno.err, errno.get() }
	defer { fd.unref() }
	access_error := linux_iov_access_error(fd, false)
	if access_error != 0 { return errno.err, access_error }
	fast := C.vinix_stack_alloc(linux_iov_fast * sizeof(LinuxIOVec))
	vector := import_linux_iov(iov_ptr, iovcnt, fast) or { return errno.err, errno.get() }
	defer { vector.release() }
	if vector.total == 0 {
		return 0, 0
	}
	if flags != 0 {
		fd.handle.mac_check(proc.mac_read) or { return errno.err, errno.get() }
		return errno.err, errno.eopnotsupp
	}
	mode := fd.handle.resource.stat.mode
	if stat.isifo(mode) || stat.issock(mode) || mode & stat.ifmt == stat.ifpipe {
		return linux_readv_stream(mut fd, vector, iovcnt)
	}

	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		iov := unsafe { vector.data[i] }
		if iov.len == 0 {
			continue
		}
		ret, err := fs.read_pinned_descriptor(mut fd, voidptr(iov.base), iov.len, true)
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

// A pipe/socket read supplies one available piece or one complete record.
// Reading again for a later iovec can wait after receiving data, discard a
// record's tail, or consume the next record. Keep the imported vector and FD
// borrowed while one bounded receive is scattered into its destinations.
fn linux_readv_stream(mut fd file.FD, vector LinuxIOVector, count int) (u64, u64) {
	record := resource.read_keeps_boundaries(mut fd.handle.resource)
	for i := 0; !record && i < count; i++ {
		iov := unsafe { vector.data[i] }
		if iov.len == 0 { continue }
		// Preserve scalar stream reads' initial destination check.
		if !usercopy.writable(iov.base) { return errno.err, errno.efault }
		break
	}
	size := if vector.total < u64(1024 * 1024) { vector.total } else { u64(1024 * 1024) }
	reservation := vmstorage.allocation_bytes(size) or { return errno.err, errno.enomem }
	charge := proc.reserve_kernel(.scratch, reservation) or { return errno.err, errno.get() }
	defer { kbudget.release(charge) }
	buffer := memory.malloc_packed_fallible(size) @[freed]
	if buffer == unsafe { nil } { return errno.err, errno.enomem }
	defer {
		krandom.explicit_bzero(buffer, usize(size))
		unsafe { free(buffer) }
	}
	ret, err := fs.read_pinned_descriptor(mut fd, buffer, size, false)
	if err != 0 { return ret, err }
	mut copied := u64(0)
	for i := 0; i < count && copied < ret; i++ {
		iov := unsafe { vector.data[i] }
		length := if iov.len < ret - copied { iov.len } else { ret - copied }
		if length == 0 { continue }
		if !usercopy.copy_to_user(iov.base, voidptr(u64(buffer) + copied), length) {
			// UNIX datagram/seqpacket copy faults retire the whole selected
			// record and report EFAULT, including after a committed prefix.
			if copied != 0 && !record { return copied, 0 }
			return errno.err, errno.efault
		}
		copied += length
	}
	return copied, 0
}

const grnd_nonblock = 0x0001

const grnd_random = 0x0002

const grnd_insecure = 0x0004

fn syscall_linux_getrandom(_ voidptr, buf u64, count u64, flags u32) (u64, u64) {
	if flags & ~u32(grnd_nonblock | grnd_random | grnd_insecure) != 0 {
		return errno.err, errno.einval
	}
	if flags & u32(grnd_random | grnd_insecure) == u32(grnd_random | grnd_insecure) {
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

fn syscall_linux_setpriority(_ voidptr, raw_which int, raw_local_who int, raw_prio int) (u64, u64) {
	which := int(i32(raw_which))
	local_who := int(i32(raw_local_who))
	prio := int(i32(raw_prio))
	who := proc.kernel_id(local_who)
	if which != prio_process {
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
	privileged := proc.has_capability(caller, proc.cap_sys_nice)
	if !privileged && caller.euid != target.euid && caller.euid != target.uid {
		return errno.err, errno.eperm
	}
	if wanted < target.nice && !privileged
		&& !proc.limit_allows(target, proc.rlimit_nice, u64(20 - wanted)) {
		return errno.err, errno.eacces
	}
	target.nice = wanted
	return 0, 0
}

fn syscall_linux_getpriority(_ voidptr, raw_which int, raw_local_who int) (u64, u64) {
	which := int(i32(raw_which))
	local_who := int(i32(raw_local_who))
	who := proc.kernel_id(local_who)
	if which != prio_process {
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
