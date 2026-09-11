// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module table

// Linux x86-64 syscall dispatch used by unmodified Alpine/musl executables.
// The original Vinix table remains available to the mlibc amd64 userland;
// syscall_entry selects this table only for a process marked by exec.

import errno
import file
import fs
import memory.mmap
import net
import pipe
import proc
import socket
import stat
import time.sys
import usercopy
import userland
import x86.msr
import krandom

const linux_syscall_max = 512

__global (
	linux_syscall_table [linux_syscall_max]voidptr
)

fn syscall_linux_vacant(_ voidptr) (u64, u64) {
	return errno.err, errno.enosys
}

fn syscall_linux_open(gpr_state voidptr, path charptr, flags int, mode u32) (u64, u64) {
	return fs.syscall_openat(gpr_state, fs.at_fdcwd, path, flags, mode)
}

fn syscall_linux_stat(gpr_state voidptr, path charptr, buf &stat.Stat) (u64, u64) {
	return fs.syscall_fstatat(gpr_state, fs.at_fdcwd, path, buf, 0)
}

fn syscall_linux_lstat(gpr_state voidptr, path charptr, buf &stat.Stat) (u64, u64) {
	return fs.syscall_fstatat(gpr_state, fs.at_fdcwd, path, buf, fs.at_symlink_nofollow)
}

fn syscall_linux_access(gpr_state voidptr, path charptr, mode u32) (u64, u64) {
	return fs.syscall_faccessat(gpr_state, fs.at_fdcwd, path, mode, 0)
}

fn syscall_linux_inotify_init(gpr_state voidptr) (u64, u64) {
	return fs.syscall_inotify_init(gpr_state, 0)
}

fn syscall_linux_faccessat(gpr_state voidptr, dirfd int, path charptr, mode u32) (u64, u64) {
	return fs.syscall_faccessat(gpr_state, dirfd, path, mode, 0)
}

fn syscall_linux_mmap(gpr_state voidptr, addr voidptr, length u64, prot int, flags int, fdnum int, offset i64) (u64, u64) {
	packed := (u64(u32(prot)) << 32) | u64(u32(flags))
	return file.syscall_mmap(gpr_state, addr, length, packed, fdnum, offset)
}

struct LinuxIOVec {
	base u64
	len  u64
}

fn syscall_linux_writev(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int) (u64, u64) {
	if iovcnt < 0 || iovcnt > 1024 {
		return errno.err, errno.einval
	}
	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		mut iov := LinuxIOVec{}
		if !usercopy.copy_from_user(voidptr(&iov), iov_ptr + u64(i) * sizeof(LinuxIOVec), sizeof(LinuxIOVec)) {
			return errno.err, errno.efault
		}
		if iov.len > u64(0x7fffffffffffffff) - total {
			return errno.err, errno.einval
		}
		total += iov.len
	}
	if total == 0 {
		return fs.syscall_write(gpr_state, fdnum, unsafe { nil }, 0)
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
		mut iov := LinuxIOVec{}
		if !usercopy.copy_from_user(voidptr(&iov), iov_ptr + u64(i) * sizeof(LinuxIOVec), sizeof(LinuxIOVec)) {
			return errno.err, errno.efault
		}
		if iov.len != 0
			&& !usercopy.copy_from_user(voidptr(u64(buffer) + offset), iov.base, iov.len) {
			return errno.err, errno.efault
		}
		offset += iov.len
	}
	return fs.syscall_write(gpr_state, fdnum, buffer, total)
}

fn syscall_linux_readv(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int) (u64, u64) {
	if iovcnt < 0 || iovcnt > 1024 {
		return errno.err, errno.einval
	}
	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		mut iov := LinuxIOVec{}
		if !usercopy.copy_from_user(voidptr(&iov), iov_ptr + u64(i) * sizeof(LinuxIOVec), sizeof(LinuxIOVec)) {
			return errno.err, errno.efault
		}
		ret, err := fs.syscall_read(gpr_state, fdnum, voidptr(iov.base), iov.len)
		if err != 0 {
			return if total != 0 { total, u64(0) } else { ret, err }
		}
		total += ret
		if ret < iov.len {
			break
		}
	}
	return total, 0
}

fn syscall_linux_dup(gpr_state voidptr, oldfd int) (u64, u64) {
	return file.syscall_fcntl(gpr_state, oldfd, 0, 0)
}

