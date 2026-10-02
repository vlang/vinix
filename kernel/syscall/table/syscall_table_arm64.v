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
import security
import stat
import aarch64.cpu.local as cpulocal
import aarch64.uart
import sysvshm
import sysvsem
import sysvmsg
import krandom

// Linux aarch64 syscall numbers (from asm-generic/unistd.h).
// Table size covers all syscalls we map (max used = 441, epoll_pwait2).
// Keep in sync with the bounds check in asm/aarch64/vectors.S.
const linux_syscall_max = 512

@[export: 'syscall_table']
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

// The table slot of the stand-in for a call a seccomp filter turned away.
const seccomp_verdict_nr = u64(511)

// Returns what the call a seccomp filter turned away returns.
fn syscall_seccomp_verdict(_ voidptr) (u64, u64) {
	e := proc.current_thread().seccomp_errno
	if e == 0 {
		return 0, 0
	}
	return errno.err, e
}

// What a call runs as once the process's seccomp filters have seen it: the
// call itself, or the stand-in returning their verdict. A call is killed
// here with SIGSYS when that is the verdict.
fn seccomp_entry(mut t proc.Thread, gpr &cpulocal.GPRState, nr u64) u64 {
	process := t.process
	if process.seccomp_mode == proc.seccomp_mode_strict {
		// read, write, exit and rt_sigreturn are all strict mode allows.
		if nr == 63 || nr == 64 || nr == 93 || nr == 139 {
			return nr
		}
		security.audit_seccomp(nr, gpr.pc, proc.seccomp_ret_kill_process)
		userland.exit_with_fatal_signal(u8(9))
		return seccomp_verdict_nr
	}
	verdict := proc.seccomp_verdict(process.seccomp, nr, gpr.pc, [gpr.x0, gpr.x1, gpr.x2, gpr.x3,
		gpr.x4, gpr.x5]!)
	if verdict & proc.seccomp_ret_action_full != proc.seccomp_ret_allow {
		t.audit_sequence = security.audit_seccomp(nr, gpr.pc, verdict)
	}
	match verdict & proc.seccomp_ret_action_full {
		proc.seccomp_ret_allow, proc.seccomp_ret_log {
			return nr
		}
		proc.seccomp_ret_errno {
			mut e := u64(verdict & proc.seccomp_ret_data)
			if e > 4095 {
				e = 4095
			}
			t.seccomp_errno = e
			return seccomp_verdict_nr
		}
		proc.seccomp_ret_trap {
			userland.sendsig(t, u8(31))
			t.seccomp_errno = errno.enosys
			return seccomp_verdict_nr
		}
		proc.seccomp_ret_trace, proc.seccomp_ret_user_notif {
			// No tracer and no listener: Linux fails the call with ENOSYS.
			t.seccomp_errno = errno.enosys
			return seccomp_verdict_nr
		}
		else {
			userland.exit_with_fatal_signal(u8(31))
			return seccomp_verdict_nr
		}
	}
}

// Called on every syscall's way in. Answers the table slot to run.
@[export: 'syscall_trace']
pub fn syscall_trace(gpr_state voidptr) u64 {
	proc.cpu_enter_kernel()
	gpr := unsafe { &cpulocal.GPRState(gpr_state) }
	nr := gpr.x8
	// A busy userspace workload can keep the HVF scheduler out of its normal
	// idle polling loop. This throttled, input-only call keeps the desktop
	// responsive while translated applications occupy every virtual CPU.
	sched.poll_syscall_input()
	mut current_thread := proc.current_thread()
	current_thread.audit_sequence = 0
	current_thread.syscall_x0 = gpr.x0
	current_thread.syscall_nr = i64(nr)
	current_thread.syscall_x1 = gpr.x1
	current_thread.syscall_x2 = gpr.x2
	current_thread.syscall_x3 = gpr.x3
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
	if current_thread.process.seccomp_mode != proc.seccomp_mode_disabled {
		slot := seccomp_entry(mut current_thread, gpr, nr)
		if slot != nr {
			return slot
		}
	}
	if current_thread.process.pledge != 0 {
		return pledge_entry(mut current_thread, gpr, nr)
	}
	return nr
}

