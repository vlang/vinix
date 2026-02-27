@[has_globals]
module table

import file
import fs
import aarch64.cpu
import userland
import futex
import pipe
import socket
import memory.mmap
import time.sys
import net
import sched
import errno
import proc
import stat
import aarch64.cpu.local as cpulocal
import aarch64.uart

// Linux aarch64 syscall numbers (from asm-generic/unistd.h).
// Table size covers all syscalls we map (max used = 281).
const linux_syscall_max = 300

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

// Ring buffer for last N syscalls before a crash
// Ring buffer for last N syscalls before crash
struct SyscallTraceEntry {
mut:
	nr   u64
	x0   u64
	x1   u64
	x2   u64
	x3   u64
	ret  u64
	err  u64
	pid  u64
}

__global (
	sc_trace_active = bool(false)
	sc_ring [64]SyscallTraceEntry
	sc_ring_idx = u64(0)
	sc_trace_pid = u64(0) // PID to trace (0 = all)
	sc_trace_gpr_state = u64(0)
)

@[export: 'syscall_trace']
pub fn syscall_trace(gpr_state voidptr) {
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

// clock_getres: return 1ns resolution for all clocks.
fn syscall_linux_clock_getres(_ voidptr, clk_id int, res u64) (u64, u64) {
	if res != 0 {
		unsafe {
			*&i64(res) = 0         // tv_sec = 0
			*&i64(res + 8) = 1     // tv_nsec = 1 (1ns resolution)
		}
	}
	return 0, 0
}

// ── Wrapper / stub syscalls for Linux compatibility ──

// Linux mmap passes prot and flags as separate args (x2, x3).
// Vinix's syscall_mmap expects them packed: prot in upper 32 bits, flags in lower 32.
fn syscall_linux_mmap(gpr_state voidptr, addr voidptr, length u64, prot u64, flags u64, fdnum int, offset i64) (u64, u64) {
	prot_and_flags := (prot << 32) | flags
	return file.syscall_mmap(gpr_state, addr, length, prot_and_flags, fdnum, offset)
}

// Linux futex(uaddr, futex_op, val, ...) — dispatch by op to wait/wake.
fn syscall_linux_futex(gpr_state voidptr, uaddr u64, futex_op u64, val u64) (u64, u64) {
	op := futex_op & 0x7f // mask out FUTEX_PRIVATE_FLAG
	match op {
		0 { // FUTEX_WAIT
			return futex.syscall_futex_wait(gpr_state, unsafe { &int(uaddr) }, int(val))
		}
		1 { // FUTEX_WAKE
			return futex.syscall_futex_wake(gpr_state, unsafe { &int(uaddr) })
		}
		else {
			return u64(-1), errno.enosys
		}
	}
}

// Linux writev(fd, iov, iovcnt) — write each iovec entry sequentially.
fn syscall_linux_writev(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int) (u64, u64) {
	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		entry := iov_ptr + u64(i) * 16
		iov_base := unsafe { *&u64(entry) }
		iov_len := unsafe { *&u64(entry + 8) }
		if iov_len == 0 {
			continue
		}
		ret, err := fs.syscall_write(gpr_state, fdnum, voidptr(iov_base), iov_len)
		if err != 0 {
			if total > 0 {
				return total, 0
			}
			return ret, err
		}
		total += ret
	}
	return total, 0
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

// Linux clone(flags, stack, parent_tid, tls, child_tid) — simplified to fork,
// but respects the child_stack argument so musl posix_spawn works correctly.
// musl's __clone(fn, stack, flags, arg) stores fn/arg on the new stack via
// `stp x0, x3, [x1, #-16]!` then calls svc with x1 = stack - 16.
// After fork, the child resumes at the instruction after svc with SP = child_stack,
// loads fn/arg via `ldp x1, x0, [sp], #16`, and calls fn(arg).
fn syscall_linux_clone(gpr_state voidptr) (u64, u64) {
	mut state := unsafe { &cpulocal.GPRState(gpr_state) }
	child_stack := state.x1 // new stack from musl __clone (x1 before svc)

	// syscall_fork copies gpr_state to the new thread struct.
	// Temporarily set SP to child_stack so the child gets the right SP.
	old_sp := state.sp
	if child_stack != 0 {
		state.sp = child_stack
	}

	ret_val, err_val := userland.syscall_fork(state)

	// Restore parent's SP (child already has its own copy)
	state.sp = old_sp

	return ret_val, err_val
}

// Linux uname(buf) — fill utsname (6 x 65-byte fields).
fn syscall_linux_uname(_ voidptr, buf u64) (u64, u64) {
	unsafe {
		C.memset(voidptr(buf), 0, 390)
		C.strcpy(charptr(buf), c'Vinix')
		C.strcpy(charptr(buf + 65), c'vinix')
		C.strcpy(charptr(buf + 130), c'0.1.0')
		C.strcpy(charptr(buf + 195), c'Vinix 0.1.0 aarch64')
		C.strcpy(charptr(buf + 260), c'aarch64')
	}
	return 0, 0
}

// exit_group — same as exit for single-threaded processes.
@[noreturn]
fn syscall_linux_exit_group(gpr_state voidptr, status int) {
	userland.syscall_exit(gpr_state, status)
}

// set_tid_address — store tid pointer, return tid.
fn syscall_linux_set_tid_address(_ voidptr, tidptr u64) (u64, u64) {
	current := proc.current_thread()
	return u64(current.tid), 0
}

fn syscall_linux_gettid(_ voidptr) (u64, u64) {
	current := proc.current_thread()
	return u64(current.tid), 0
}

// sysinfo: return basic system info (stub with 2GB RAM, 1 CPU)
fn syscall_linux_sysinfo(_ voidptr, info voidptr) (u64, u64) {
	if info != unsafe { nil } {
		unsafe {
			C.memset(info, 0, 112) // sizeof(struct sysinfo) = 112 on aarch64
			mut p := &u64(info)
			p[0] = 0 // uptime
			p[1] = 0 // loads[0]
			p[2] = 0 // loads[1]
			p[3] = 0 // loads[2]
			p[4] = u64(2) * 1024 * 1024 * 1024 // totalram (2GB)
			p[5] = u64(1) * 1024 * 1024 * 1024 // freeram (1GB)
		}
	}
	return 0, 0
}

// getrusage: stub — zero out the rusage struct.
fn syscall_linux_getrusage(_ voidptr, who int, usage u64) (u64, u64) {
	if usage != 0 {
		unsafe { C.memset(voidptr(usage), 0, 144) } // sizeof(struct rusage) = 144 on aarch64
	}
	return 0, 0
}

// flock: stub — pretend it works.
fn syscall_linux_flock(_ voidptr, fd int, operation int) (u64, u64) {
	return 0, 0
}

// fchmodat: stub — return success (permissions are ignored on tmpfs).
fn syscall_linux_fchmodat(_ voidptr, dirfd int, path charptr, mode u32, flags int) (u64, u64) {
	return 0, 0
}

// ── X11 / dynamic-linking syscall stubs ──

// ftruncate: stub — pretend success (mostly used for tmpfiles).
fn syscall_linux_ftruncate(_ voidptr, fd int, length i64) (u64, u64) {
	return 0, 0
}

// sendfile: return ENOSYS so callers fall back to read/write
fn syscall_linux_sendfile(_ voidptr, out_fd int, in_fd int, offset &i64, count u64) (u64, u64) {
	return errno.err, errno.enosys
}

// pread64: read at offset without changing file position.
fn syscall_linux_pread64(gpr_state voidptr, fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	// Save current position, seek to offset, read, seek back.
	old_pos, err1 := fs.syscall_seek(gpr_state, fdnum, 0, 1) // SEEK_CUR
	if err1 != 0 {
		return old_pos, err1
	}
	_, err2 := fs.syscall_seek(gpr_state, fdnum, offset, 0) // SEEK_SET
	if err2 != 0 {
		return errno.err, err2
	}
	ret, err3 := fs.syscall_read(gpr_state, fdnum, buf, count)
	// Restore position regardless of read result
	fs.syscall_seek(gpr_state, fdnum, i64(old_pos), 0) // SEEK_SET
	return ret, err3
}

// pwrite64: write at offset without changing file position.
fn syscall_linux_pwrite64(gpr_state voidptr, fdnum int, buf voidptr, count u64, offset i64) (u64, u64) {
	old_pos, err1 := fs.syscall_seek(gpr_state, fdnum, 0, 1)
	if err1 != 0 {
		return old_pos, err1
	}
	_, err2 := fs.syscall_seek(gpr_state, fdnum, offset, 0)
	if err2 != 0 {
		return errno.err, err2
	}
	ret, err3 := fs.syscall_write(gpr_state, fdnum, buf, count)
	fs.syscall_seek(gpr_state, fdnum, i64(old_pos), 0)
	return ret, err3
}

// utimensat: stub — timestamps not tracked.
fn syscall_linux_utimensat(_ voidptr, dirfd int, path charptr, times u64, flags int) (u64, u64) {
	return 0, 0
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
			*&i64(old_value) = old_int / 1000000      // it_interval.tv_sec
			*&i64(old_value + 8) = old_int % 1000000  // it_interval.tv_usec
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
		*&i64(curr_value) = intv / 1000000      // it_interval.tv_sec
		*&i64(curr_value + 8) = intv % 1000000  // it_interval.tv_usec
		*&i64(curr_value + 16) = val / 1000000  // it_value.tv_sec
		*&i64(curr_value + 24) = val % 1000000  // it_value.tv_usec
	}

	return 0, 0
}