fn syscall_linux_dup2(gpr_state voidptr, oldfd int, newfd int) (u64, u64) {
	if oldfd == newfd {
		mut fd := file.fd_from_fdnum(unsafe { nil }, oldfd) or {
			return errno.err, errno.get()
		}
		fd.unref()
		return u64(newfd), 0
	}
	return file.syscall_dup3(gpr_state, oldfd, newfd, 0)
}

fn syscall_linux_pipe(gpr_state voidptr, pipefds &int) (u64, u64) {
	return pipe.syscall_pipe(gpr_state, pipefds, 0)
}

fn syscall_linux_arch_prctl(_ voidptr, code int, address u64) (u64, u64) {
	match code {
		0x1002 { // ARCH_SET_FS
			mut current_thread := proc.current_thread()
			current_thread.fs_base = address
			msr.wrmsr(0xc0000100, address)
			return 0, 0
		}
		0x1003 { // ARCH_GET_FS
			value := msr.rdmsr(0xc0000100)
			if !usercopy.copy_to_user(address, voidptr(&value), sizeof(u64)) {
				return errno.err, errno.efault
			}
			return 0, 0
		}
		else {
			return errno.err, errno.einval
		}
	}
}

fn syscall_linux_set_tid_address(_ voidptr, _address u64) (u64, u64) {
	current_thread := proc.current_thread()
	return u64(if current_thread.tid == 0 { current_thread.process.pid } else { current_thread.tid }), 0
}

fn syscall_linux_set_robust_list(_ voidptr, _head u64, len u64) (u64, u64) {
	if len != 24 {
		return errno.err, errno.einval
	}
	return 0, 0
}

fn syscall_linux_rseq(_ voidptr) (u64, u64) {
	// musl treats ENOSYS as a kernel without restartable-sequence support.
	return errno.err, errno.enosys
}

fn syscall_linux_rt_sigaction(gpr_state voidptr, signum int, act_ptr u64, oldact_ptr u64, sigsetsize u64) (u64, u64) {
	if sigsetsize != 8 {
		return errno.err, errno.einval
	}
	mut incoming := proc.SigAction{}
	mut old := proc.SigAction{}
	mut raw := [4]u64{}
	if act_ptr != 0 {
		if !usercopy.copy_from_user(voidptr(&raw[0]), act_ptr, 32) {
			return errno.err, errno.efault
		}
		incoming = proc.SigAction{
			sa_sigaction: voidptr(raw[0])
			sa_flags: int(raw[1])
			sa_restorer: voidptr(raw[2])
			sa_mask: raw[3]
		}
	}
	mut incoming_arg := &proc.SigAction(unsafe { nil })
	mut old_arg := &proc.SigAction(unsafe { nil })
	if act_ptr != 0 {
		incoming_arg = &incoming
	}
	if oldact_ptr != 0 {
		old_arg = &old
	}
	ret, err := userland.syscall_sigaction(gpr_state, signum, incoming_arg, old_arg)
	if err != 0 {
		return ret, err
	}
	if oldact_ptr != 0 {
		raw[0] = u64(old.sa_sigaction)
		raw[1] = u64(u32(old.sa_flags))
		raw[2] = u64(old.sa_restorer)
		raw[3] = old.sa_mask
		if !usercopy.copy_to_user(oldact_ptr, voidptr(&raw[0]), 32) {
			return errno.err, errno.efault
		}
	}
	return 0, 0
}

fn syscall_linux_rt_sigprocmask(gpr_state voidptr, how int, set_ptr u64, oldset_ptr u64, sigsetsize u64) (u64, u64) {
	if sigsetsize != 8 {
		return errno.err, errno.einval
	}
	mut set_arg := &u64(unsafe { nil })
	mut oldset_arg := &u64(unsafe { nil })
	if set_ptr != 0 {
		set_arg = unsafe { &u64(set_ptr) }
	}
	if oldset_ptr != 0 {
		oldset_arg = unsafe { &u64(oldset_ptr) }
	}
	return userland.syscall_sigprocmask(gpr_state, how, set_arg, oldset_arg)
}

fn syscall_linux_wait4(gpr_state voidptr, pid int, status &int, options int, _rusage u64) (u64, u64) {
	return userland.syscall_waitpid(gpr_state, pid, status, options)
}

