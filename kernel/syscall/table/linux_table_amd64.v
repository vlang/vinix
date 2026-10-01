// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module table

// The x86-64 syscall table: Linux's numbers, which every amd64 program
// uses, as every arm64 program uses asm-generic's.
//
// It covers what the arm64 table does, with the same handlers wherever the
// ABI agrees -- the wrappers shared between the two live in linux_common.v,
// linux_compat.v, gaps.v and container.v -- plus the calls x86-64 kept from
// before the *at() family: open, stat, rename, chmod, select and the like,
// which musl, BusyBox and Python still make here.

import errno
import file
import fs
import memory
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
import x86.cpu
import x86.msr

const linux_syscall_max = 512

@[export: 'syscall_table']
__global (
	syscall_table [linux_syscall_max]voidptr
)

fn syscall_linux_vacant(_ voidptr) (u64, u64) {
	return errno.err, errno.enosys
}

fn syscall_linux_open(gpr_state voidptr, path charptr, flags int, mode u32) (u64, u64) {
	return fs.syscall_openat(gpr_state, fs.at_fdcwd, path, flags, mode)
}

// A bad user `stat` buffer must fail with EFAULT, not fault the kernel: the
// result goes into a kernel struct that is then copied out through the
// checked path. On amd64 the Vinix stat.Stat already has the Linux struct
// stat layout, so the copy is verbatim.
fn copy_stat_to_user(src &stat.Stat, buf u64) (u64, u64) {
	if !usercopy.copy_to_user(buf, voidptr(src), u64(sizeof(stat.Stat))) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn syscall_linux_fstat(gpr_state voidptr, fdnum int, buf u64) (u64, u64) {
	mut vinix_stat := stat.Stat{}
	ret, err := fs.syscall_fstat(gpr_state, fdnum, unsafe { &vinix_stat })
	if err != 0 {
		return ret, err
	}
	return copy_stat_to_user(&vinix_stat, buf)
}

fn syscall_linux_fstatat(gpr_state voidptr, dirfd int, path charptr, buf u64, flags int) (u64, u64) {
	mut vinix_stat := stat.Stat{}
	ret, err := fs.syscall_fstatat(gpr_state, dirfd, path, unsafe { &vinix_stat }, flags)
	if err != 0 {
		return ret, err
	}
	return copy_stat_to_user(&vinix_stat, buf)
}

fn syscall_linux_stat(gpr_state voidptr, path charptr, buf u64) (u64, u64) {
	return syscall_linux_fstatat(gpr_state, fs.at_fdcwd, path, buf, 0)
}

fn syscall_linux_lstat(gpr_state voidptr, path charptr, buf u64) (u64, u64) {
	return syscall_linux_fstatat(gpr_state, fs.at_fdcwd, path, buf, fs.at_symlink_nofollow)
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
	return pipe.syscall_pipe_checked(gpr_state, pipefds, 0)
}

// arch_prctl(code, address): the calling thread's FS and GS bases. Inside a
// syscall the user's GS base is the one SWAPGS parked in KERNEL_GS_BASE. The
// segment register is loaded null first, as Linux does: a selector in it
// would give its descriptor's base instead; see sched.load_fs_gs().
fn syscall_linux_arch_prctl(_ voidptr, code int, address u64) (u64, u64) {
	mut current_thread := proc.current_thread()
	match code {
		0x1001, 0x1002 { // ARCH_SET_GS, ARCH_SET_FS
			// A non-canonical base would fault the kernel's own WRMSR.
			if address >= memory.user_address_limit() {
				return errno.err, errno.eperm
			}
			if code == 0x1002 {
				current_thread.fs_base = address
				cpu.load_fs_selector(0)
				msr.wrmsr(0xc0000100, address)
			} else {
				current_thread.gs_base = address
				cpu.load_user_gs_selector(0)
				msr.wrmsr(0xc0000102, address)
			}
			return 0, 0
		}
		0x1003, 0x1004 { // ARCH_GET_FS, ARCH_GET_GS
			value := msr.rdmsr(if code == 0x1003 { u32(0xc0000100) } else { u32(0xc0000102) })
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
	return linux_getdents(gpr_state, fdnum, dirp, count, false)
}

// getdents(fd, dirp, count): getdents64's entries in the layout from before
// it, struct linux_dirent: the name straight after the record length, and
// the type in the record's last byte.
fn syscall_linux_getdents(gpr_state voidptr, fdnum int, dirp u64, count u64) (u64, u64) {
	return linux_getdents(gpr_state, fdnum, dirp, count, true)
}

// As many of the directory's entries as fit in `count` bytes at `dirp`, as
// struct linux_dirent64, or as struct linux_dirent when `legacy`. Both are
// the inode, the offset and the record length first, and padded to 8 bytes;
// the same length holds either. An entry that does not fit is left for the
// next call, and EINVAL is the answer when it is the first, as on Linux.
fn linux_getdents(gpr_state voidptr, fdnum int, dirp u64, count u64, legacy bool) (u64, u64) {
	mut offset := u64(0)
	for {
		mut dirent := stat.Dirent{}
		ret, err := fs.syscall_readdir(gpr_state, fdnum, mut dirent)
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
			if offset == 0 {
				return errno.err, errno.einval
			}
			break
		}
		mut record := []u8{len: int(reclen)} @[freed]
		unsafe {
			*&u64(&record[0]) = dirent.ino
			*&u64(&record[8]) = dirent.off
			*&u16(&record[16]) = u16(reclen)
			if legacy {
				C.memcpy(voidptr(&record[18]), &dirent.name[0], name_len + 1)
				record[reclen - 1] = dirent.@type
			} else {
				record[18] = dirent.@type
				C.memcpy(voidptr(&record[19]), &dirent.name[0], name_len + 1)
			}
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

// utime(path, times): utimensat() with a struct utimbuf, whole seconds of
// access and modification, or none for now.
fn syscall_linux_utime(_ voidptr, path charptr, times u64) (u64, u64) {
	mut requested := [2]time.TimeSpec{init: time.TimeSpec{
		tv_nsec: fs.utime_now
	}}
	if times != 0 {
		mut seconds := [2]i64{}
		if !usercopy.copy_from_user(voidptr(&seconds[0]), times, sizeof(i64) * 2) {
			return errno.err, errno.efault
		}
		requested[0] = time.TimeSpec{
			tv_sec: seconds[0]
		}
		requested[1] = time.TimeSpec{
			tv_sec: seconds[1]
		}
	}
	return fs.set_file_times(fs.at_fdcwd, path, requested, 0)
}

// futimesat(dirfd, path, times): utimensat() with two struct timevals, or
// none for now. Microseconds out of range are refused before they become
// nanoseconds, which would let UTIME_NOW and UTIME_OMIT through, as on Linux.
fn syscall_linux_futimesat(_ voidptr, dirfd int, path charptr, times u64) (u64, u64) {
	mut requested := [2]time.TimeSpec{init: time.TimeSpec{
		tv_nsec: fs.utime_now
	}}
	if times != 0 {
		mut timevals := [4]i64{}
		if !usercopy.copy_from_user(voidptr(&timevals[0]), times, sizeof(i64) * 4) {
			return errno.err, errno.efault
		}
		for i := 0; i < 2; i++ {
			microseconds := timevals[i * 2 + 1]
			if microseconds < 0 || microseconds >= 1000000 {
				return errno.err, errno.einval
			}
			requested[i] = time.TimeSpec{
				tv_sec:  timevals[i * 2]
				tv_nsec: microseconds * 1000
			}
		}
	}
	return fs.set_file_times(dirfd, path, requested, 0)
}

// utimes(path, times) is futimesat(AT_FDCWD, path, times).
fn syscall_linux_utimes(gpr_state voidptr, path charptr, times u64) (u64, u64) {
	return syscall_linux_futimesat(gpr_state, fs.at_fdcwd, path, times)
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

pub fn init_syscall_table() {
	for i := 0; i < linux_syscall_max; i++ {
		syscall_table[i] = voidptr(syscall_linux_vacant)
	}

	// Linux x86-64 syscall numbers → Vinix handlers.
	// Reference: arch/x86/entry/syscalls/syscall_64.tbl

	// File I/O
	syscall_table[0] = voidptr(fs.syscall_read) // read
	syscall_table[1] = voidptr(fs.syscall_write) // write
	syscall_table[2] = voidptr(syscall_linux_open) // open
	syscall_table[3] = voidptr(fs.syscall_close) // close
	syscall_table[4] = voidptr(syscall_linux_stat) // stat
	syscall_table[5] = voidptr(syscall_linux_fstat) // fstat
	syscall_table[6] = voidptr(syscall_linux_lstat) // lstat
	syscall_table[7] = voidptr(file.syscall_poll) // poll
	syscall_table[8] = voidptr(fs.syscall_seek) // lseek
	syscall_table[16] = voidptr(fs.syscall_ioctl) // ioctl
	syscall_table[17] = voidptr(syscall_linux_pread64) // pread64
	syscall_table[18] = voidptr(syscall_linux_pwrite64) // pwrite64
	syscall_table[19] = voidptr(syscall_linux_readv) // readv
	syscall_table[20] = voidptr(syscall_linux_writev) // writev
	syscall_table[21] = voidptr(syscall_linux_access) // access
	syscall_table[22] = voidptr(syscall_linux_pipe) // pipe
	syscall_table[23] = voidptr(file.syscall_select) // select
	syscall_table[32] = voidptr(syscall_linux_dup) // dup
	syscall_table[33] = voidptr(syscall_linux_dup2) // dup2
	syscall_table[40] = voidptr(syscall_linux_sendfile) // sendfile
	syscall_table[72] = voidptr(file.syscall_fcntl) // fcntl
	syscall_table[73] = voidptr(file.syscall_flock) // flock
	syscall_table[74] = voidptr(file.syscall_fsync) // fsync
	syscall_table[75] = voidptr(file.syscall_fsync) // fdatasync
	syscall_table[76] = voidptr(fs.syscall_truncate) // truncate
	syscall_table[77] = voidptr(file.syscall_ftruncate) // ftruncate
	syscall_table[78] = voidptr(syscall_linux_getdents) // getdents
	syscall_table[79] = voidptr(fs.syscall_getcwd) // getcwd
	syscall_table[80] = voidptr(fs.syscall_chdir) // chdir
	syscall_table[81] = voidptr(fs.syscall_fchdir) // fchdir
	syscall_table[82] = voidptr(syscall_linux_rename) // rename
	syscall_table[83] = voidptr(syscall_linux_mkdir) // mkdir
	syscall_table[84] = voidptr(syscall_linux_rmdir) // rmdir
	syscall_table[85] = voidptr(syscall_linux_creat) // creat
	syscall_table[86] = voidptr(syscall_linux_link) // link
	syscall_table[87] = voidptr(syscall_linux_unlink) // unlink
	syscall_table[88] = voidptr(syscall_linux_symlink) // symlink
	syscall_table[89] = voidptr(syscall_linux_readlink) // readlink
	syscall_table[90] = voidptr(syscall_linux_chmod) // chmod
	syscall_table[91] = voidptr(fs.syscall_fchmod) // fchmod
	syscall_table[92] = voidptr(syscall_linux_chown) // chown
	syscall_table[93] = voidptr(fs.syscall_fchown) // fchown
	syscall_table[94] = voidptr(syscall_linux_lchown) // lchown
	syscall_table[95] = voidptr(fs.syscall_umask) // umask
	syscall_table[132] = voidptr(syscall_linux_utime) // utime
	syscall_table[133] = voidptr(syscall_linux_mknod) // mknod
	syscall_table[137] = voidptr(fs.syscall_statfs) // statfs
	syscall_table[138] = voidptr(fs.syscall_fstatfs) // fstatfs
	syscall_table[162] = voidptr(fs.syscall_sync) // sync
	syscall_table[169] = voidptr(syscall_linux_reboot) // reboot
	syscall_table[188] = voidptr(fs.syscall_setxattr) // setxattr
	syscall_table[189] = voidptr(fs.syscall_lsetxattr) // lsetxattr
	syscall_table[190] = voidptr(fs.syscall_fsetxattr) // fsetxattr
	syscall_table[191] = voidptr(fs.syscall_getxattr) // getxattr
	syscall_table[192] = voidptr(fs.syscall_lgetxattr) // lgetxattr
	syscall_table[193] = voidptr(fs.syscall_fgetxattr) // fgetxattr
	syscall_table[194] = voidptr(fs.syscall_listxattr) // listxattr
	syscall_table[195] = voidptr(fs.syscall_llistxattr) // llistxattr
	syscall_table[196] = voidptr(fs.syscall_flistxattr) // flistxattr
	syscall_table[197] = voidptr(fs.syscall_removexattr) // removexattr
	syscall_table[198] = voidptr(fs.syscall_lremovexattr) // lremovexattr
	syscall_table[199] = voidptr(fs.syscall_fremovexattr) // fremovexattr
	syscall_table[217] = voidptr(syscall_linux_getdents64) // getdents64
	syscall_table[221] = voidptr(file.syscall_fadvise64) // fadvise64
	syscall_table[235] = voidptr(syscall_linux_utimes) // utimes
	syscall_table[253] = voidptr(syscall_linux_inotify_init) // inotify_init
	syscall_table[254] = voidptr(fs.syscall_inotify_add_watch) // inotify_add_watch
	syscall_table[255] = voidptr(fs.syscall_inotify_rm_watch) // inotify_rm_watch
	syscall_table[257] = voidptr(syscall_linux_openat) // openat
	syscall_table[258] = voidptr(fs.syscall_mkdirat) // mkdirat
	syscall_table[259] = voidptr(fs.syscall_mknodat) // mknodat
	syscall_table[260] = voidptr(fs.syscall_fchownat) // fchownat
	syscall_table[261] = voidptr(syscall_linux_futimesat) // futimesat
	syscall_table[262] = voidptr(syscall_linux_fstatat) // newfstatat
	syscall_table[263] = voidptr(fs.syscall_unlinkat) // unlinkat
	syscall_table[264] = voidptr(fs.syscall_renameat) // renameat
	syscall_table[265] = voidptr(fs.syscall_linkat) // linkat
	syscall_table[266] = voidptr(fs.syscall_symlinkat) // symlinkat
	syscall_table[267] = voidptr(fs.syscall_readlinkat) // readlinkat
	syscall_table[268] = voidptr(fs.syscall_fchmodat) // fchmodat
	syscall_table[269] = voidptr(syscall_linux_faccessat) // faccessat
	syscall_table[270] = voidptr(file.syscall_pselect6) // pselect6
	// The fifth argument, the signal set's size, is always 8 from musl.
	syscall_table[271] = voidptr(file.syscall_ppoll) // ppoll
	syscall_table[275] = voidptr(pipe.syscall_splice) // splice
	syscall_table[276] = voidptr(pipe.syscall_tee) // tee
	syscall_table[277] = voidptr(file.syscall_sync_file_range) // sync_file_range
	syscall_table[278] = voidptr(pipe.syscall_vmsplice) // vmsplice
	syscall_table[280] = voidptr(fs.syscall_utimensat) // utimensat
	syscall_table[282] = voidptr(syscall_linux_signalfd) // signalfd
	syscall_table[283] = voidptr(file.syscall_timerfd_create) // timerfd_create
	syscall_table[284] = voidptr(syscall_linux_eventfd) // eventfd
	syscall_table[285] = voidptr(file.syscall_fallocate) // fallocate
	syscall_table[286] = voidptr(file.syscall_timerfd_settime) // timerfd_settime
	syscall_table[287] = voidptr(file.syscall_timerfd_gettime) // timerfd_gettime
	syscall_table[289] = voidptr(userland.syscall_signalfd4) // signalfd4
	syscall_table[290] = voidptr(file.syscall_eventfd2) // eventfd2
	syscall_table[292] = voidptr(file.syscall_dup3) // dup3
	syscall_table[293] = voidptr(pipe.syscall_pipe_checked) // pipe2
	syscall_table[294] = voidptr(fs.syscall_inotify_init) // inotify_init1
	syscall_table[295] = voidptr(syscall_linux_preadv) // preadv
	syscall_table[296] = voidptr(syscall_linux_pwritev) // pwritev
	syscall_table[306] = voidptr(fs.syscall_syncfs) // syncfs
	syscall_table[316] = voidptr(fs.syscall_renameat2) // renameat2
	syscall_table[319] = voidptr(fs.syscall_memfd_create) // memfd_create
	syscall_table[326] = voidptr(pipe.syscall_copy_file_range) // copy_file_range
	syscall_table[327] = voidptr(syscall_linux_preadv2) // preadv2
	syscall_table[328] = voidptr(syscall_linux_pwritev2) // pwritev2
	syscall_table[332] = voidptr(syscall_linux_statx) // statx
	syscall_table[436] = voidptr(file.syscall_close_range) // close_range
	syscall_table[437] = voidptr(syscall_linux_openat2) // openat2
	syscall_table[439] = voidptr(syscall_linux_faccessat2) // faccessat2

	// epoll
	syscall_table[213] = voidptr(syscall_linux_epoll_create) // epoll_create
	syscall_table[232] = voidptr(syscall_linux_epoll_wait) // epoll_wait
	syscall_table[233] = voidptr(file.syscall_epoll_ctl) // epoll_ctl
	syscall_table[281] = voidptr(file.syscall_epoll_pwait) // epoll_pwait
	syscall_table[291] = voidptr(file.syscall_epoll_create1) // epoll_create1
	syscall_table[441] = voidptr(file.syscall_epoll_pwait2) // epoll_pwait2

	// Memory
	syscall_table[9] = voidptr(syscall_linux_mmap) // mmap
	syscall_table[10] = voidptr(mmap.syscall_mprotect) // mprotect
	syscall_table[11] = voidptr(mmap.syscall_munmap) // munmap
	syscall_table[12] = voidptr(mmap.syscall_brk) // brk
	syscall_table[25] = voidptr(mmap.syscall_mremap) // mremap
	syscall_table[26] = voidptr(mmap.syscall_msync) // msync
	syscall_table[27] = voidptr(mmap.syscall_mincore) // mincore
	syscall_table[28] = voidptr(mmap.syscall_madvise) // madvise
	syscall_table[29] = voidptr(sysvshm.syscall_shmget) // shmget
	syscall_table[30] = voidptr(sysvshm.syscall_shmat) // shmat
	syscall_table[31] = voidptr(sysvshm.syscall_shmctl) // shmctl
	syscall_table[67] = voidptr(sysvshm.syscall_shmdt) // shmdt
	syscall_table[64] = voidptr(sysvsem.syscall_semget) // semget
	syscall_table[65] = voidptr(sysvsem.syscall_semop) // semop
	syscall_table[66] = voidptr(sysvsem.syscall_semctl) // semctl
	syscall_table[220] = voidptr(sysvsem.syscall_semtimedop) // semtimedop
	syscall_table[149] = voidptr(syscall_linux_mlock) // mlock
	syscall_table[150] = voidptr(syscall_linux_mlock) // munlock
	syscall_table[151] = voidptr(syscall_linux_mlockall) // mlockall
	syscall_table[152] = voidptr(syscall_linux_munlockall) // munlockall
	syscall_table[237] = voidptr(numa.syscall_mbind) // mbind
	syscall_table[238] = voidptr(numa.syscall_set_mempolicy) // set_mempolicy
	syscall_table[239] = voidptr(numa.syscall_get_mempolicy) // get_mempolicy
	syscall_table[324] = voidptr(syscall_linux_membarrier) // membarrier
	syscall_table[325] = voidptr(syscall_linux_mlock2) // mlock2

	// Signals
	syscall_table[13] = voidptr(userland.syscall_rt_sigaction) // rt_sigaction
	syscall_table[14] = voidptr(userland.syscall_rt_sigprocmask) // rt_sigprocmask
	syscall_table[15] = voidptr(userland.syscall_linux_rt_sigreturn) // rt_sigreturn
	syscall_table[34] = voidptr(userland.syscall_pause) // pause
	syscall_table[62] = voidptr(userland.syscall_kill) // kill
	syscall_table[127] = voidptr(syscall_linux_rt_sigpending) // rt_sigpending
	syscall_table[128] = voidptr(userland.syscall_rt_sigtimedwait) // rt_sigtimedwait
	syscall_table[130] = voidptr(userland.syscall_rt_sigsuspend) // rt_sigsuspend
	syscall_table[131] = voidptr(userland.syscall_sigaltstack) // sigaltstack
	syscall_table[200] = voidptr(userland.syscall_tkill) // tkill
	syscall_table[234] = voidptr(userland.syscall_tgkill) // tgkill

	// Time
	syscall_table[35] = voidptr(sys.syscall_nanosleep) // nanosleep
	syscall_table[36] = voidptr(syscall_linux_getitimer) // getitimer
	syscall_table[37] = voidptr(syscall_linux_alarm) // alarm
	syscall_table[38] = voidptr(syscall_linux_setitimer) // setitimer
	syscall_table[96] = voidptr(sys.syscall_gettimeofday) // gettimeofday
	syscall_table[100] = voidptr(syscall_linux_times) // times
	syscall_table[201] = voidptr(syscall_linux_time) // time
	syscall_table[222] = voidptr(posixtimer.syscall_timer_create) // timer_create
	syscall_table[223] = voidptr(posixtimer.syscall_timer_settime) // timer_settime
	syscall_table[224] = voidptr(posixtimer.syscall_timer_gettime) // timer_gettime
	syscall_table[225] = voidptr(posixtimer.syscall_timer_getoverrun) // timer_getoverrun
	syscall_table[226] = voidptr(posixtimer.syscall_timer_delete) // timer_delete
	syscall_table[228] = voidptr(sys.syscall_clock_gettime) // clock_gettime
	syscall_table[229] = voidptr(sys.syscall_clock_getres) // clock_getres
	syscall_table[230] = voidptr(sys.syscall_clock_nanosleep) // clock_nanosleep

	// Processes and threads
	syscall_table[24] = voidptr(syscall_linux_sched_yield) // sched_yield
	syscall_table[39] = voidptr(userland.syscall_getpid) // getpid
	syscall_table[56] = voidptr(userland.syscall_clone) // clone
	syscall_table[57] = voidptr(userland.syscall_fork) // fork
	syscall_table[58] = voidptr(userland.syscall_fork) // vfork
	syscall_table[59] = voidptr(userland.syscall_execve) // execve
	syscall_table[60] = voidptr(userland.syscall_exit) // exit
	syscall_table[61] = voidptr(userland.syscall_wait4) // wait4
	syscall_table[63] = voidptr(syscall_linux_uname) // uname
	syscall_table[97] = voidptr(syscall_linux_getrlimit) // getrlimit
	syscall_table[98] = voidptr(sys.syscall_getrusage) // getrusage
	syscall_table[99] = voidptr(sys.syscall_sysinfo) // sysinfo
	syscall_table[102] = voidptr(userland.syscall_getuid) // getuid
	syscall_table[104] = voidptr(userland.syscall_getgid) // getgid
	syscall_table[105] = voidptr(userland.syscall_setuid) // setuid
	syscall_table[106] = voidptr(userland.syscall_setgid) // setgid
	syscall_table[107] = voidptr(userland.syscall_geteuid) // geteuid
	syscall_table[108] = voidptr(userland.syscall_getegid) // getegid
	syscall_table[109] = voidptr(syscall_linux_setpgid) // setpgid
	syscall_table[110] = voidptr(userland.syscall_getppid) // getppid
	syscall_table[111] = voidptr(syscall_linux_getpgrp) // getpgrp
	syscall_table[112] = voidptr(userland.syscall_setsid) // setsid
	syscall_table[113] = voidptr(userland.syscall_setreuid) // setreuid
	syscall_table[114] = voidptr(userland.syscall_setregid) // setregid
	syscall_table[115] = voidptr(userland.syscall_getgroups) // getgroups
	syscall_table[116] = voidptr(userland.syscall_setgroups) // setgroups
	syscall_table[117] = voidptr(userland.syscall_setresuid) // setresuid
	syscall_table[118] = voidptr(userland.syscall_getresuid) // getresuid
	syscall_table[119] = voidptr(userland.syscall_setresgid) // setresgid
	syscall_table[120] = voidptr(userland.syscall_getresgid) // getresgid
	syscall_table[121] = voidptr(syscall_linux_getpgid) // getpgid
	syscall_table[124] = voidptr(userland.syscall_getsid) // getsid
	syscall_table[140] = voidptr(syscall_linux_getpriority) // getpriority
	syscall_table[141] = voidptr(syscall_linux_setpriority) // setpriority
	syscall_table[142] = voidptr(syscall_linux_sched_setparam) // sched_setparam
	syscall_table[143] = voidptr(syscall_linux_sched_getparam) // sched_getparam
	syscall_table[144] = voidptr(syscall_linux_sched_setscheduler) // sched_setscheduler
	syscall_table[145] = voidptr(syscall_linux_sched_getscheduler) // sched_getscheduler
	syscall_table[146] = voidptr(syscall_linux_sched_get_priority_max) // sched_get_priority_max
	syscall_table[147] = voidptr(syscall_linux_sched_get_priority_min) // sched_get_priority_min
	syscall_table[148] = voidptr(syscall_linux_sched_rr_get_interval) // sched_rr_get_interval
	syscall_table[157] = voidptr(syscall_container_prctl) // prctl
	syscall_table[154] = voidptr(syscall_linux_modify_ldt) // modify_ldt
	syscall_table[158] = voidptr(syscall_linux_arch_prctl) // arch_prctl
	syscall_table[160] = voidptr(syscall_linux_setrlimit) // setrlimit
	syscall_table[186] = voidptr(syscall_linux_gettid) // gettid
	syscall_table[202] = voidptr(syscall_linux_futex) // futex
	syscall_table[203] = voidptr(syscall_linux_sched_setaffinity) // sched_setaffinity
	syscall_table[204] = voidptr(syscall_linux_sched_getaffinity) // sched_getaffinity
	syscall_table[205] = voidptr(syscall_linux_set_thread_area) // set_thread_area
	syscall_table[211] = voidptr(syscall_linux_get_thread_area) // get_thread_area
	syscall_table[218] = voidptr(userland.syscall_set_tid_address) // set_tid_address
	syscall_table[231] = voidptr(userland.syscall_exit_group) // exit_group
	syscall_table[247] = voidptr(userland.syscall_waitid) // waitid
	syscall_table[273] = voidptr(userland.syscall_set_robust_list) // set_robust_list
	syscall_table[274] = voidptr(userland.syscall_get_robust_list) // get_robust_list
	syscall_table[302] = voidptr(syscall_linux_prlimit64) // prlimit64
	syscall_table[309] = voidptr(numa.syscall_getcpu) // getcpu
	syscall_table[314] = voidptr(syscall_linux_sched_setattr) // sched_setattr
	syscall_table[315] = voidptr(syscall_linux_sched_getattr) // sched_getattr
	syscall_table[318] = voidptr(syscall_linux_getrandom) // getrandom
	syscall_table[322] = voidptr(userland.syscall_execveat) // execveat
	syscall_table[334] = voidptr(syscall_linux_rseq) // rseq
	syscall_table[435] = voidptr(userland.syscall_clone3) // clone3

	// Sockets
	syscall_table[41] = voidptr(socket.syscall_socket) // socket
	syscall_table[42] = voidptr(socket.syscall_connect) // connect
	syscall_table[43] = voidptr(syscall_linux_accept) // accept
	syscall_table[44] = voidptr(socket.syscall_sendto) // sendto
	syscall_table[45] = voidptr(socket.syscall_recvfrom) // recvfrom
	syscall_table[46] = voidptr(socket.syscall_sendmsg) // sendmsg
	syscall_table[47] = voidptr(socket.syscall_recvmsg) // recvmsg
	syscall_table[48] = voidptr(socket.syscall_shutdown) // shutdown
	syscall_table[49] = voidptr(socket.syscall_bind) // bind
	syscall_table[50] = voidptr(socket.syscall_listen) // listen
	syscall_table[51] = voidptr(socket.syscall_getsockname) // getsockname
	syscall_table[52] = voidptr(socket.syscall_getpeername) // getpeername
	syscall_table[53] = voidptr(socket.syscall_socketpair) // socketpair
	syscall_table[54] = voidptr(socket.syscall_setsockopt) // setsockopt
	syscall_table[55] = voidptr(socket.syscall_getsockopt) // getsockopt
	syscall_table[288] = voidptr(syscall_linux_accept4) // accept4
	syscall_table[299] = voidptr(syscall_linux_recvmmsg) // recvmmsg
	syscall_table[307] = voidptr(syscall_linux_sendmmsg) // sendmmsg

	// Hostname
	syscall_table[170] = voidptr(net.syscall_sethostname) // sethostname
	syscall_table[171] = voidptr(net.syscall_setdomainname) // setdomainname

	// Containers: capabilities, mounts and namespaces
	syscall_table[125] = voidptr(syscall_linux_capget) // capget
	syscall_table[126] = voidptr(syscall_linux_capset) // capset
	syscall_table[155] = voidptr(fs.syscall_pivot_root) // pivot_root
	syscall_table[161] = voidptr(fs.syscall_chroot) // chroot
	syscall_table[165] = voidptr(fs.syscall_mount) // mount
	syscall_table[166] = voidptr(fs.syscall_umount) // umount2
	syscall_table[272] = voidptr(fs.syscall_unshare) // unshare
	syscall_table[308] = voidptr(fs.syscall_setns) // setns
	syscall_table[321] = voidptr(syscall_linux_bpf) // bpf
	syscall_table[317] = voidptr(syscall_linux_seccomp) // seccomp
	syscall_table[seccomp_verdict_nr] = voidptr(syscall_seccomp_verdict)
}