@[export: 'syscall_trace_ret']
pub fn syscall_trace_ret(ret u64, err u64) {
	mut current_thread := proc.current_thread()
	security.audit_complete(current_thread.audit_sequence, ret, err)
	current_thread.audit_sequence = 0
	current_thread.syscall_nr = -1
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

// Linux getdents64(fd, dirp, count) — fill buffer with directory entries.
// Vinix readdir returns one entry at a time; we loop to fill the buffer.
fn syscall_linux_getdents64(gpr_state voidptr, fdnum int, dirp u64, count u64) (u64, u64) {
	// One synchronous scratch record per syscall, independent of directory size.
	mut dirent := unsafe { &stat.Dirent(C.__builtin_alloca(sizeof(stat.Dirent))) }
	mut offset := u64(0)
	for {
		unsafe { *dirent = stat.Dirent{} }
		ret, err := fs.syscall_readdir(gpr_state, fdnum, mut dirent)
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
			if offset == 0 { return errno.err, errno.einval }
			break
		}
		// Build the entry in a kernel buffer and copy it out, so a bad `dirp`
		// fails with EFAULT rather than faulting the kernel. reclen is bounded
		// by the 1024-byte name limit above.
		mut record := [1064]u8{}
		unsafe {
			*&u64(&record[0]) = dirent.ino
			*&u64(&record[8]) = dirent.off
			*&u16(&record[16]) = u16(reclen)
			record[18] = dirent.@type
			C.memcpy(voidptr(&record[19]), &dirent.name[0], name_len + 1)
		}
		if !usercopy.copy_to_user(dirp + offset, unsafe { voidptr(&record[0]) }, reclen) {
			if offset > 0 {
				return offset, 0
			}
			return errno.err, errno.efault
		}
		offset += reclen
	}
	return offset, 0
}