// setpgid / getpgid: stubs — process groups not fully implemented.
fn syscall_linux_setpgid(_ voidptr, pid int, pgid int) (u64, u64) {
	return 0, 0
}

fn syscall_linux_getpgid(_ voidptr, pid int) (u64, u64) {
	current := proc.current_thread()
	return u64(current.process.pid), 0
}

// prctl: stub — return success for most operations.
fn syscall_linux_prctl(_ voidptr, option int, arg2 u64, arg3 u64, arg4 u64, arg5 u64) (u64, u64) {
	return 0, 0
}

// getsockname: return local socket address.
fn syscall_linux_getsockname(_ voidptr, fdnum int, _addr voidptr, addrlen voidptr) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }
	defer { fd.unref() }
	// Return a minimal AF_UNIX sockaddr
	alen := unsafe { *&u32(addrlen) }
	if alen >= 2 {
		unsafe { *&u16(_addr) = 1 } // AF_UNIX
	}
	if alen > 2 {
		unsafe { C.memset(voidptr(u64(_addr) + 2), 0, u64(alen) - 2) }
	}
	return 0, 0
}

// setsockopt / getsockopt: stubs — return success.
fn syscall_linux_setsockopt(_ voidptr, fd int, level int, optname int, optval voidptr, optlen u32) (u64, u64) {
	return 0, 0
}

