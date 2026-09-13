@[has_globals]
module table

import file
import fs
import aarch64.cpu
import userland
import futex
import pipe
import posixtimer
import socket
import socket.public as sock_pub
import memory.mmap
import numa
import time
import time.sys
import net
import sched
import errno
import usercopy
import proc
import stat
import aarch64.cpu.local as cpulocal
import aarch64.uart
import sysvshm
import krandom

// Linux aarch64 syscall numbers (from asm-generic/unistd.h).
// Table size covers all syscalls we map (max used = 441, epoll_pwait2).
// Keep in sync with the bounds check in asm/aarch64/vectors.S.
const linux_syscall_max = 512

__global (
	syscall_table [linux_syscall_max]voidptr
)

fn syscall_vacant(gpr_state voidptr) (u64, u64) {
	gpr := unsafe { &cpulocal.GPRState(gpr_state) }
	uart.puts(c'VACANT SC:')
	uart.put_dec(gpr.x8)
	uart.puts(c'\n')
	return u64(-1), errno.enosys
}

// Vinix filesystems do not expose extended attributes yet. Linux software
// probes every xattr entry point during prefix and cache setup; ENOTSUP is the
// defined filesystem answer and avoids treating each harmless probe as an
// unknown syscall.
fn syscall_linux_xattr_unsupported(_ voidptr) (u64, u64) {
	return errno.err, errno.enotsup
}

// Ring buffer for last N syscalls before a crash
// Ring buffer for last N syscalls before crash
struct SyscallTraceEntry {
mut:
	nr  u64
	x0  u64
	x1  u64
	x2  u64
	x3  u64
	ret u64
	err u64
	pid u64
}

__global (
	sc_trace_active    = bool(false)
	sc_ring            [64]SyscallTraceEntry
	sc_ring_idx        = u64(0)
	sc_trace_pid       = u64(0) // PID to trace (0 = all)
	sc_trace_gpr_state = u64(0)
)

@[export: 'syscall_trace']
pub fn syscall_trace(gpr_state voidptr) {
	// A busy userspace workload can keep the HVF scheduler out of its normal
	// idle polling loop. This throttled, input-only call keeps the desktop
	// responsive while translated applications occupy every virtual CPU.
	sched.poll_syscall_input()
	gpr := unsafe { &cpulocal.GPRState(gpr_state) }
	nr := gpr.x8
	mut current_thread := proc.current_thread()
	pid := u64(current_thread.process.pid)
	// Debug: detect x30=0x220000 corruption at syscall entry
	if pid == 3 && gpr.x30 == u64(0x220000) {
		uart.puts(c'\nSYSCALL ENTRY: pid=3 x30=0x220000! nr=')
		uart.put_dec(nr)
		uart.puts(c' pc=0x')
		uart.put_hex(gpr.pc)
		uart.puts(c' sp=0x')
		uart.put_hex(gpr.sp)
		uart.puts(c' x29=0x')
		uart.put_hex(gpr.x29)
		uart.puts(c' x16=0x')
		uart.put_hex(gpr.x16)
		uart.puts(c' x17=0x')
		uart.put_hex(gpr.x17)
		uart.putc(`\n`)
	}
	// Record in ring buffer for crash dump
	idx := sc_ring_idx % 64
	sc_ring[idx].nr = nr
	sc_ring[idx].x0 = gpr.x0
	sc_ring[idx].x1 = gpr.x1
	sc_ring[idx].x2 = gpr.x2
	sc_ring[idx].x3 = gpr.x3
	sc_ring[idx].pid = pid
	sc_trace_gpr_state = u64(gpr_state)
	sc_trace_active = true
}

@[export: 'syscall_trace_ret']
pub fn syscall_trace_ret(ret u64, err u64) {
	if !sc_trace_active {
		return
	}
	idx := sc_ring_idx % 64
	sc_ring[idx].ret = ret
	sc_ring[idx].err = err
	sc_ring_idx++
	sc_trace_active = false
}

@[export: 'sc_dump_ring']
pub fn sc_dump_ring() {
	uart.puts(c'\n=== SYSCALL RING BUFFER (last 64) ===\n')
	start := if sc_ring_idx >= 64 { sc_ring_idx - 64 } else { u64(0) }
	for i := start; i < sc_ring_idx; i++ {
		idx := i % 64
		e := sc_ring[idx]
		uart.puts(c'P')
		uart.put_dec(e.pid)
		uart.puts(c' [')
		uart.put_dec(e.nr)
		uart.puts(c'](')
		uart.put_hex(e.x0)
		uart.puts(c',')
		uart.put_hex(e.x1)
		uart.puts(c',')
		uart.put_hex(e.x2)
		uart.puts(c',')
		uart.put_hex(e.x3)
		uart.puts(c')->')
		uart.put_hex(e.ret)
		if e.err != 0 {
			uart.puts(c' E')
			uart.put_dec(e.err)
		}
		uart.puts(c'\n')
	}
	uart.puts(c'=== END RING BUFFER ===\n')
}