// Linux uname(buf); see linux_uname().
fn syscall_linux_uname(_ voidptr, buf u64) (u64, u64) {
	return linux_uname(buf, c'Vinix 0.1.0 aarch64', c'aarch64')
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

// Convert Vinix stat.Stat (144 bytes, x86_64 layout) to Linux aarch64 struct stat (128 bytes).
// Field order and sizes differ: mode/nlink are swapped and narrower on aarch64, blksize is i32.
fn convert_stat_to_linux(src &stat.Stat, user_dst u64) bool {
	mut buf := [128]u8{}
	dst := unsafe { u64(&buf[0]) }
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
	return usercopy.copy_to_user(user_dst, unsafe { voidptr(&buf[0]) }, u64(sizeof(buf)))
}

// fstatat wrapper: call Vinix fstatat with a local buffer, then convert to Linux layout.
fn syscall_linux_fstatat(gpr_state voidptr, dirfd int, path charptr, linux_buf u64, flags int) (u64, u64) {
	// Neither the filesystem fill nor the checked conversion retains this scratch.
	stat_storage := unsafe { &stat.Stat(C.vinix_stack_alloc(sizeof(stat.Stat))) }
	unsafe { *stat_storage = stat.Stat{} }
	ret, err := fs.syscall_fstatat(gpr_state, dirfd, path, stat_storage, flags)
	if err != 0 {
		return ret, err
	}
	if !convert_stat_to_linux(stat_storage, linux_buf) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// fstat wrapper: call Vinix fstat with a local buffer, then convert to Linux layout.
fn syscall_linux_fstat(gpr_state voidptr, fdnum int, linux_buf u64) (u64, u64) {
	// Neither the filesystem fill nor the checked conversion retains this scratch.
	stat_storage := unsafe { &stat.Stat(C.vinix_stack_alloc(sizeof(stat.Stat))) }
	unsafe { *stat_storage = stat.Stat{} }
	ret, err := fs.syscall_fstat(gpr_state, fdnum, stat_storage)
	if err != 0 {
		return ret, err
	}
	if !convert_stat_to_linux(stat_storage, linux_buf) {
		return errno.err, errno.efault
	}
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
	syscall_table[5] = voidptr(fs.syscall_setxattr) // __NR_setxattr
	syscall_table[6] = voidptr(fs.syscall_lsetxattr) // __NR_lsetxattr
	syscall_table[7] = voidptr(fs.syscall_fsetxattr) // __NR_fsetxattr
	syscall_table[8] = voidptr(fs.syscall_getxattr) // __NR_getxattr
	syscall_table[9] = voidptr(fs.syscall_lgetxattr) // __NR_lgetxattr
	syscall_table[10] = voidptr(fs.syscall_fgetxattr) // __NR_fgetxattr
	syscall_table[11] = voidptr(fs.syscall_listxattr) // __NR_listxattr
	syscall_table[12] = voidptr(fs.syscall_llistxattr) // __NR_llistxattr
	syscall_table[13] = voidptr(fs.syscall_flistxattr) // __NR_flistxattr
	syscall_table[14] = voidptr(fs.syscall_removexattr) // __NR_removexattr
	syscall_table[15] = voidptr(fs.syscall_lremovexattr) // __NR_lremovexattr
	syscall_table[16] = voidptr(fs.syscall_fremovexattr) // __NR_fremovexattr
	syscall_table[17] = voidptr(fs.syscall_getcwd) // __NR_getcwd
	syscall_table[seccomp_verdict_nr] = voidptr(syscall_seccomp_verdict)
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
	syscall_table[56] = voidptr(syscall_linux_openat) // __NR_openat
	syscall_table[57] = voidptr(fs.syscall_close) // __NR_close
	syscall_table[59] = voidptr(pipe.syscall_pipe_checked) // __NR_pipe2
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
	syscall_table[74] = voidptr(userland.syscall_signalfd4) // __NR_signalfd4
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
	syscall_table[269] = voidptr(syscall_linux_sendmmsg) // __NR_sendmmsg
	syscall_table[279] = voidptr(fs.syscall_memfd_create) // __NR_memfd_create
	syscall_table[280] = voidptr(syscall_linux_bpf) // __NR_bpf
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
	syscall_table[274] = voidptr(syscall_linux_sched_setattr) // __NR_sched_setattr
	syscall_table[275] = voidptr(syscall_linux_sched_getattr) // __NR_sched_getattr
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
	syscall_table[270] = voidptr(syscall_linux_process_vm_readv) // process_vm_readv
	syscall_table[271] = voidptr(syscall_linux_process_vm_writev) // process_vm_writev
	syscall_table[38] = voidptr(fs.syscall_renameat) // __NR_renameat
	syscall_table[276] = voidptr(fs.syscall_renameat2) // __NR_renameat2
	syscall_table[43] = voidptr(fs.syscall_statfs) // __NR_statfs
	syscall_table[44] = voidptr(fs.syscall_fstatfs) // __NR_fstatfs
	syscall_table[45] = voidptr(fs.syscall_truncate) // __NR_truncate
	syscall_table[278] = voidptr(syscall_linux_getrandom) // __NR_getrandom
	syscall_table[435] = voidptr(userland.syscall_clone3) // __NR_clone3
	syscall_table[424] = voidptr(userland.syscall_pidfd_send_signal)
	syscall_table[434] = voidptr(userland.syscall_pidfd_open)
	syscall_table[223] = voidptr(file.syscall_fadvise64) // __NR_fadvise64

	// Sockets
	syscall_table[198] = voidptr(socket.syscall_socket) // __NR_socket
	syscall_table[199] = voidptr(socket.syscall_socketpair) // __NR_socketpair
	syscall_table[200] = voidptr(socket.syscall_bind) // __NR_bind
	syscall_table[201] = voidptr(socket.syscall_listen) // __NR_listen
	syscall_table[202] = voidptr(syscall_linux_accept) // __NR_accept
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
	syscall_table[243] = voidptr(syscall_linux_recvmmsg) // __NR_recvmmsg

	// Memory
	syscall_table[194] = voidptr(sysvshm.syscall_shmget) // __NR_shmget
	syscall_table[190] = voidptr(sysvsem.syscall_semget) // __NR_semget
	syscall_table[186] = voidptr(sysvmsg.syscall_msgget)
	syscall_table[187] = voidptr(sysvmsg.syscall_msgctl)
	syscall_table[188] = voidptr(sysvmsg.syscall_msgrcv)
	syscall_table[189] = voidptr(sysvmsg.syscall_msgsnd)
	syscall_table[191] = voidptr(sysvsem.syscall_semctl) // __NR_semctl
	syscall_table[192] = voidptr(sysvsem.syscall_semtimedop) // __NR_semtimedop
	syscall_table[193] = voidptr(sysvsem.syscall_semop) // __NR_semop
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
