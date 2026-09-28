// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module table

// Linux x86-64 syscall dispatch used by unmodified Alpine/musl executables.
// The original Vinix table remains available to the mlibc amd64 userland;
// syscall_entry selects this table only for a process marked by exec.
//
// It covers what the arm64 table does, with the same handlers wherever the
// ABI agrees -- the wrappers shared between the two live in linux_common.v,
// linux_compat.v, gaps.v and container.v -- plus the calls x86-64 kept from
// before the *at() family: open, stat, rename, chmod, select and the like,
// which musl, BusyBox and Python still make here.

import errno
import file
import fs
import memory.mmap
import numa
import net
import pipe
import posixtimer
import proc
import resource
import sched
import socket
import stat
import sysvsem
import sysvshm
import time
import time.sys
import usercopy
import userland
import x86.msr

const linux_syscall_max = 512

@[export: 'linux_syscall_table']
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

fn syscall_linux_mmap(gpr_state voidptr, addr voidptr, length u64, prot int, flags int, fdnum int, offset i64) (u64, u64) {
	packed := (u64(u32(prot)) << 32) | u64(u32(flags))
	return file.syscall_mmap(gpr_state, addr, length, packed, fdnum, offset)
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

fn syscall_linux_pipe(gpr_state voidptr, pipefds &i32) (u64, u64) {
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
			sa_mask: userland.linux_mask_to_vinix(raw[3])
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
		raw[3] = userland.vinix_mask_to_linux(old.sa_mask)
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
	// Linux spells SIG_BLOCK, SIG_UNBLOCK and SIG_SETMASK 0, 1 and 2; the
	// native handler takes mlibc's 1, 2 and 3. Passed through unchanged, a
	// Linux SIG_BLOCK did nothing, SIG_UNBLOCK blocked and SIG_SETMASK
	// unblocked: pthread_sigmask() and sigprocmask() never blocked anything,
	// and a signal a program meant to take with sigwait() killed it instead.
	native_how := match how {
		0 { userland.sig_block }
		1 { userland.sig_unblock }
		2 { userland.sig_setmask }
		else { -1 }
	}
	if set_ptr != 0 && native_how < 0 {
		return errno.err, errno.einval
	}
	// Linux numbers signal n as bit n-1; the kernel's masks use bit n.
	mut set := u64(0)
	mut oldset := u64(0)
	mut set_arg := &u64(unsafe { nil })
	if set_ptr != 0 {
		if !usercopy.copy_from_user(voidptr(&set), set_ptr, 8) {
			return errno.err, errno.efault
		}
		// SIGKILL and SIGSTOP cannot be blocked; Linux drops them silently.
		set = userland.linux_mask_to_vinix(set) & ~((u64(1) << 9) | (u64(1) << 19))
		set_arg = &set
	}
	ret, err := userland.syscall_sigprocmask(gpr_state, native_how, set_arg, &oldset)
	if err != 0 {
		return ret, err
	}
	if oldset_ptr != 0 {
		linux_old := userland.vinix_mask_to_linux(oldset)
		if !usercopy.copy_to_user(oldset_ptr, voidptr(&linux_old), 8) {
			return errno.err, errno.efault
		}
	}
	return 0, 0
}

// Linux uname(buf); see linux_uname().
fn syscall_linux_uname(_ voidptr, buf u64) (u64, u64) {
	return linux_uname(buf, c'Vinix 0.1.0 amd64', c'x86_64')
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

// ── the calls x86-64 kept from before the *at() family ─────────────────────

fn syscall_linux_rename(gpr_state voidptr, oldpath charptr, newpath charptr) (u64, u64) {
	return fs.syscall_renameat(gpr_state, fs.at_fdcwd, oldpath, fs.at_fdcwd, newpath)
}

fn syscall_linux_chmod(gpr_state voidptr, path charptr, mode u32) (u64, u64) {
	return fs.syscall_fchmodat(gpr_state, fs.at_fdcwd, path, mode)
}

// creat(path, mode) is open(path, O_CREAT | O_WRONLY | O_TRUNC, mode).
fn syscall_linux_creat(gpr_state voidptr, path charptr, mode u32) (u64, u64) {
	return fs.syscall_openat(gpr_state, fs.at_fdcwd, path, resource.o_creat | resource.o_wronly | resource.o_trunc,
		mode)
}

fn syscall_linux_link(gpr_state voidptr, oldpath charptr, newpath charptr) (u64, u64) {
	return fs.syscall_linkat(gpr_state, fs.at_fdcwd, oldpath, fs.at_fdcwd, newpath, 0)
}

fn syscall_linux_symlink(gpr_state voidptr, target charptr, linkpath charptr) (u64, u64) {
	return fs.syscall_symlinkat(gpr_state, target, fs.at_fdcwd, linkpath)
}

fn syscall_linux_chown(gpr_state voidptr, path charptr, uid u32, gid u32) (u64, u64) {
	return fs.syscall_fchownat(gpr_state, fs.at_fdcwd, path, uid, gid, 0)
}

fn syscall_linux_lchown(gpr_state voidptr, path charptr, uid u32, gid u32) (u64, u64) {
	return fs.syscall_fchownat(gpr_state, fs.at_fdcwd, path, uid, gid, fs.at_symlink_nofollow)
}

fn syscall_linux_mknod(gpr_state voidptr, path charptr, mode u32, dev u64) (u64, u64) {
	return fs.syscall_mknodat(gpr_state, fs.at_fdcwd, path, mode, dev)
}

fn syscall_linux_getpgrp(gpr_state voidptr) (u64, u64) {
	return syscall_linux_getpgid(gpr_state, 0)
}

// epoll_create(size): epoll_create1(0), once size has been checked. The size
// has been a hint only since Linux 2.6.8, but it still has to be positive.
fn syscall_linux_epoll_create(gpr_state voidptr, size int) (u64, u64) {
	if size <= 0 {
		return errno.err, errno.einval
	}
	return file.syscall_epoll_create1(gpr_state, 0)
}

fn syscall_linux_epoll_wait(gpr_state voidptr, epfd int, events u64, maxevents int, timeout int) (u64, u64) {
	return file.syscall_epoll_pwait(gpr_state, epfd, events, maxevents, timeout, 0, 0)
}

fn syscall_linux_eventfd(gpr_state voidptr, initial u32) (u64, u64) {
	return file.syscall_eventfd2(gpr_state, initial, 0)
}

// signalfd(fd, mask, sizemask): signalfd4 without flags.
fn syscall_linux_signalfd(gpr_state voidptr, fdnum int, mask_ptr u64, sizemask u64) (u64, u64) {
	return userland.syscall_signalfd4(gpr_state, fdnum, mask_ptr, sizemask, 0)
}

// time(tloc): the seconds of the realtime clock, stored at tloc as well when
// it is given.
fn syscall_linux_time(_ voidptr, tloc u64) (u64, u64) {
	now := time.clock_now(time.clock_type_realtime) or { return errno.err, errno.einval }
	seconds := now.tv_sec
	if tloc != 0 && !usercopy.copy_to_user(tloc, voidptr(&seconds), sizeof(i64)) {
		return errno.err, errno.efault
	}
	return u64(seconds), 0
}

// alarm(seconds): ITIMER_REAL without an interval. Answers the seconds that
// were left on the previous alarm, rounded up so that one still pending is
// never reported as none.
fn syscall_linux_alarm(_ voidptr, seconds u32) (u64, u64) {
	current_thread := proc.current_thread()
	old_value, _ := sched.set_itimer_real(current_thread, i64(seconds) * 1000000, 0)
	if old_value <= 0 {
		return 0, 0
	}
	return u64((old_value + 999999) / 1000000), 0
}

pub fn init_linux_syscall_table() {
	for i := 0; i < linux_syscall_max; i++ {
		linux_syscall_table[i] = voidptr(syscall_linux_vacant)
	}

	// Linux x86-64 syscall numbers → Vinix handlers.
	// Reference: arch/x86/entry/syscalls/syscall_64.tbl

	// File I/O
	linux_syscall_table[0] = voidptr(fs.syscall_read) // read
	linux_syscall_table[1] = voidptr(fs.syscall_write) // write
	linux_syscall_table[2] = voidptr(syscall_linux_open) // open
	linux_syscall_table[3] = voidptr(fs.syscall_close) // close
	linux_syscall_table[4] = voidptr(syscall_linux_stat) // stat
	linux_syscall_table[5] = voidptr(fs.syscall_fstat) // fstat
	linux_syscall_table[6] = voidptr(syscall_linux_lstat) // lstat
	linux_syscall_table[7] = voidptr(file.syscall_poll) // poll
	linux_syscall_table[8] = voidptr(fs.syscall_seek) // lseek
	linux_syscall_table[16] = voidptr(fs.syscall_ioctl) // ioctl
	linux_syscall_table[17] = voidptr(syscall_linux_pread64) // pread64
	linux_syscall_table[18] = voidptr(syscall_linux_pwrite64) // pwrite64
	linux_syscall_table[19] = voidptr(syscall_linux_readv) // readv
	linux_syscall_table[20] = voidptr(syscall_linux_writev) // writev
	linux_syscall_table[21] = voidptr(syscall_linux_access) // access
	linux_syscall_table[22] = voidptr(syscall_linux_pipe) // pipe
	linux_syscall_table[23] = voidptr(file.syscall_select) // select
	linux_syscall_table[32] = voidptr(syscall_linux_dup) // dup
	linux_syscall_table[33] = voidptr(syscall_linux_dup2) // dup2
	linux_syscall_table[40] = voidptr(syscall_linux_sendfile) // sendfile
	linux_syscall_table[72] = voidptr(file.syscall_fcntl) // fcntl
	linux_syscall_table[73] = voidptr(file.syscall_flock) // flock
	linux_syscall_table[74] = voidptr(file.syscall_fsync) // fsync
	linux_syscall_table[75] = voidptr(file.syscall_fsync) // fdatasync
	linux_syscall_table[76] = voidptr(fs.syscall_truncate) // truncate
	linux_syscall_table[77] = voidptr(file.syscall_ftruncate) // ftruncate
	linux_syscall_table[79] = voidptr(fs.syscall_getcwd) // getcwd
	linux_syscall_table[80] = voidptr(fs.syscall_chdir) // chdir
	linux_syscall_table[81] = voidptr(fs.syscall_fchdir) // fchdir
	linux_syscall_table[82] = voidptr(syscall_linux_rename) // rename
	linux_syscall_table[83] = voidptr(syscall_linux_mkdir) // mkdir
	linux_syscall_table[84] = voidptr(syscall_linux_rmdir) // rmdir
	linux_syscall_table[85] = voidptr(syscall_linux_creat) // creat
	linux_syscall_table[86] = voidptr(syscall_linux_link) // link
	linux_syscall_table[87] = voidptr(syscall_linux_unlink) // unlink
	linux_syscall_table[88] = voidptr(syscall_linux_symlink) // symlink
	linux_syscall_table[89] = voidptr(syscall_linux_readlink) // readlink
	linux_syscall_table[90] = voidptr(syscall_linux_chmod) // chmod
	linux_syscall_table[91] = voidptr(fs.syscall_fchmod) // fchmod
	linux_syscall_table[92] = voidptr(syscall_linux_chown) // chown
	linux_syscall_table[93] = voidptr(fs.syscall_fchown) // fchown
	linux_syscall_table[94] = voidptr(syscall_linux_lchown) // lchown
	linux_syscall_table[95] = voidptr(fs.syscall_umask) // umask
	linux_syscall_table[133] = voidptr(syscall_linux_mknod) // mknod
	linux_syscall_table[137] = voidptr(fs.syscall_statfs) // statfs
	linux_syscall_table[138] = voidptr(fs.syscall_fstatfs) // fstatfs
	linux_syscall_table[162] = voidptr(fs.syscall_sync) // sync
	linux_syscall_table[169] = voidptr(syscall_linux_reboot) // reboot
	linux_syscall_table[188] = voidptr(fs.syscall_setxattr) // setxattr
	linux_syscall_table[189] = voidptr(fs.syscall_lsetxattr) // lsetxattr
	linux_syscall_table[190] = voidptr(fs.syscall_fsetxattr) // fsetxattr
	linux_syscall_table[191] = voidptr(fs.syscall_getxattr) // getxattr
	linux_syscall_table[192] = voidptr(fs.syscall_lgetxattr) // lgetxattr
	linux_syscall_table[193] = voidptr(fs.syscall_fgetxattr) // fgetxattr
	linux_syscall_table[194] = voidptr(fs.syscall_listxattr) // listxattr
	linux_syscall_table[195] = voidptr(fs.syscall_llistxattr) // llistxattr
	linux_syscall_table[196] = voidptr(fs.syscall_flistxattr) // flistxattr
	linux_syscall_table[197] = voidptr(fs.syscall_removexattr) // removexattr
	linux_syscall_table[198] = voidptr(fs.syscall_lremovexattr) // lremovexattr
	linux_syscall_table[199] = voidptr(fs.syscall_fremovexattr) // fremovexattr
	linux_syscall_table[217] = voidptr(syscall_linux_getdents64) // getdents64
	linux_syscall_table[221] = voidptr(file.syscall_fadvise64) // fadvise64
	linux_syscall_table[253] = voidptr(syscall_linux_inotify_init) // inotify_init
	linux_syscall_table[254] = voidptr(fs.syscall_inotify_add_watch) // inotify_add_watch
	linux_syscall_table[255] = voidptr(fs.syscall_inotify_rm_watch) // inotify_rm_watch
	linux_syscall_table[257] = voidptr(syscall_linux_openat) // openat
	linux_syscall_table[258] = voidptr(fs.syscall_mkdirat) // mkdirat
	linux_syscall_table[259] = voidptr(fs.syscall_mknodat) // mknodat
	linux_syscall_table[260] = voidptr(fs.syscall_fchownat) // fchownat
	linux_syscall_table[262] = voidptr(fs.syscall_fstatat) // newfstatat
	linux_syscall_table[263] = voidptr(fs.syscall_unlinkat) // unlinkat
	linux_syscall_table[264] = voidptr(fs.syscall_renameat) // renameat
	linux_syscall_table[265] = voidptr(fs.syscall_linkat) // linkat
	linux_syscall_table[266] = voidptr(fs.syscall_symlinkat) // symlinkat
	linux_syscall_table[267] = voidptr(fs.syscall_readlinkat) // readlinkat
	linux_syscall_table[268] = voidptr(fs.syscall_fchmodat) // fchmodat
	linux_syscall_table[269] = voidptr(syscall_linux_faccessat) // faccessat
	linux_syscall_table[270] = voidptr(file.syscall_pselect6) // pselect6
	// The fifth argument, the signal set's size, is always 8 from musl.
	linux_syscall_table[271] = voidptr(file.syscall_ppoll) // ppoll
	linux_syscall_table[275] = voidptr(pipe.syscall_splice) // splice
	linux_syscall_table[276] = voidptr(pipe.syscall_tee) // tee
	linux_syscall_table[277] = voidptr(file.syscall_sync_file_range) // sync_file_range
	linux_syscall_table[278] = voidptr(pipe.syscall_vmsplice) // vmsplice
	linux_syscall_table[280] = voidptr(fs.syscall_utimensat) // utimensat
	linux_syscall_table[282] = voidptr(syscall_linux_signalfd) // signalfd
	linux_syscall_table[283] = voidptr(file.syscall_timerfd_create) // timerfd_create
	linux_syscall_table[284] = voidptr(syscall_linux_eventfd) // eventfd
	linux_syscall_table[285] = voidptr(file.syscall_fallocate) // fallocate
	linux_syscall_table[286] = voidptr(file.syscall_timerfd_settime) // timerfd_settime
	linux_syscall_table[287] = voidptr(file.syscall_timerfd_gettime) // timerfd_gettime
	linux_syscall_table[289] = voidptr(userland.syscall_signalfd4) // signalfd4
	linux_syscall_table[290] = voidptr(file.syscall_eventfd2) // eventfd2
	linux_syscall_table[292] = voidptr(file.syscall_dup3) // dup3
	linux_syscall_table[293] = voidptr(pipe.syscall_pipe_checked) // pipe2
	linux_syscall_table[294] = voidptr(fs.syscall_inotify_init) // inotify_init1
	linux_syscall_table[295] = voidptr(syscall_linux_preadv) // preadv
	linux_syscall_table[296] = voidptr(syscall_linux_pwritev) // pwritev
	linux_syscall_table[306] = voidptr(fs.syscall_syncfs) // syncfs
	linux_syscall_table[316] = voidptr(fs.syscall_renameat2) // renameat2
	linux_syscall_table[319] = voidptr(fs.syscall_memfd_create) // memfd_create
	linux_syscall_table[326] = voidptr(pipe.syscall_copy_file_range) // copy_file_range
	linux_syscall_table[327] = voidptr(syscall_linux_preadv2) // preadv2
	linux_syscall_table[328] = voidptr(syscall_linux_pwritev2) // pwritev2
	linux_syscall_table[332] = voidptr(syscall_linux_statx) // statx
	linux_syscall_table[436] = voidptr(file.syscall_close_range) // close_range
	linux_syscall_table[437] = voidptr(syscall_linux_openat2) // openat2
	linux_syscall_table[439] = voidptr(syscall_linux_faccessat2) // faccessat2

	// epoll
	linux_syscall_table[213] = voidptr(syscall_linux_epoll_create) // epoll_create
	linux_syscall_table[232] = voidptr(syscall_linux_epoll_wait) // epoll_wait
	linux_syscall_table[233] = voidptr(file.syscall_epoll_ctl) // epoll_ctl
	linux_syscall_table[281] = voidptr(file.syscall_epoll_pwait) // epoll_pwait
	linux_syscall_table[291] = voidptr(file.syscall_epoll_create1) // epoll_create1
	linux_syscall_table[441] = voidptr(file.syscall_epoll_pwait2) // epoll_pwait2

	// Memory
	linux_syscall_table[9] = voidptr(syscall_linux_mmap) // mmap
	linux_syscall_table[10] = voidptr(mmap.syscall_mprotect) // mprotect
	linux_syscall_table[11] = voidptr(mmap.syscall_munmap) // munmap
	linux_syscall_table[12] = voidptr(mmap.syscall_brk) // brk
	linux_syscall_table[25] = voidptr(mmap.syscall_mremap) // mremap
	linux_syscall_table[26] = voidptr(mmap.syscall_msync) // msync
	linux_syscall_table[27] = voidptr(mmap.syscall_mincore) // mincore
	linux_syscall_table[28] = voidptr(mmap.syscall_madvise) // madvise
	linux_syscall_table[29] = voidptr(sysvshm.syscall_shmget) // shmget
	linux_syscall_table[30] = voidptr(sysvshm.syscall_shmat) // shmat
	linux_syscall_table[31] = voidptr(sysvshm.syscall_shmctl) // shmctl
	linux_syscall_table[67] = voidptr(sysvshm.syscall_shmdt) // shmdt
	linux_syscall_table[64] = voidptr(sysvsem.syscall_semget) // semget
	linux_syscall_table[65] = voidptr(sysvsem.syscall_semop) // semop
	linux_syscall_table[66] = voidptr(sysvsem.syscall_semctl) // semctl
	linux_syscall_table[220] = voidptr(sysvsem.syscall_semtimedop) // semtimedop
	linux_syscall_table[149] = voidptr(syscall_linux_mlock) // mlock
	linux_syscall_table[150] = voidptr(syscall_linux_mlock) // munlock
	linux_syscall_table[151] = voidptr(syscall_linux_mlockall) // mlockall
	linux_syscall_table[152] = voidptr(syscall_linux_munlockall) // munlockall
	linux_syscall_table[237] = voidptr(numa.syscall_mbind) // mbind
	linux_syscall_table[238] = voidptr(numa.syscall_set_mempolicy) // set_mempolicy
	linux_syscall_table[239] = voidptr(numa.syscall_get_mempolicy) // get_mempolicy
	linux_syscall_table[324] = voidptr(syscall_linux_membarrier) // membarrier
	linux_syscall_table[325] = voidptr(syscall_linux_mlock2) // mlock2

	// Signals
	linux_syscall_table[13] = voidptr(syscall_linux_rt_sigaction) // rt_sigaction
	linux_syscall_table[14] = voidptr(syscall_linux_rt_sigprocmask) // rt_sigprocmask
	linux_syscall_table[15] = voidptr(userland.syscall_linux_rt_sigreturn) // rt_sigreturn
	linux_syscall_table[34] = voidptr(userland.syscall_pause) // pause
	linux_syscall_table[62] = voidptr(userland.syscall_kill) // kill
	linux_syscall_table[127] = voidptr(syscall_linux_rt_sigpending) // rt_sigpending
	linux_syscall_table[128] = voidptr(userland.syscall_rt_sigtimedwait) // rt_sigtimedwait
	linux_syscall_table[130] = voidptr(userland.syscall_linux_rt_sigsuspend) // rt_sigsuspend
	linux_syscall_table[131] = voidptr(userland.syscall_sigaltstack) // sigaltstack
	linux_syscall_table[200] = voidptr(userland.syscall_tkill) // tkill
	linux_syscall_table[234] = voidptr(userland.syscall_tgkill) // tgkill

	// Time
	linux_syscall_table[35] = voidptr(sys.syscall_nanosleep) // nanosleep
	linux_syscall_table[36] = voidptr(syscall_linux_getitimer) // getitimer
	linux_syscall_table[37] = voidptr(syscall_linux_alarm) // alarm
	linux_syscall_table[38] = voidptr(syscall_linux_setitimer) // setitimer
	linux_syscall_table[96] = voidptr(sys.syscall_gettimeofday) // gettimeofday
	linux_syscall_table[100] = voidptr(syscall_linux_times) // times
	linux_syscall_table[201] = voidptr(syscall_linux_time) // time
	linux_syscall_table[222] = voidptr(posixtimer.syscall_timer_create) // timer_create
	linux_syscall_table[223] = voidptr(posixtimer.syscall_timer_settime) // timer_settime
	linux_syscall_table[224] = voidptr(posixtimer.syscall_timer_gettime) // timer_gettime
	linux_syscall_table[225] = voidptr(posixtimer.syscall_timer_getoverrun) // timer_getoverrun
	linux_syscall_table[226] = voidptr(posixtimer.syscall_timer_delete) // timer_delete
	linux_syscall_table[228] = voidptr(sys.syscall_clock_gettime) // clock_gettime
	linux_syscall_table[229] = voidptr(sys.syscall_clock_getres) // clock_getres
	linux_syscall_table[230] = voidptr(sys.syscall_clock_nanosleep) // clock_nanosleep

	// Processes and threads
	linux_syscall_table[24] = voidptr(syscall_linux_sched_yield) // sched_yield
	linux_syscall_table[39] = voidptr(userland.syscall_getpid) // getpid
	linux_syscall_table[56] = voidptr(userland.syscall_clone) // clone
	linux_syscall_table[57] = voidptr(userland.syscall_fork) // fork
	linux_syscall_table[58] = voidptr(userland.syscall_fork) // vfork
	linux_syscall_table[59] = voidptr(userland.syscall_execve) // execve
	linux_syscall_table[60] = voidptr(userland.syscall_linux_exit) // exit
	linux_syscall_table[61] = voidptr(userland.syscall_wait4) // wait4
	linux_syscall_table[63] = voidptr(syscall_linux_uname) // uname
	linux_syscall_table[97] = voidptr(syscall_linux_getrlimit) // getrlimit
	linux_syscall_table[98] = voidptr(sys.syscall_getrusage) // getrusage
	linux_syscall_table[99] = voidptr(sys.syscall_sysinfo) // sysinfo
	linux_syscall_table[102] = voidptr(userland.syscall_getuid) // getuid
	linux_syscall_table[104] = voidptr(userland.syscall_getgid) // getgid
	linux_syscall_table[105] = voidptr(userland.syscall_setuid) // setuid
	linux_syscall_table[106] = voidptr(userland.syscall_setgid) // setgid
	linux_syscall_table[107] = voidptr(userland.syscall_geteuid) // geteuid
	linux_syscall_table[108] = voidptr(userland.syscall_getegid) // getegid
	linux_syscall_table[109] = voidptr(syscall_linux_setpgid) // setpgid
	linux_syscall_table[110] = voidptr(userland.syscall_getppid) // getppid
	linux_syscall_table[111] = voidptr(syscall_linux_getpgrp) // getpgrp
	linux_syscall_table[112] = voidptr(userland.syscall_setsid) // setsid
	linux_syscall_table[113] = voidptr(userland.syscall_setreuid) // setreuid
	linux_syscall_table[114] = voidptr(userland.syscall_setregid) // setregid
	linux_syscall_table[115] = voidptr(userland.syscall_getgroups) // getgroups
	linux_syscall_table[116] = voidptr(userland.syscall_setgroups) // setgroups
	linux_syscall_table[117] = voidptr(userland.syscall_setresuid) // setresuid
	linux_syscall_table[118] = voidptr(userland.syscall_getresuid) // getresuid
	linux_syscall_table[119] = voidptr(userland.syscall_setresgid) // setresgid
	linux_syscall_table[120] = voidptr(userland.syscall_getresgid) // getresgid
	linux_syscall_table[121] = voidptr(syscall_linux_getpgid) // getpgid
	linux_syscall_table[124] = voidptr(userland.syscall_getsid) // getsid
	linux_syscall_table[140] = voidptr(syscall_linux_getpriority) // getpriority
	linux_syscall_table[141] = voidptr(syscall_linux_setpriority) // setpriority
	linux_syscall_table[142] = voidptr(syscall_linux_sched_setparam) // sched_setparam
	linux_syscall_table[143] = voidptr(syscall_linux_sched_getparam) // sched_getparam
	linux_syscall_table[144] = voidptr(syscall_linux_sched_setscheduler) // sched_setscheduler
	linux_syscall_table[145] = voidptr(syscall_linux_sched_getscheduler) // sched_getscheduler
	linux_syscall_table[146] = voidptr(syscall_linux_sched_get_priority_max) // sched_get_priority_max
	linux_syscall_table[147] = voidptr(syscall_linux_sched_get_priority_min) // sched_get_priority_min
	linux_syscall_table[148] = voidptr(syscall_linux_sched_rr_get_interval) // sched_rr_get_interval
	linux_syscall_table[157] = voidptr(syscall_container_prctl) // prctl
	linux_syscall_table[158] = voidptr(syscall_linux_arch_prctl) // arch_prctl
	linux_syscall_table[160] = voidptr(syscall_linux_setrlimit) // setrlimit
	linux_syscall_table[186] = voidptr(syscall_linux_gettid) // gettid
	linux_syscall_table[202] = voidptr(syscall_linux_futex) // futex
	linux_syscall_table[203] = voidptr(syscall_linux_sched_setaffinity) // sched_setaffinity
	linux_syscall_table[204] = voidptr(syscall_linux_sched_getaffinity) // sched_getaffinity
	linux_syscall_table[218] = voidptr(userland.syscall_set_tid_address) // set_tid_address
	linux_syscall_table[231] = voidptr(userland.syscall_exit_group) // exit_group
	linux_syscall_table[247] = voidptr(userland.syscall_waitid) // waitid
	linux_syscall_table[273] = voidptr(userland.syscall_set_robust_list) // set_robust_list
	linux_syscall_table[274] = voidptr(userland.syscall_get_robust_list) // get_robust_list
	linux_syscall_table[302] = voidptr(syscall_linux_prlimit64) // prlimit64
	linux_syscall_table[309] = voidptr(numa.syscall_getcpu) // getcpu
	linux_syscall_table[314] = voidptr(syscall_linux_sched_setattr) // sched_setattr
	linux_syscall_table[315] = voidptr(syscall_linux_sched_getattr) // sched_getattr
	linux_syscall_table[318] = voidptr(syscall_linux_getrandom) // getrandom
	linux_syscall_table[322] = voidptr(userland.syscall_execveat) // execveat
	linux_syscall_table[334] = voidptr(syscall_linux_rseq) // rseq
	linux_syscall_table[435] = voidptr(userland.syscall_clone3) // clone3

	// Sockets
	linux_syscall_table[41] = voidptr(socket.syscall_socket) // socket
	linux_syscall_table[42] = voidptr(socket.syscall_connect) // connect
	linux_syscall_table[43] = voidptr(syscall_linux_accept) // accept
	linux_syscall_table[44] = voidptr(socket.syscall_sendto) // sendto
	linux_syscall_table[45] = voidptr(socket.syscall_recvfrom) // recvfrom
	linux_syscall_table[46] = voidptr(socket.syscall_sendmsg) // sendmsg
	linux_syscall_table[47] = voidptr(socket.syscall_recvmsg) // recvmsg
	linux_syscall_table[48] = voidptr(socket.syscall_shutdown) // shutdown
	linux_syscall_table[49] = voidptr(socket.syscall_bind) // bind
	linux_syscall_table[50] = voidptr(socket.syscall_listen) // listen
	linux_syscall_table[51] = voidptr(socket.syscall_getsockname) // getsockname
	linux_syscall_table[52] = voidptr(socket.syscall_getpeername) // getpeername
	linux_syscall_table[53] = voidptr(socket.syscall_socketpair) // socketpair
	linux_syscall_table[54] = voidptr(socket.syscall_setsockopt) // setsockopt
	linux_syscall_table[55] = voidptr(socket.syscall_getsockopt) // getsockopt
	linux_syscall_table[288] = voidptr(syscall_linux_accept4) // accept4
	linux_syscall_table[299] = voidptr(syscall_linux_recvmmsg) // recvmmsg
	linux_syscall_table[307] = voidptr(syscall_linux_sendmmsg) // sendmmsg

	// Hostname
	linux_syscall_table[170] = voidptr(net.syscall_sethostname) // sethostname
	linux_syscall_table[171] = voidptr(net.syscall_setdomainname) // setdomainname

	// Containers: capabilities, mounts and namespaces
	linux_syscall_table[125] = voidptr(syscall_linux_capget) // capget
	linux_syscall_table[126] = voidptr(syscall_linux_capset) // capset
	linux_syscall_table[155] = voidptr(fs.syscall_pivot_root) // pivot_root
	linux_syscall_table[161] = voidptr(fs.syscall_chroot) // chroot
	linux_syscall_table[165] = voidptr(fs.syscall_mount) // mount
	linux_syscall_table[166] = voidptr(fs.syscall_umount) // umount2
	linux_syscall_table[272] = voidptr(fs.syscall_unshare) // unshare
	linux_syscall_table[308] = voidptr(fs.syscall_setns) // setns
	linux_syscall_table[321] = voidptr(syscall_linux_bpf) // bpf
	linux_syscall_table[317] = voidptr(syscall_linux_seccomp) // seccomp
	linux_syscall_table[seccomp_verdict_nr] = voidptr(syscall_seccomp_verdict)
}