fn syscall_linux_getsockopt(_ voidptr, fd int, level int, optname int, optval voidptr, optlen voidptr) (u64, u64) {
	// For SO_ERROR and similar, return 0
	if optval != unsafe { nil } && optlen != unsafe { nil } {
		len := unsafe { *&u32(optlen) }
		if len >= 4 {
			unsafe { *&int(optval) = 0 }
			unsafe { *&u32(optlen) = 4 }
		}
	}
	return 0, 0
}

// shutdown: stub — just return success.
fn syscall_linux_shutdown(_ voidptr, fd int, how int) (u64, u64) {
	return 0, 0
}

// sendmsg: write iovec data to socket (no ancillary data support).
fn syscall_linux_sendmsg(gpr_state voidptr, fdnum int, msg_ptr u64, flags int) (u64, u64) {
	// struct msghdr layout (aarch64):
	//   0: msg_name (8)
	//   8: msg_namelen (4) + pad(4)
	//  16: msg_iov (8)
	//  24: msg_iovlen (8)
	//  32: msg_control (8)
	//  40: msg_controllen (8)
	//  48: msg_flags (4)
	iov_ptr := unsafe { *&u64(msg_ptr + 16) }
	iovcnt := unsafe { *&u64(msg_ptr + 24) }

	mut total := u64(0)
	for i := u64(0); i < iovcnt; i++ {
		entry := iov_ptr + i * 16
		iov_base := unsafe { *&u64(entry) }
		iov_len := unsafe { *&u64(entry + 8) }
		if iov_len == 0 {
			continue
		}
		ret, err := fs.syscall_write(gpr_state, fdnum, voidptr(iov_base), iov_len)
		if err != 0 {
			if total > 0 {
				return total, 0
			}
			return ret, err
		}
		total += ret
	}
	return total, 0
}