fn syscall_linux_uname(_ voidptr, buf u64) (u64, u64) {
	if buf == 0 {
		return errno.err, errno.efault
	}
	mut uts := [390]u8{}
	unsafe {
		C.strcpy(charptr(&uts[0]), c'Vinix')
		C.strcpy(charptr(&uts[65]), c'vinix')
		C.strcpy(charptr(&uts[130]), c'0.1.0')
		C.strcpy(charptr(&uts[195]), c'Vinix 0.1.0 amd64')
		C.strcpy(charptr(&uts[260]), c'x86_64')
	}
	net.copy_hostname(u64(&uts[65]))
	net.copy_domainname(u64(&uts[325]))
	if !usercopy.copy_to_user(buf, voidptr(&uts[0]), u64(uts.len)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn syscall_linux_getuid(_ voidptr) (u64, u64) {
	return u64(proc.current_thread().process.uid), 0
}

fn syscall_linux_getgid(_ voidptr) (u64, u64) {
	return u64(proc.current_thread().process.gid), 0
}

fn syscall_linux_geteuid(_ voidptr) (u64, u64) {
	return u64(proc.current_thread().process.euid), 0
}

fn syscall_linux_getegid(_ voidptr) (u64, u64) {
	return u64(proc.current_thread().process.egid), 0
}

fn syscall_linux_gettid(_ voidptr) (u64, u64) {
	current_thread := proc.current_thread()
	return u64(if current_thread.tid == 0 { current_thread.process.pid } else { current_thread.tid }), 0
}

fn syscall_linux_prlimit64(_ voidptr, pid int, resource int, new_limit u64, old_limit u64) (u64, u64) {
	mut process := proc.current_thread().process
	if pid != 0 && pid != process.pid {
		return errno.err, errno.esrch
	}
	if resource != proc.rlimit_nofile {
		return errno.err, errno.einval
	}
	process.fds_lock.acquire()
	defer { process.fds_lock.release() }
	old := process.rlimits[resource]
	if old_limit != 0 {
		if !usercopy.copy_to_user(old_limit, voidptr(&old), sizeof(proc.RLimit)) {
			return errno.err, errno.efault
		}
	}
	if new_limit != 0 {
		mut requested := proc.RLimit{}
		if !usercopy.copy_from_user(voidptr(&requested), new_limit, sizeof(proc.RLimit)) {
			return errno.err, errno.efault
		}
		if requested.cur > requested.max {
			return errno.err, errno.einval
		}
		if requested.max > old.max && process.euid != 0 {
			return errno.err, errno.eperm
		}
		if requested.max > u64(proc.max_fds) {
			return errno.err, errno.eperm
		}
		process.rlimits[resource] = requested
	}
	return 0, 0
}

fn syscall_linux_getrandom(_ voidptr, buf u64, count u64, flags u32) (u64, u64) {
	if flags & ~u32(7) != 0 {
		return errno.err, errno.einval
	}
	if count == 0 {
		return 0, 0
	}
	if buf == 0 {
		return errno.err, errno.efault
	}
	allow_insecure := flags & u32(4) != 0
	if !krandom.is_ready() && !allow_insecure {
		return errno.err, errno.eagain
	}
	mut bounce := [256]u8{}
	mut written := u64(0)
	for written < count {
		mut amount := count - written
		if amount > bounce.len {
			amount = u64(bounce.len)
		}
		if !krandom.fill(&bounce[0], amount, allow_insecure) {
			return errno.err, errno.eagain
		}
		if !usercopy.copy_to_user(buf + written, voidptr(&bounce[0]), amount) {
			if written != 0 {
				return written, 0
			}
			return errno.err, errno.efault
		}
		written += amount
	}
	unsafe { C.memset(&bounce[0], 0, sizeof(bounce)) }
	return written, 0
}

fn syscall_linux_mkdir(gpr_state voidptr, path charptr, mode u32) (u64, u64) {
	return fs.syscall_mkdirat(gpr_state, fs.at_fdcwd, path, mode)
}

fn syscall_linux_rmdir(gpr_state voidptr, path charptr) (u64, u64) {
	return fs.syscall_unlinkat(gpr_state, fs.at_fdcwd, path, fs.at_removedir)
}

fn syscall_linux_unlink(gpr_state voidptr, path charptr) (u64, u64) {
	return fs.syscall_unlinkat(gpr_state, fs.at_fdcwd, path, 0)
}

fn syscall_linux_readlink(gpr_state voidptr, path charptr, buf voidptr, size u64) (u64, u64) {
	return fs.syscall_readlinkat(gpr_state, fs.at_fdcwd, path, buf, size)
}

fn syscall_linux_exit_group(gpr_state voidptr, status int) {
	userland.syscall_exit(gpr_state, status)
}

fn syscall_linux_getdents64(gpr_state voidptr, fdnum int, dirp u64, count u64) (u64, u64) {
	mut offset := u64(0)
	for offset + 20 <= count {
		mut dirent := stat.Dirent{}
		ret, err := fs.syscall_readdir(gpr_state, fdnum, mut &dirent)
		if err != 0 {
			return if offset != 0 { offset, u64(0) } else { ret, err }
		}
		if ret == errno.err {
			break
		}
		mut name_len := u64(0)
		for name_len < 1024 && dirent.name[name_len] != 0 {
			name_len++
		}
		reclen := (u64(20) + name_len + 7) & ~u64(7)
		if offset + reclen > count {
			fs.readdir_unread(fdnum)
			break
		}
		mut record := []u8{len: int(reclen)}
		unsafe {
			*&u64(&record[0]) = dirent.ino
			*&u64(&record[8]) = dirent.off
			*&u16(&record[16]) = u16(reclen)
			record[18] = dirent.@type
			C.memcpy(voidptr(&record[19]), &dirent.name[0], name_len + 1)
		}
		if !usercopy.copy_to_user(dirp + offset, unsafe { voidptr(&record[0]) }, reclen) {
			unsafe { record.free() }
			return errno.err, errno.efault
		}
		unsafe { record.free() }
		offset += reclen
	}
	return offset, 0
}

pub fn init_linux_syscall_table() {
	for i := 0; i < linux_syscall_max; i++ {
		linux_syscall_table[i] = voidptr(syscall_linux_vacant)
	}

	linux_syscall_table[0] = voidptr(fs.syscall_read)
	linux_syscall_table[1] = voidptr(fs.syscall_write)
	linux_syscall_table[2] = voidptr(syscall_linux_open)
	linux_syscall_table[3] = voidptr(fs.syscall_close)
	linux_syscall_table[4] = voidptr(syscall_linux_stat)
	linux_syscall_table[5] = voidptr(fs.syscall_fstat)
	linux_syscall_table[6] = voidptr(syscall_linux_lstat)
	linux_syscall_table[8] = voidptr(fs.syscall_seek)
	linux_syscall_table[9] = voidptr(syscall_linux_mmap)
	linux_syscall_table[10] = voidptr(mmap.syscall_mprotect)
	linux_syscall_table[11] = voidptr(mmap.syscall_munmap)
	linux_syscall_table[12] = voidptr(mmap.syscall_brk)
	linux_syscall_table[13] = voidptr(syscall_linux_rt_sigaction)
	linux_syscall_table[14] = voidptr(syscall_linux_rt_sigprocmask)
	linux_syscall_table[16] = voidptr(fs.syscall_ioctl)
	linux_syscall_table[17] = voidptr(file.syscall_pread)
	linux_syscall_table[18] = voidptr(file.syscall_pwrite)
	linux_syscall_table[19] = voidptr(syscall_linux_readv)
	linux_syscall_table[20] = voidptr(syscall_linux_writev)
	linux_syscall_table[21] = voidptr(syscall_linux_access)
	linux_syscall_table[22] = voidptr(syscall_linux_pipe)
	linux_syscall_table[25] = voidptr(mmap.syscall_mremap)
	linux_syscall_table[27] = voidptr(mmap.syscall_mincore)
	linux_syscall_table[28] = voidptr(mmap.syscall_madvise)
	linux_syscall_table[32] = voidptr(syscall_linux_dup)
	linux_syscall_table[33] = voidptr(syscall_linux_dup2)
	linux_syscall_table[35] = voidptr(sys.syscall_nanosleep)
	linux_syscall_table[39] = voidptr(userland.syscall_getpid)
	linux_syscall_table[41] = voidptr(socket.syscall_socket)
	linux_syscall_table[42] = voidptr(socket.syscall_connect)
	linux_syscall_table[43] = voidptr(socket.syscall_accept)
	linux_syscall_table[44] = voidptr(socket.syscall_sendto)
	linux_syscall_table[45] = voidptr(socket.syscall_recvfrom)
	linux_syscall_table[46] = voidptr(socket.syscall_sendmsg)
	linux_syscall_table[47] = voidptr(socket.syscall_recvmsg)
	linux_syscall_table[48] = voidptr(socket.syscall_shutdown)
	linux_syscall_table[49] = voidptr(socket.syscall_bind)
	linux_syscall_table[50] = voidptr(socket.syscall_listen)
	linux_syscall_table[51] = voidptr(socket.syscall_getsockname)
	linux_syscall_table[52] = voidptr(socket.syscall_getpeername)
	linux_syscall_table[53] = voidptr(socket.syscall_socketpair)
	linux_syscall_table[54] = voidptr(socket.syscall_setsockopt)
	linux_syscall_table[55] = voidptr(socket.syscall_getsockopt)
	linux_syscall_table[57] = voidptr(userland.syscall_fork)
	linux_syscall_table[58] = voidptr(userland.syscall_fork)
	linux_syscall_table[59] = voidptr(userland.syscall_execve)
	linux_syscall_table[60] = voidptr(userland.syscall_exit)
	linux_syscall_table[61] = voidptr(syscall_linux_wait4)
	linux_syscall_table[62] = voidptr(userland.syscall_kill)
	linux_syscall_table[63] = voidptr(syscall_linux_uname)
	linux_syscall_table[72] = voidptr(file.syscall_fcntl)
	linux_syscall_table[73] = voidptr(file.syscall_flock)
	linux_syscall_table[74] = voidptr(file.syscall_fsync)
	linux_syscall_table[77] = voidptr(file.syscall_ftruncate)
	linux_syscall_table[79] = voidptr(fs.syscall_getcwd)
	linux_syscall_table[80] = voidptr(fs.syscall_chdir)
	linux_syscall_table[81] = voidptr(fs.syscall_fchdir)
	linux_syscall_table[83] = voidptr(syscall_linux_mkdir)
	linux_syscall_table[84] = voidptr(syscall_linux_rmdir)
	linux_syscall_table[87] = voidptr(syscall_linux_unlink)
	linux_syscall_table[89] = voidptr(syscall_linux_readlink)
	linux_syscall_table[91] = voidptr(fs.syscall_fchmod)
	linux_syscall_table[95] = voidptr(fs.syscall_umask)
	linux_syscall_table[96] = voidptr(sys.syscall_gettimeofday)
	linux_syscall_table[98] = voidptr(sys.syscall_getrusage)
	linux_syscall_table[99] = voidptr(sys.syscall_sysinfo)
	linux_syscall_table[102] = voidptr(syscall_linux_getuid)
	linux_syscall_table[104] = voidptr(syscall_linux_getgid)
	linux_syscall_table[107] = voidptr(syscall_linux_geteuid)
	linux_syscall_table[108] = voidptr(syscall_linux_getegid)
	linux_syscall_table[110] = voidptr(userland.syscall_getppid)
	linux_syscall_table[112] = voidptr(userland.syscall_setsid)
	linux_syscall_table[137] = voidptr(fs.syscall_statfs)
	linux_syscall_table[138] = voidptr(fs.syscall_fstatfs)
	linux_syscall_table[158] = voidptr(syscall_linux_arch_prctl)
	linux_syscall_table[186] = voidptr(syscall_linux_gettid)
	linux_syscall_table[217] = voidptr(syscall_linux_getdents64)
	linux_syscall_table[218] = voidptr(syscall_linux_set_tid_address)
	linux_syscall_table[228] = voidptr(sys.syscall_clock_gettime)
	linux_syscall_table[229] = voidptr(sys.syscall_clock_getres)
	linux_syscall_table[230] = voidptr(sys.syscall_clock_nanosleep)
	linux_syscall_table[231] = voidptr(syscall_linux_exit_group)
	linux_syscall_table[253] = voidptr(syscall_linux_inotify_init)
	linux_syscall_table[254] = voidptr(fs.syscall_inotify_add_watch)
	linux_syscall_table[255] = voidptr(fs.syscall_inotify_rm_watch)
	linux_syscall_table[257] = voidptr(fs.syscall_openat)
	linux_syscall_table[262] = voidptr(fs.syscall_fstatat)
	linux_syscall_table[269] = voidptr(syscall_linux_faccessat)
	linux_syscall_table[273] = voidptr(syscall_linux_set_robust_list)
	linux_syscall_table[280] = voidptr(fs.syscall_utimensat)
	linux_syscall_table[293] = voidptr(pipe.syscall_pipe)
	linux_syscall_table[294] = voidptr(fs.syscall_inotify_init)
	linux_syscall_table[302] = voidptr(syscall_linux_prlimit64)
	linux_syscall_table[318] = voidptr(syscall_linux_getrandom)
	linux_syscall_table[334] = voidptr(syscall_linux_rseq)
	linux_syscall_table[439] = voidptr(fs.syscall_faccessat)
}