// ── Wrapper / stub syscalls for Linux compatibility ──

// Linux mmap passes prot and flags as separate args (x2, x3).
// Vinix's syscall_mmap expects them packed: prot in upper 32 bits, flags in lower 32.
fn syscall_linux_mmap(gpr_state voidptr, addr voidptr, length u64, prot u64, flags u64, fdnum int, offset i64) (u64, u64) {
	prot_and_flags := (prot << 32) | flags
	return file.syscall_mmap(gpr_state, addr, length, prot_and_flags, fdnum, offset)
}

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

	buffer := unsafe { malloc(total) }
	if buffer == unsafe { nil } {
		return errno.err, errno.enomem
	}
	defer {
		unsafe { free(buffer) }
	}

	mut offset := u64(0)
	for i := 0; i < iovcnt; i++ {
		iov := read_linux_iov(iov_ptr, i) or { return errno.err, errno.efault }
		if iov.len == 0 {
			continue
		}
		if !usercopy.copy_from_user(voidptr(u64(buffer) + offset), iov.base, iov.len) {
			return errno.err, errno.efault
		}
		offset += iov.len
	}
	return fs.syscall_write(gpr_state, fdnum, buffer, total)
}

// Linux getdents64(fd, dirp, count) — fill buffer with directory entries.
// Vinix readdir returns one entry at a time; we loop to fill the buffer.
fn syscall_linux_getdents64(gpr_state voidptr, fdnum int, dirp u64, count u64) (u64, u64) {
	mut offset := u64(0)
	for offset + 19 < count { // minimum dirent64 size: 19 bytes + 1 name char
		mut dirent := stat.Dirent{}
		ret, err := fs.syscall_readdir(gpr_state, fdnum, mut &dirent)
		if err != 0 {
			if offset > 0 {
				return offset, 0
			}
			return ret, err
		}
		// Vinix readdir returns (errno.err, 0) at end of directory
		if ret == errno.err {
			break
		}
		// Calculate name length
		mut name_len := u64(0)
		for name_len < 1024 && dirent.name[name_len] != 0 {
			name_len++
		}
		// Record length: d_ino(8) + d_off(8) + d_reclen(2) + d_type(1) + name + null, aligned to 8
		reclen := (u64(19) + name_len + u64(1) + u64(7)) & ~u64(7)
		if offset + reclen > count {
			// syscall_readdir() advances the shared directory position. Leave
			// this entry for the next getdents64 call instead of losing it.
			fs.readdir_unread(fdnum)
			break
		}
		// Write linux_dirent64 to user buffer
		unsafe {
			*&u64(dirp + offset) = dirent.ino
			*&u64(dirp + offset + 8) = dirent.off
			*&u16(dirp + offset + 16) = u16(reclen)
			*&u8(dirp + offset + 18) = dirent.@type
			C.memcpy(voidptr(dirp + offset + 19), &dirent.name[0], name_len + 1)
		}
		offset += reclen
	}
	return offset, 0
}