// sendto: for SOCK_STREAM, just write the data.
fn syscall_linux_sendto(gpr_state voidptr, fdnum int, buf voidptr, len u64, flags int, dest_addr voidptr, addrlen u32) (u64, u64) {
	return fs.syscall_write(gpr_state, fdnum, buf, len)
}

// recvfrom: for SOCK_STREAM, just read the data.
fn syscall_linux_recvfrom(gpr_state voidptr, fdnum int, buf voidptr, len u64, flags int, src_addr voidptr, addrlen voidptr) (u64, u64) {
	return fs.syscall_read(gpr_state, fdnum, buf, len)
}

fn syscall_linux_getuid(_ voidptr) (u64, u64) {
	return 0, 0
}

fn syscall_linux_geteuid(_ voidptr) (u64, u64) {
	return 0, 0
}

fn syscall_linux_getgid(_ voidptr) (u64, u64) {
	return 0, 0
}

fn syscall_linux_getegid(_ voidptr) (u64, u64) {
	return 0, 0
}

// setuid/setgid: stubs — everything runs as root.
// Critical for Xorg's custom Popen which calls setgid(getgid())/setuid(getuid())
// in the child before exec; failure causes _exit(127).
fn syscall_linux_setuid(_ voidptr, uid u32) (u64, u64) {
	return 0, 0
}

fn syscall_linux_setgid(_ voidptr, gid u32) (u64, u64) {
	return 0, 0
}

fn syscall_linux_setreuid(_ voidptr, ruid u32, euid u32) (u64, u64) {
	return 0, 0
}

fn syscall_linux_setregid(_ voidptr, rgid u32, egid u32) (u64, u64) {
	return 0, 0
}

// brk — return 0 to indicate failure; musl falls back to mmap.
fn syscall_linux_brk(_ voidptr, addr u64) (u64, u64) {
	return 0, 0
}

fn syscall_linux_umask(_ voidptr, mask int) (u64, u64) {
	return 0o22, 0
}

fn syscall_linux_set_robust_list(_ voidptr, head u64, len u64) (u64, u64) {
	return 0, 0
}

fn syscall_linux_prlimit64(_ voidptr, pid int, resource int, new_rlim u64, old_rlim u64) (u64, u64) {
	if old_rlim != 0 {
		// Return sensible default limits. RLIMIT_NOFILE (7) must return a
		// reasonable integer, not RLIM_INFINITY — xtrans casts rlim_cur to
		// int and compares fd >= limit, so infinity → -1 which breaks.
		mut soft := u64(1024)
		mut hard := u64(1048576)
		match resource {
			7 { // RLIMIT_NOFILE
				soft = 1024
				hard = 1048576
			}
			else {
				soft = 0xffffffffffffffff
				hard = 0xffffffffffffffff
			}
		}
		unsafe {
			*&u64(old_rlim) = soft
			*&u64(old_rlim + 8) = hard
		}
	}
	return 0, 0
}

fn syscall_linux_sched_yield(_ voidptr) (u64, u64) {
	sched.yield(false)
	return 0, 0
}

// dup(oldfd) via fcntl(oldfd, F_DUPFD, 0)
fn syscall_linux_dup(gpr_state voidptr, oldfd int) (u64, u64) {
	return file.syscall_fcntl(gpr_state, oldfd, 0, 0)
}

// Convert Vinix stat.Stat (144 bytes, x86_64 layout) to Linux aarch64 struct stat (128 bytes).
// Field order and sizes differ: mode/nlink are swapped and narrower on aarch64, blksize is i32.
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
	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		entry := iov_ptr + u64(i) * 16
		iov_base := unsafe { *&u64(entry) }
		iov_len := unsafe { *&u64(entry + 8) }
		if iov_len == 0 {
			continue
		}
		ret, err := fs.syscall_read(gpr_state, fdnum, voidptr(iov_base), iov_len)
		if err != 0 {
			if total > 0 {
				return total, 0
			}
			return ret, err
		}
		total += ret
	}
	return total, 0
}

// getrandom: fill buffer with pseudo-random bytes.
// Uses a simple xorshift64 PRNG seeded from the timer counter.
fn syscall_linux_getrandom(_ voidptr, buf voidptr, count u64, flags u32) (u64, u64) {
	if buf == unsafe { nil } || count == 0 {
		return 0, 0
	}
	// Seed from architectural counter
	mut state := u64(0)
	asm volatile aarch64 {
		mrs state, CNTVCT_EL0
		; =r (state)
	}
	if state == 0 {
		state = 0xdeadbeef12345678
	}
	mut p := &u8(buf)
	for i := u64(0); i < count; i++ {
		state ^= state << 13
		state ^= state >> 7
		state ^= state << 17
		unsafe {
			p[i] = u8(state & 0xff)
		}
	}
	return count, 0
}

// fstatfs: return filesystem statistics for an open fd.
// Stub: report a tmpfs-like filesystem.
fn syscall_linux_fstatfs(_ voidptr, fd int, buf u64) (u64, u64) {
	if buf == 0 {
		return errno.err, errno.efault
	}
	unsafe {
		C.memset(voidptr(buf), 0, 120) // sizeof(struct statfs) on aarch64
		*&u64(buf + 0) = 0x01021994 // f_type = TMPFS_MAGIC
		*&u64(buf + 8) = 4096 // f_bsize
		*&u64(buf + 16) = 262144 // f_blocks (1GB / 4KB)
		*&u64(buf + 24) = 131072 // f_bfree
		*&u64(buf + 32) = 131072 // f_bavail
		*&u64(buf + 40) = 65536 // f_files
		*&u64(buf + 48) = 65536 // f_ffree
		*&u64(buf + 64) = 255 // f_namelen
		*&u64(buf + 72) = 4096 // f_frsize
	}
	return 0, 0
}

// renameat: stub — return success (Xorg creates temp files and renames them).
fn syscall_linux_renameat(gpr_state voidptr, olddirfd int, oldpath charptr, newdirfd int, newpath charptr) (u64, u64) {
	// For now, just return success. A real implementation would need
	// VFS rename support. Xorg uses this for XKB compiled keymaps.
	return 0, 0
}