// Linux uname(buf) — fill utsname (6 x 65-byte fields).
fn syscall_linux_uname(_ voidptr, buf u64) (u64, u64) {
	mut uts := [390]u8{}
	unsafe {
		C.strcpy(charptr(&uts[0]), c'Vinix')
		C.strcpy(charptr(&uts[65]), c'vinix')
		C.strcpy(charptr(&uts[130]), c'0.1.0')
		C.strcpy(charptr(&uts[195]), c'Vinix 0.1.0 aarch64')
		C.strcpy(charptr(&uts[260]), c'aarch64')
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

const task_comm_len = 16

fn syscall_linux_prctl(_ voidptr, option int, arg2 u64, _arg3 u64, _arg4 u64, _arg5 u64) (u64, u64) {
	mut process := proc.current_thread().process

	match option {
		pr_set_name {
			// The name is the thread's, up to 16 bytes including the null.
			mut raw := [task_comm_len]u8{}
			if !usercopy.copy_from_user(voidptr(&raw[0]), arg2, task_comm_len) {
				return errno.err, errno.efault
			}
			raw[task_comm_len - 1] = 0
			process.name = unsafe { cstring_to_vstring(&raw[0]) }
			return 0, 0
		}
		pr_get_name {
			mut raw := [task_comm_len]u8{}
			mut length := u64(process.name.len)
			if length > task_comm_len - 1 {
				length = task_comm_len - 1
			}
			unsafe { C.memcpy(&raw[0], process.name.str, length) }
			if !usercopy.copy_to_user(arg2, voidptr(&raw[0]), task_comm_len) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		pr_get_dumpable {
			return 1, 0
		}
		pr_set_dumpable, pr_set_pdeathsig, pr_set_no_new_privs {
			// Accepted and remembered nowhere: there is no core dump to
			// suppress, no parent death to notice and no privilege to gain.
			return 0, 0
		}
		pr_get_pdeathsig, pr_get_no_new_privs {
			value := int(0)
			if !usercopy.copy_to_user(arg2, voidptr(&value), sizeof(int)) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

fn syscall_linux_prlimit64(_ voidptr, pid int, res int, new_rlim u64, old_rlim u64) (u64, u64) {
	if res < 0 || res >= proc.rlimit_nlimits {
		return errno.err, errno.einval
	}
	mut process := proc.current_thread().process
	if pid != 0 && pid != process.pid {
		return errno.err, errno.esrch
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
	}

	return 0, 0
}

fn syscall_linux_gettid(_ voidptr) (u64, u64) {
	current := proc.current_thread()
	return u64(current.tid), 0
}

// ── X11 / dynamic-linking syscall stubs ──

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
			file.syscall_pread(gpr_state, in_fd, buffer, chunk, input_offset)
		} else {
			fs.syscall_read(gpr_state, in_fd, buffer, chunk)
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

		written, write_error := fs.syscall_write(gpr_state, out_fd, buffer, got)
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

// setitimer / getitimer: ITIMER_REAL delivers SIGALRM via scheduler tick.
// struct itimerval layout (aarch64):
//   0: it_interval.tv_sec  (i64)
//   8: it_interval.tv_usec (i64)
//  16: it_value.tv_sec     (i64)
//  24: it_value.tv_usec    (i64)
fn syscall_linux_setitimer(_ voidptr, which int, new_value u64, old_value u64) (u64, u64) {
	if which != 0 {
		// Only ITIMER_REAL (0) supported; ITIMER_VIRTUAL (1) and
		// ITIMER_PROF (2) are no-ops.
		if old_value != 0 {
			unsafe { C.memset(voidptr(old_value), 0, 32) }
		}
		return 0, 0
	}

	mut current_thread := proc.current_thread()

	mut value_us := i64(0)
	mut interval_us := i64(0)
	if new_value != 0 {
		interval_sec := unsafe { *&i64(new_value) }
		interval_usec := unsafe { *&i64(new_value + 8) }
		value_sec := unsafe { *&i64(new_value + 16) }
		value_usec := unsafe { *&i64(new_value + 24) }
		interval_us = interval_sec * 1000000 + interval_usec
		value_us = value_sec * 1000000 + value_usec
	}

	old_val, old_int := sched.set_itimer_real(current_thread, value_us, interval_us)

	if old_value != 0 {
		unsafe {
			*&i64(old_value) = old_int / 1000000 // it_interval.tv_sec
			*&i64(old_value + 8) = old_int % 1000000 // it_interval.tv_usec
			*&i64(old_value + 16) = old_val / 1000000 // it_value.tv_sec
			*&i64(old_value + 24) = old_val % 1000000 // it_value.tv_usec
		}
	}

	return 0, 0
}

fn syscall_linux_getitimer(_ voidptr, which int, curr_value u64) (u64, u64) {
	if which != 0 || curr_value == 0 {
		if curr_value != 0 {
			unsafe { C.memset(voidptr(curr_value), 0, 32) }
		}
		return 0, 0
	}

	current_thread := proc.current_thread()
	val, intv := sched.get_itimer_real(current_thread)

	unsafe {
		*&i64(curr_value) = intv / 1000000 // it_interval.tv_sec
		*&i64(curr_value + 8) = intv % 1000000 // it_interval.tv_usec
		*&i64(curr_value + 16) = val / 1000000 // it_value.tv_sec
		*&i64(curr_value + 24) = val % 1000000 // it_value.tv_usec
	}

	return 0, 0
}

// setpgid / getpgid: wait4()/waitid() select on process groups, so these have
// to be real.
fn syscall_linux_setpgid(_ voidptr, pid int, pgid int) (u64, u64) {
	if pid < 0 || pgid < 0 {
		return errno.err, errno.einval
	}

	mut target := proc.current_thread().process
	if pid != 0 {
		if pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		target = processes[pid]
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
	}

	target.pgid = if pgid == 0 { target.pid } else { pgid }

	return 0, 0
}

fn syscall_linux_getpgid(_ voidptr, pid int) (u64, u64) {
	mut target := proc.current_thread().process
	if pid != 0 {
		if pid < 0 || pid >= proc.max_pid {
			return errno.err, errno.esrch
		}
		target = processes[pid]
		if target == unsafe { nil } {
			return errno.err, errno.esrch
		}
	}

	return u64(target.pgid), 0
}

// sendmsg is implemented by the socket layer so AF_INET datagrams retain their
// destination and stream writes remain one operation.
fn syscall_linux_sendmsg(gpr_state voidptr, fdnum int, msg_ptr u64, flags int) (u64, u64) {
	return socket.syscall_sendmsg(gpr_state, fdnum, unsafe { &sock_pub.MsgHdr(msg_ptr) }, flags)
}

fn syscall_linux_sendto(gpr_state voidptr, fdnum int, buf voidptr, len u64, flags int, dest_addr voidptr, addrlen u32) (u64, u64) {
	return socket.syscall_sendto(gpr_state, fdnum, buf, len, flags, dest_addr, addrlen)
}

fn syscall_linux_recvfrom(gpr_state voidptr, fdnum int, buf voidptr, len u64, flags int, src_addr voidptr, addrlen voidptr) (u64, u64) {
	return socket.syscall_recvfrom(gpr_state, fdnum, buf, len, flags, src_addr, unsafe { &u32(addrlen) })
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

// Convert Vinix stat.Stat (144 bytes, x86_64 layout) to Linux aarch64 struct stat (128 bytes).
// Field order and sizes differ: mode/nlink are swapped and narrower on aarch64, blksize is i32.
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

fn convert_stat_to_statx(src &stat.Stat, dst u64) {
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
}

// statx(dirfd, path, flags, mask, buf). The mask is a request, and a kernel is
// free to answer with more than was asked for as long as stx_mask says what it
// actually filled.
fn syscall_linux_statx(gpr_state voidptr, dirfd int, path charptr, flags int, _mask u32, buf u64) (u64, u64) {
	if buf == 0 {
		return errno.err, errno.efault
	}

	mut vinix_stat := stat.Stat{}
	ret, err := fs.syscall_fstatat(gpr_state, dirfd, path, &vinix_stat, flags)
	if err != 0 {
		return ret, err
	}

	convert_stat_to_statx(&vinix_stat, buf)
	return 0, 0
}

fn convert_stat_to_linux(src &stat.Stat, dst u64) {
	unsafe {
		*&u64(dst + 0) = src.dev
		*&u64(dst + 8) = src.ino
		*&u32(dst + 16) = src.mode // st_mode (u32, moved before nlink)
		*&u32(dst + 20) = u32(src.nlink) // st_nlink (u32, truncated from u64)
		*&u32(dst + 24) = src.uid
		*&u32(dst + 28) = src.gid
		*&u64(dst + 32) = src.rdev
		*&u64(dst + 40) = 0 // __pad1
		*&i64(dst + 48) = src.size
		*&i32(dst + 56) = i32(src.blksize) // st_blksize (i32, truncated from i64)
		*&i32(dst + 60) = 0 // __pad2
		*&i64(dst + 64) = src.blocks
		*&i64(dst + 72) = src.atim.tv_sec
		*&i64(dst + 80) = src.atim.tv_nsec
		*&i64(dst + 88) = src.mtim.tv_sec
		*&i64(dst + 96) = src.mtim.tv_nsec
		*&i64(dst + 104) = src.ctim.tv_sec
		*&i64(dst + 112) = src.ctim.tv_nsec
		*&u32(dst + 120) = 0 // __unused4
		*&u32(dst + 124) = 0 // __unused5
	}
}

// fstatat wrapper: call Vinix fstatat with a local buffer, then convert to Linux layout.
fn syscall_linux_fstatat(gpr_state voidptr, dirfd int, path charptr, linux_buf u64, flags int) (u64, u64) {
	mut vinix_stat := stat.Stat{}
	ret, err := fs.syscall_fstatat(gpr_state, dirfd, path, &vinix_stat, flags)
	if err != 0 {
		return ret, err
	}
	convert_stat_to_linux(&vinix_stat, linux_buf)
	return 0, 0
}

// fstat wrapper: call Vinix fstat with a local buffer, then convert to Linux layout.
fn syscall_linux_fstat(gpr_state voidptr, fdnum int, linux_buf u64) (u64, u64) {
	mut vinix_stat := stat.Stat{}
	ret, err := fs.syscall_fstat(gpr_state, fdnum, &vinix_stat)
	if err != 0 {
		return ret, err
	}
	convert_stat_to_linux(&vinix_stat, linux_buf)
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

fn syscall_linux_setpriority(_ voidptr, which int, who int, prio int) (u64, u64) {
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
	if caller.euid != 0 && caller.euid != target.euid && caller.euid != target.uid {
		return errno.err, errno.eperm
	}
	if wanted < target.nice && caller.euid != 0 {
		return errno.err, errno.eacces
	}
	target.nice = wanted
	return 0, 0
}

fn syscall_linux_getpriority(_ voidptr, which int, who int) (u64, u64) {
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
	// The raw syscall returns 20 - nice so every successful result is positive.
	return u64(20 - target.nice), 0
}

// ── Syscall table initialization with Linux aarch64 numbers ──

pub fn init_syscall_table() {
	// Fill entire table with vacant handler
	for i := 0; i < linux_syscall_max; i++ {
		syscall_table[i] = voidptr(syscall_vacant)
	}

	// Linux aarch64 syscall numbers → Vinix handlers
	// Reference: include/uapi/asm-generic/unistd.h

	// File I/O
	for i := 5; i <= 16; i++ {
		syscall_table[i] = voidptr(syscall_linux_xattr_unsupported)
	}
	syscall_table[17] = voidptr(fs.syscall_getcwd) // __NR_getcwd
	syscall_table[19] = voidptr(file.syscall_eventfd2) // __NR_eventfd2
	syscall_table[23] = voidptr(syscall_linux_dup) // __NR_dup
	syscall_table[24] = voidptr(file.syscall_dup3) // __NR_dup3
	syscall_table[25] = voidptr(file.syscall_fcntl) // __NR_fcntl
	syscall_table[26] = voidptr(fs.syscall_inotify_init) // __NR_inotify_init1
	syscall_table[27] = voidptr(fs.syscall_inotify_add_watch) // __NR_inotify_add_watch
	syscall_table[28] = voidptr(fs.syscall_inotify_rm_watch) // __NR_inotify_rm_watch
	syscall_table[29] = voidptr(fs.syscall_ioctl) // __NR_ioctl
	syscall_table[34] = voidptr(fs.syscall_mkdirat) // __NR_mkdirat
	syscall_table[35] = voidptr(fs.syscall_unlinkat) // __NR_unlinkat
	syscall_table[36] = voidptr(fs.syscall_symlinkat) // __NR_symlinkat
	syscall_table[37] = voidptr(fs.syscall_linkat) // __NR_linkat
	syscall_table[39] = voidptr(fs.syscall_umount) // __NR_umount2
	syscall_table[40] = voidptr(fs.syscall_mount) // __NR_mount
	syscall_table[47] = voidptr(file.syscall_fallocate) // __NR_fallocate
	syscall_table[48] = voidptr(syscall_linux_faccessat) // __NR_faccessat
	syscall_table[49] = voidptr(fs.syscall_chdir) // __NR_chdir
	syscall_table[50] = voidptr(fs.syscall_fchdir) // __NR_fchdir
	syscall_table[52] = voidptr(fs.syscall_fchmod) // __NR_fchmod
	syscall_table[53] = voidptr(fs.syscall_fchmodat) // __NR_fchmodat
	syscall_table[54] = voidptr(fs.syscall_fchownat) // __NR_fchownat
	syscall_table[55] = voidptr(fs.syscall_fchown) // __NR_fchown
	syscall_table[56] = voidptr(fs.syscall_openat) // __NR_openat
	syscall_table[57] = voidptr(fs.syscall_close) // __NR_close
	syscall_table[59] = voidptr(pipe.syscall_pipe) // __NR_pipe2
	syscall_table[61] = voidptr(syscall_linux_getdents64) // __NR_getdents64
	syscall_table[62] = voidptr(fs.syscall_seek) // __NR_lseek
	syscall_table[63] = voidptr(fs.syscall_read) // __NR_read
	syscall_table[64] = voidptr(fs.syscall_write) // __NR_write
	syscall_table[65] = voidptr(syscall_linux_readv) // __NR_readv
	syscall_table[66] = voidptr(syscall_linux_writev) // __NR_writev
	syscall_table[67] = voidptr(syscall_linux_pread64) // __NR_pread64
	syscall_table[68] = voidptr(syscall_linux_pwrite64) // __NR_pwrite64
	syscall_table[69] = voidptr(syscall_linux_preadv) // __NR_preadv
	syscall_table[70] = voidptr(syscall_linux_pwritev) // __NR_pwritev
	syscall_table[72] = voidptr(file.syscall_pselect6) // __NR_pselect6
	syscall_table[73] = voidptr(file.syscall_ppoll) // __NR_ppoll
	syscall_table[74] = voidptr(userland.syscall_signalfd) // __NR_signalfd4
	syscall_table[78] = voidptr(fs.syscall_readlinkat) // __NR_readlinkat
	syscall_table[79] = voidptr(syscall_linux_fstatat) // __NR_fstatat / newfstatat
	syscall_table[80] = voidptr(syscall_linux_fstat) // __NR_fstat
	syscall_table[75] = voidptr(pipe.syscall_vmsplice) // __NR_vmsplice
	syscall_table[76] = voidptr(pipe.syscall_splice) // __NR_splice
	syscall_table[77] = voidptr(pipe.syscall_tee) // __NR_tee
	syscall_table[81] = voidptr(fs.syscall_sync) // __NR_sync
	syscall_table[82] = voidptr(file.syscall_fsync) // __NR_fsync
	syscall_table[83] = voidptr(file.syscall_fsync) // __NR_fdatasync
	syscall_table[84] = voidptr(file.syscall_sync_file_range) // __NR_sync_file_range
	syscall_table[85] = voidptr(file.syscall_timerfd_create) // __NR_timerfd_create
	syscall_table[86] = voidptr(file.syscall_timerfd_settime) // __NR_timerfd_settime
	syscall_table[87] = voidptr(file.syscall_timerfd_gettime) // __NR_timerfd_gettime
	syscall_table[267] = voidptr(fs.syscall_syncfs) // __NR_syncfs
	syscall_table[279] = voidptr(fs.syscall_memfd_create) // __NR_memfd_create
	syscall_table[281] = voidptr(userland.syscall_execveat) // __NR_execveat
	syscall_table[283] = voidptr(syscall_linux_membarrier) // __NR_membarrier
	syscall_table[285] = voidptr(pipe.syscall_copy_file_range) // __NR_copy_file_range
	syscall_table[286] = voidptr(syscall_linux_preadv2) // __NR_preadv2
	syscall_table[287] = voidptr(syscall_linux_pwritev2) // __NR_pwritev2
	syscall_table[291] = voidptr(syscall_linux_statx) // __NR_statx
	syscall_table[436] = voidptr(file.syscall_close_range) // __NR_close_range
	syscall_table[437] = voidptr(syscall_linux_openat2) // __NR_openat2
	syscall_table[439] = voidptr(syscall_linux_faccessat2) // __NR_faccessat2
	syscall_table[441] = voidptr(file.syscall_epoll_pwait2) // __NR_epoll_pwait2

	// Process control
	syscall_table[93] = voidptr(userland.syscall_exit) // __NR_exit
	syscall_table[94] = voidptr(userland.syscall_exit_group) // __NR_exit_group
	syscall_table[95] = voidptr(userland.syscall_waitid) // __NR_waitid
	syscall_table[96] = voidptr(userland.syscall_set_tid_address) // __NR_set_tid_address
	syscall_table[98] = voidptr(syscall_linux_futex) // __NR_futex
	syscall_table[99] = voidptr(userland.syscall_set_robust_list) // __NR_set_robust_list
	syscall_table[100] = voidptr(userland.syscall_get_robust_list) // __NR_get_robust_list
	syscall_table[101] = voidptr(sys.syscall_nanosleep) // __NR_nanosleep
	syscall_table[113] = voidptr(sys.syscall_clock_gettime) // __NR_clock_gettime
	syscall_table[114] = voidptr(sys.syscall_clock_getres) // __NR_clock_getres
	syscall_table[115] = voidptr(sys.syscall_clock_nanosleep) // __NR_clock_nanosleep
	syscall_table[118] = voidptr(syscall_linux_sched_setparam) // __NR_sched_setparam
	syscall_table[119] = voidptr(syscall_linux_sched_setscheduler) // __NR_sched_setscheduler
	syscall_table[120] = voidptr(syscall_linux_sched_getscheduler) // __NR_sched_getscheduler
	syscall_table[121] = voidptr(syscall_linux_sched_getparam) // __NR_sched_getparam
	syscall_table[122] = voidptr(syscall_linux_sched_setaffinity) // __NR_sched_setaffinity
	syscall_table[123] = voidptr(syscall_linux_sched_getaffinity) // __NR_sched_getaffinity
	syscall_table[124] = voidptr(syscall_linux_sched_yield) // __NR_sched_yield
	syscall_table[125] = voidptr(syscall_linux_sched_get_priority_max) // __NR_sched_get_priority_max
	syscall_table[126] = voidptr(syscall_linux_sched_get_priority_min) // __NR_sched_get_priority_min
	syscall_table[127] = voidptr(syscall_linux_sched_rr_get_interval) // __NR_sched_rr_get_interval
	syscall_table[129] = voidptr(userland.syscall_kill) // __NR_kill
	syscall_table[130] = voidptr(userland.syscall_tkill) // __NR_tkill
	syscall_table[131] = voidptr(userland.syscall_tgkill) // __NR_tgkill
	syscall_table[132] = voidptr(userland.syscall_sigaltstack) // __NR_sigaltstack
	syscall_table[133] = voidptr(userland.syscall_rt_sigsuspend) // __NR_rt_sigsuspend
	syscall_table[134] = voidptr(userland.syscall_rt_sigaction) // __NR_rt_sigaction
	syscall_table[135] = voidptr(userland.syscall_rt_sigprocmask) // __NR_rt_sigprocmask
	syscall_table[136] = voidptr(syscall_linux_rt_sigpending) // __NR_rt_sigpending
	syscall_table[137] = voidptr(userland.syscall_rt_sigtimedwait) // __NR_rt_sigtimedwait
	syscall_table[139] = voidptr(userland.syscall_sigreturn) // __NR_rt_sigreturn
	syscall_table[140] = voidptr(syscall_linux_setpriority) // __NR_setpriority
	syscall_table[141] = voidptr(syscall_linux_getpriority) // __NR_getpriority
	syscall_table[156] = voidptr(userland.syscall_getsid) // __NR_getsid
	syscall_table[157] = voidptr(userland.syscall_setsid) // __NR_setsid
	syscall_table[158] = voidptr(userland.syscall_getgroups) // __NR_getgroups
	syscall_table[159] = voidptr(userland.syscall_setgroups) // __NR_setgroups
	syscall_table[160] = voidptr(syscall_linux_uname) // __NR_uname
	syscall_table[163] = voidptr(syscall_linux_getrlimit) // __NR_getrlimit
	syscall_table[164] = voidptr(syscall_linux_setrlimit) // __NR_setrlimit
	syscall_table[169] = voidptr(sys.syscall_gettimeofday) // __NR_gettimeofday
	syscall_table[166] = voidptr(fs.syscall_umask) // __NR_umask
	syscall_table[172] = voidptr(userland.syscall_getpid) // __NR_getpid
	syscall_table[173] = voidptr(userland.syscall_getppid) // __NR_getppid
	// 143 is setregid and 147 is setresuid. The table used to put setregid at
	// 147, so a three-argument setresuid landed in a two-argument handler.
	syscall_table[143] = voidptr(userland.syscall_setregid) // __NR_setregid
	syscall_table[144] = voidptr(userland.syscall_setgid) // __NR_setgid
	syscall_table[145] = voidptr(userland.syscall_setreuid) // __NR_setreuid
	syscall_table[146] = voidptr(userland.syscall_setuid) // __NR_setuid
	syscall_table[147] = voidptr(userland.syscall_setresuid) // __NR_setresuid
	syscall_table[148] = voidptr(userland.syscall_getresuid) // __NR_getresuid
	syscall_table[149] = voidptr(userland.syscall_setresgid) // __NR_setresgid
	syscall_table[150] = voidptr(userland.syscall_getresgid) // __NR_getresgid
	syscall_table[174] = voidptr(userland.syscall_getuid) // __NR_getuid
	syscall_table[175] = voidptr(userland.syscall_geteuid) // __NR_geteuid
	syscall_table[176] = voidptr(userland.syscall_getgid) // __NR_getgid
	syscall_table[177] = voidptr(userland.syscall_getegid) // __NR_getegid
	syscall_table[178] = voidptr(syscall_linux_gettid) // __NR_gettid
	syscall_table[179] = voidptr(sys.syscall_sysinfo) // __NR_sysinfo
	syscall_table[168] = voidptr(numa.syscall_getcpu) // __NR_getcpu
	syscall_table[235] = voidptr(numa.syscall_mbind) // __NR_mbind
	syscall_table[236] = voidptr(numa.syscall_get_mempolicy) // __NR_get_mempolicy
	syscall_table[237] = voidptr(numa.syscall_set_mempolicy) // __NR_set_mempolicy

	// Resource / file locking
	// epoll
	syscall_table[20] = voidptr(file.syscall_epoll_create1) // __NR_epoll_create1
	syscall_table[21] = voidptr(file.syscall_epoll_ctl) // __NR_epoll_ctl
	syscall_table[22] = voidptr(file.syscall_epoll_pwait) // __NR_epoll_pwait

	syscall_table[32] = voidptr(file.syscall_flock) // __NR_flock
	syscall_table[46] = voidptr(file.syscall_ftruncate) // __NR_ftruncate
	syscall_table[71] = voidptr(syscall_linux_sendfile) // __NR_sendfile
	syscall_table[88] = voidptr(fs.syscall_utimensat) // __NR_utimensat
	syscall_table[102] = voidptr(syscall_linux_getitimer) // __NR_getitimer
	syscall_table[103] = voidptr(syscall_linux_setitimer) // __NR_setitimer
	syscall_table[107] = voidptr(posixtimer.syscall_timer_create) // __NR_timer_create
	syscall_table[108] = voidptr(posixtimer.syscall_timer_gettime) // __NR_timer_gettime
	syscall_table[109] = voidptr(posixtimer.syscall_timer_getoverrun) // __NR_timer_getoverrun
	syscall_table[110] = voidptr(posixtimer.syscall_timer_settime) // __NR_timer_settime
	syscall_table[111] = voidptr(posixtimer.syscall_timer_delete) // __NR_timer_delete
	syscall_table[153] = voidptr(syscall_linux_times) // __NR_times
	syscall_table[154] = voidptr(syscall_linux_setpgid) // __NR_setpgid
	syscall_table[155] = voidptr(syscall_linux_getpgid) // __NR_getpgid
	syscall_table[165] = voidptr(sys.syscall_getrusage) // __NR_getrusage
	syscall_table[167] = voidptr(syscall_linux_prctl) // __NR_prctl
	syscall_table[38] = voidptr(fs.syscall_renameat) // __NR_renameat
	syscall_table[276] = voidptr(fs.syscall_renameat2) // __NR_renameat2
	syscall_table[43] = voidptr(fs.syscall_statfs) // __NR_statfs
	syscall_table[44] = voidptr(fs.syscall_fstatfs) // __NR_fstatfs
	syscall_table[45] = voidptr(fs.syscall_truncate) // __NR_truncate
	syscall_table[278] = voidptr(syscall_linux_getrandom) // __NR_getrandom
	syscall_table[435] = voidptr(userland.syscall_clone3) // __NR_clone3
	syscall_table[223] = voidptr(file.syscall_fadvise64) // __NR_fadvise64

	// Sockets
	syscall_table[198] = voidptr(socket.syscall_socket) // __NR_socket
	syscall_table[199] = voidptr(socket.syscall_socketpair) // __NR_socketpair
	syscall_table[200] = voidptr(socket.syscall_bind) // __NR_bind
	syscall_table[201] = voidptr(socket.syscall_listen) // __NR_listen
	syscall_table[202] = voidptr(socket.syscall_accept) // __NR_accept
	syscall_table[203] = voidptr(socket.syscall_connect) // __NR_connect
	syscall_table[204] = voidptr(socket.syscall_getsockname) // __NR_getsockname
	syscall_table[205] = voidptr(socket.syscall_getpeername) // __NR_getpeername
	syscall_table[206] = voidptr(syscall_linux_sendto) // __NR_sendto
	syscall_table[207] = voidptr(syscall_linux_recvfrom) // __NR_recvfrom
	syscall_table[208] = voidptr(socket.syscall_setsockopt) // __NR_setsockopt
	syscall_table[209] = voidptr(socket.syscall_getsockopt) // __NR_getsockopt
	syscall_table[210] = voidptr(socket.syscall_shutdown) // __NR_shutdown
	syscall_table[211] = voidptr(syscall_linux_sendmsg) // __NR_sendmsg
	syscall_table[212] = voidptr(socket.syscall_recvmsg) // __NR_recvmsg
	syscall_table[242] = voidptr(syscall_linux_accept4) // __NR_accept4

	// Memory
	syscall_table[194] = voidptr(sysvshm.syscall_shmget) // __NR_shmget
	syscall_table[195] = voidptr(sysvshm.syscall_shmctl) // __NR_shmctl
	syscall_table[196] = voidptr(sysvshm.syscall_shmat) // __NR_shmat
	syscall_table[197] = voidptr(sysvshm.syscall_shmdt) // __NR_shmdt
	syscall_table[214] = voidptr(mmap.syscall_brk) // __NR_brk
	syscall_table[215] = voidptr(mmap.syscall_munmap) // __NR_munmap
	syscall_table[216] = voidptr(mmap.syscall_mremap) // __NR_mremap
	syscall_table[220] = voidptr(userland.syscall_clone) // __NR_clone
	syscall_table[221] = voidptr(userland.syscall_execve) // __NR_execve
	syscall_table[222] = voidptr(syscall_linux_mmap) // __NR_mmap
	syscall_table[226] = voidptr(mmap.syscall_mprotect) // __NR_mprotect
	syscall_table[232] = voidptr(mmap.syscall_mincore) // __NR_mincore
	syscall_table[227] = voidptr(mmap.syscall_msync) // __NR_msync
	syscall_table[228] = voidptr(syscall_linux_mlock) // __NR_mlock
	syscall_table[229] = voidptr(syscall_linux_mlock) // __NR_munlock
	syscall_table[230] = voidptr(syscall_linux_mlockall) // __NR_mlockall
	syscall_table[231] = voidptr(syscall_linux_munlockall) // __NR_munlockall
	syscall_table[233] = voidptr(mmap.syscall_madvise) // __NR_madvise
	syscall_table[284] = voidptr(syscall_linux_mlock2) // __NR_mlock2

	// Misc
	syscall_table[260] = voidptr(userland.syscall_wait4) // __NR_wait4
	syscall_table[261] = voidptr(syscall_linux_prlimit64) // __NR_prlimit64

	// Networking
	syscall_table[161] = voidptr(net.syscall_sethostname) // __NR_sethostname
	syscall_table[162] = voidptr(net.syscall_setdomainname) // __NR_setdomainname

	// TLS — on aarch64 musl sets TPIDR_EL0 directly, but keep Vinix's
	// set_tls available at a high slot for mlibc compat
	// Vinix extensions. 245-259 is the block asm-generic sets aside for
	// arch-specific syscalls and that arm64 never uses, so nothing upstream can
	// grow into it. They used to sit on 291 and 292, which are statx and
	// io_pgetevents: a program calling statx got set_tls with statx's arguments.
	syscall_table[245] = voidptr(cpu.syscall_set_tls)
	syscall_table[246] = voidptr(userland.syscall_sigentry)
}