// Linux-compatible rt_sigaction wrapper.
// Linux k_sigaction layout (aarch64): {handler(8), flags(8), restorer(8), mask(8)} = 32 bytes
// Vinix proc.SigAction layout:         {sa_sigaction(8), sa_mask(8), sa_flags(4)} = 20-24 bytes
// This wrapper translates between the two formats at the syscall boundary.
fn syscall_linux_rt_sigaction(_ voidptr, signum int, act_ptr u64, oldact_ptr u64, sigsetsize u64) (u64, u64) {
	if signum < 0 || signum > 34 || signum == 9 || signum == 19 {
		return errno.err, errno.einval
	}

	mut t := proc.current_thread()

	// Write old sigaction to user memory in Linux format
	if oldact_ptr != 0 {
		sa := t.sigactions[signum]
		unsafe {
			// Linux k_sigaction offsets: handler=0, flags=8, restorer=16, mask=24
			*&u64(oldact_ptr + 0) = u64(sa.sa_sigaction)
			*&u64(oldact_ptr + 8) = u64(sa.sa_flags)
			*&u64(oldact_ptr + 16) = u64(0) // restorer (unused)
			*&u64(oldact_ptr + 24) = sa.sa_mask
		}
	}

	// Read new sigaction from user memory in Linux format
	if act_ptr != 0 {
		unsafe {
			t.sigactions[signum].sa_sigaction = voidptr(*&u64(act_ptr + 0))
			t.sigactions[signum].sa_flags = int(*&u64(act_ptr + 8))
			t.sigactions[signum].sa_restorer = voidptr(*&u64(act_ptr + 16))
			t.sigactions[signum].sa_mask = *&u64(act_ptr + 24)
		}
	}

	return 0, 0
}

// rt_sigsuspend: atomically set signal mask and wait for a signal.
// xinit uses this to wait for SIGUSR1 from Xorg. A proper implementation
// would block until a signal arrives; we yield the CPU and return -EINTR
// so the caller's retry loop progresses without starving other threads.
fn syscall_linux_rt_sigsuspend(_ voidptr, mask u64, sigsetsize u64) (u64, u64) {
	sched.yield(false)
	return errno.err, errno.eintr
}

// setpriority / getpriority: stubs.
fn syscall_linux_setpriority(_ voidptr, which int, who int, prio int) (u64, u64) {
	return 0, 0
}

fn syscall_linux_getpriority(_ voidptr, which int, who int) (u64, u64) {
	return 20, 0 // default nice value
}

// madvise: stub — memory hints are no-ops.
fn syscall_linux_madvise(_ voidptr, addr u64, length u64, advice int) (u64, u64) {
	return 0, 0
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
	syscall_table[17] = voidptr(fs.syscall_getcwd) // __NR_getcwd
	syscall_table[23] = voidptr(syscall_linux_dup) // __NR_dup
	syscall_table[24] = voidptr(file.syscall_dup3) // __NR_dup3
	syscall_table[25] = voidptr(file.syscall_fcntl) // __NR_fcntl
	syscall_table[26] = voidptr(fs.syscall_inotify_init) // __NR_inotify_init1
	syscall_table[29] = voidptr(fs.syscall_ioctl) // __NR_ioctl
	syscall_table[34] = voidptr(fs.syscall_mkdirat) // __NR_mkdirat
	syscall_table[35] = voidptr(fs.syscall_unlinkat) // __NR_unlinkat
	syscall_table[37] = voidptr(fs.syscall_linkat) // __NR_linkat
	syscall_table[39] = voidptr(fs.syscall_umount) // __NR_umount2
	syscall_table[40] = voidptr(fs.syscall_mount) // __NR_mount
	syscall_table[48] = voidptr(fs.syscall_faccessat) // __NR_faccessat
	syscall_table[49] = voidptr(fs.syscall_chdir) // __NR_chdir
	syscall_table[52] = voidptr(fs.syscall_fchmod) // __NR_fchmod
	syscall_table[53] = voidptr(syscall_linux_fchmodat) // __NR_fchmodat
	syscall_table[56] = voidptr(fs.syscall_openat) // __NR_openat
	syscall_table[57] = voidptr(fs.syscall_close) // __NR_close
	syscall_table[59] = voidptr(pipe.syscall_pipe) // __NR_pipe2
	syscall_table[61] = voidptr(syscall_linux_getdents64) // __NR_getdents64
	syscall_table[62] = voidptr(fs.syscall_seek) // __NR_lseek
	syscall_table[63] = voidptr(fs.syscall_read) // __NR_read
	syscall_table[64] = voidptr(fs.syscall_write) // __NR_write
	syscall_table[65] = voidptr(syscall_linux_readv) // __NR_readv
	syscall_table[66] = voidptr(syscall_linux_writev) // __NR_writev
	syscall_table[73] = voidptr(file.syscall_ppoll) // __NR_ppoll
	syscall_table[74] = voidptr(userland.syscall_signalfd) // __NR_signalfd4
	syscall_table[78] = voidptr(fs.syscall_readlinkat) // __NR_readlinkat
	syscall_table[79] = voidptr(syscall_linux_fstatat) // __NR_fstatat / newfstatat
	syscall_table[80] = voidptr(syscall_linux_fstat) // __NR_fstat

	// Process control
	syscall_table[93] = voidptr(userland.syscall_exit) // __NR_exit
	syscall_table[94] = voidptr(syscall_linux_exit_group) // __NR_exit_group
	syscall_table[96] = voidptr(syscall_linux_set_tid_address) // __NR_set_tid_address
	syscall_table[98] = voidptr(syscall_linux_futex) // __NR_futex
	syscall_table[99] = voidptr(syscall_linux_set_robust_list) // __NR_set_robust_list
	syscall_table[101] = voidptr(sys.syscall_nanosleep) // __NR_nanosleep
	syscall_table[113] = voidptr(sys.syscall_clock_get) // __NR_clock_gettime
	syscall_table[114] = voidptr(syscall_linux_clock_getres) // __NR_clock_getres
	syscall_table[124] = voidptr(syscall_linux_sched_yield) // __NR_sched_yield
	syscall_table[129] = voidptr(userland.syscall_kill) // __NR_kill
	syscall_table[133] = voidptr(syscall_linux_rt_sigsuspend) // __NR_rt_sigsuspend
	syscall_table[134] = voidptr(syscall_linux_rt_sigaction) // __NR_rt_sigaction
	syscall_table[135] = voidptr(userland.syscall_sigprocmask) // __NR_rt_sigprocmask
	syscall_table[139] = voidptr(userland.syscall_sigreturn) // __NR_rt_sigreturn
	syscall_table[140] = voidptr(syscall_linux_setpriority) // __NR_setpriority
	syscall_table[141] = voidptr(syscall_linux_getpriority) // __NR_getpriority
	syscall_table[158] = voidptr(userland.syscall_getgroups) // __NR_getgroups
	syscall_table[160] = voidptr(syscall_linux_uname) // __NR_uname
	syscall_table[166] = voidptr(syscall_linux_umask) // __NR_umask
	syscall_table[172] = voidptr(userland.syscall_getpid) // __NR_getpid
	syscall_table[173] = voidptr(userland.syscall_getppid) // __NR_getppid
	syscall_table[144] = voidptr(syscall_linux_setgid) // __NR_setgid
	syscall_table[145] = voidptr(syscall_linux_setreuid) // __NR_setreuid (Xorg Popen)
	syscall_table[146] = voidptr(syscall_linux_setuid) // __NR_setuid
	syscall_table[147] = voidptr(syscall_linux_setregid) // __NR_setregid
	syscall_table[174] = voidptr(syscall_linux_getuid) // __NR_getuid
	syscall_table[175] = voidptr(syscall_linux_geteuid) // __NR_geteuid
	syscall_table[176] = voidptr(syscall_linux_getgid) // __NR_getgid
	syscall_table[177] = voidptr(syscall_linux_getegid) // __NR_getegid
	syscall_table[178] = voidptr(syscall_linux_gettid) // __NR_gettid
	syscall_table[179] = voidptr(syscall_linux_sysinfo) // __NR_sysinfo

	// Resource / file locking
	// epoll
	syscall_table[20] = voidptr(file.syscall_epoll_create1) // __NR_epoll_create1
	syscall_table[21] = voidptr(file.syscall_epoll_ctl) // __NR_epoll_ctl
	syscall_table[22] = voidptr(file.syscall_epoll_pwait) // __NR_epoll_pwait

	syscall_table[32] = voidptr(syscall_linux_flock) // __NR_flock
	syscall_table[46] = voidptr(syscall_linux_ftruncate) // __NR_ftruncate
	syscall_table[71] = voidptr(syscall_linux_sendfile) // __NR_sendfile
	syscall_table[67] = voidptr(syscall_linux_pread64) // __NR_pread64
	syscall_table[68] = voidptr(syscall_linux_pwrite64) // __NR_pwrite64
	syscall_table[88] = voidptr(syscall_linux_utimensat) // __NR_utimensat
	syscall_table[103] = voidptr(syscall_linux_setitimer) // __NR_setitimer
	syscall_table[104] = voidptr(syscall_linux_getitimer) // __NR_getitimer
	syscall_table[154] = voidptr(syscall_linux_setpgid) // __NR_setpgid
	syscall_table[155] = voidptr(syscall_linux_getpgid) // __NR_getpgid
	syscall_table[165] = voidptr(syscall_linux_getrusage) // __NR_getrusage
	syscall_table[167] = voidptr(syscall_linux_prctl) // __NR_prctl
	syscall_table[38] = voidptr(syscall_linux_renameat) // __NR_renameat
	syscall_table[44] = voidptr(syscall_linux_fstatfs) // __NR_fstatfs
	syscall_table[278] = voidptr(syscall_linux_getrandom) // __NR_getrandom

	// Sockets
	syscall_table[198] = voidptr(socket.syscall_socket) // __NR_socket
	syscall_table[199] = voidptr(socket.syscall_socketpair) // __NR_socketpair
	syscall_table[200] = voidptr(socket.syscall_bind) // __NR_bind
	syscall_table[201] = voidptr(socket.syscall_listen) // __NR_listen
	syscall_table[202] = voidptr(socket.syscall_accept) // __NR_accept
	syscall_table[203] = voidptr(socket.syscall_connect) // __NR_connect
	syscall_table[204] = voidptr(syscall_linux_getsockname) // __NR_getsockname
	syscall_table[205] = voidptr(socket.syscall_getpeername) // __NR_getpeername
	syscall_table[206] = voidptr(syscall_linux_sendto) // __NR_sendto
	syscall_table[207] = voidptr(syscall_linux_recvfrom) // __NR_recvfrom
	syscall_table[208] = voidptr(syscall_linux_setsockopt) // __NR_setsockopt
	syscall_table[209] = voidptr(syscall_linux_getsockopt) // __NR_getsockopt
	syscall_table[210] = voidptr(syscall_linux_shutdown) // __NR_shutdown
	syscall_table[211] = voidptr(syscall_linux_sendmsg) // __NR_sendmsg
	syscall_table[212] = voidptr(socket.syscall_recvmsg) // __NR_recvmsg

	// Memory
	syscall_table[214] = voidptr(syscall_linux_brk) // __NR_brk
	syscall_table[215] = voidptr(mmap.syscall_munmap) // __NR_munmap
	syscall_table[220] = voidptr(syscall_linux_clone) // __NR_clone
	syscall_table[221] = voidptr(userland.syscall_execve) // __NR_execve
	syscall_table[222] = voidptr(syscall_linux_mmap) // __NR_mmap
	syscall_table[226] = voidptr(mmap.syscall_mprotect) // __NR_mprotect
	syscall_table[233] = voidptr(syscall_linux_madvise) // __NR_madvise

	// Misc
	syscall_table[260] = voidptr(userland.syscall_waitpid) // __NR_wait4
	syscall_table[261] = voidptr(syscall_linux_prlimit64) // __NR_prlimit64

	// Networking
	syscall_table[161] = voidptr(net.syscall_gethostname) // __NR_sethostname (close enough)
	syscall_table[162] = voidptr(net.syscall_sethostname) // __NR_setdomainname → sethostname

	// TLS — on aarch64 musl sets TPIDR_EL0 directly, but keep Vinix's
	// set_tls available at a high slot for mlibc compat
	syscall_table[291] = voidptr(cpu.syscall_set_tls) // Vinix extension
	syscall_table[292] = voidptr(userland.syscall_sigentry) // Vinix extension
}
