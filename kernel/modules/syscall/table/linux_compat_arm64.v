// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

// Linux AArch64 compatibility calls which do not map one-for-one onto an
// existing Vinix syscall.  musl exposes these directly (notably the vectored
// positioned-I/O family), so their argument layout must follow the kernel ABI
// rather than the C library function prototype.

import aarch64.cpu
import errno
import file
import fs
import proc
import resource
import time
import usercopy

fn split_offset(low u64, high u64) i64 {
	return i64((low & 0xffffffff) | (high << 32))
}

fn syscall_linux_preadv(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int, pos_low u64, pos_high u64) (u64, u64) {
	return syscall_linux_preadv2(gpr_state, fdnum, iov_ptr, iovcnt, pos_low, pos_high,
		0)
}

fn syscall_linux_pwritev(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int, pos_low u64, pos_high u64) (u64, u64) {
	return syscall_linux_pwritev2(gpr_state, fdnum, iov_ptr, iovcnt, pos_low, pos_high,
		0)
}

fn syscall_linux_preadv2(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int, pos_low u64, pos_high u64, flags u32) (u64, u64) {
	if flags != 0 {
		return errno.err, errno.eopnotsupp
	}

	_, validation_error := validate_linux_iov(iov_ptr, iovcnt)
	if validation_error != 0 {
		return errno.err, validation_error
	}

	offset := split_offset(pos_low, pos_high)
	if offset == -1 {
		return syscall_linux_readv(gpr_state, fdnum, iov_ptr, iovcnt)
	}
	if offset < 0 {
		return errno.err, errno.einval
	}

	// Even a zero-length vector validates the descriptor.
	mut checked_fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
		return errno.err, errno.get()
	}
	checked_fd.unref()

	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		iov := read_linux_iov(iov_ptr, i) or { return errno.err, errno.efault }
		if iov.len == 0 {
			continue
		}
		if total > u64(0x7fffffffffffffff) - u64(offset)
			|| iov.len > u64(0x7fffffffffffffff) - u64(offset) - total {
			return if total > 0 { total, u64(0) } else { errno.err, errno.einval }
		}
		ret, err := file.syscall_pread(gpr_state, fdnum, voidptr(iov.base), iov.len,
			offset + i64(total))
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

fn syscall_linux_pwritev2(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int, pos_low u64, pos_high u64, flags u32) (u64, u64) {
	if flags != 0 {
		return errno.err, errno.eopnotsupp
	}

	_, validation_error := validate_linux_iov(iov_ptr, iovcnt)
	if validation_error != 0 {
		return errno.err, validation_error
	}

	offset := split_offset(pos_low, pos_high)
	if offset == -1 {
		return syscall_linux_writev(gpr_state, fdnum, iov_ptr, iovcnt)
	}
	if offset < 0 {
		return errno.err, errno.einval
	}

	mut checked_fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or {
		return errno.err, errno.get()
	}
	checked_fd.unref()

	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		iov := read_linux_iov(iov_ptr, i) or { return errno.err, errno.efault }
		if iov.len == 0 {
			continue
		}
		if total > u64(0x7fffffffffffffff) - u64(offset)
			|| iov.len > u64(0x7fffffffffffffff) - u64(offset) - total {
			return if total > 0 { total, u64(0) } else { errno.err, errno.einval }
		}
		ret, err := file.syscall_pwrite(gpr_state, fdnum, voidptr(iov.base), iov.len,
			offset + i64(total))
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

// faccessat has no flags argument at syscall 48.  Calling the five-argument
// VFS handler directly let an arbitrary live x3 register become flags.
fn syscall_linux_faccessat(gpr_state voidptr, dirfd int, path charptr, mode u32) (u64, u64) {
	if mode & ~u32(0x7) != 0 {
		return errno.err, errno.einval
	}
	return fs.syscall_faccessat(gpr_state, dirfd, path, mode, 0)
}

fn syscall_linux_faccessat2(gpr_state voidptr, dirfd int, path charptr, mode u32, flags int) (u64, u64) {
	// R_OK | W_OK | X_OK; AT_EACCESS, AT_SYMLINK_NOFOLLOW, AT_EMPTY_PATH.
	if mode & ~u32(0x7) != 0 || flags & ~0x1300 != 0 {
		return errno.err, errno.einval
	}
	mut first := u8(0)
	if !usercopy.copy_from_user(voidptr(&first), u64(path), 1) {
		return errno.err, errno.efault
	}
	if first == 0 {
		if flags & fs.at_empty_path == 0 {
			return errno.err, errno.enoent
		}
		if dirfd == fs.at_fdcwd {
			return 0, 0
		}
		mut checked_fd := file.fd_from_fdnum(unsafe { nil }, dirfd) or {
			return errno.err, errno.get()
		}
		checked_fd.unref()
		return 0, 0
	}
	return fs.syscall_faccessat(gpr_state, dirfd, path, mode, flags)
}

struct LinuxOpenHow {
	flags   u64
	mode    u64
	resolve u64
}

const linux_o_noatime = 0o1000000

const linux_o_tmpfile_bit = 0o20000000

const linux_open_flags = resource.o_accmode | resource.o_creat | resource.o_excl |
	resource.o_noctty | resource.o_trunc | resource.o_append | resource.o_nonblock |
	resource.o_dsync | resource.o_async | resource.o_direct | resource.o_largefile |
	resource.o_directory | resource.o_nofollow | linux_o_noatime | resource.o_cloexec |
	resource.o_sync | linux_o_tmpfile_bit

fn syscall_linux_openat2(gpr_state voidptr, dirfd int, path charptr, how_ptr u64, size u64) (u64, u64) {
	if size < sizeof(LinuxOpenHow) {
		return errno.err, errno.einval
	}
	if how_ptr == 0 {
		return errno.err, errno.efault
	}

	mut how := LinuxOpenHow{}
	if !usercopy.copy_from_user(voidptr(&how), how_ptr, sizeof(LinuxOpenHow)) {
		return errno.err, errno.efault
	}

	// The ABI is extensible: a larger structure is accepted when every byte
	// unknown to this kernel is zero, and rejected with E2BIG otherwise.
	if size > sizeof(LinuxOpenHow) {
		if size > page_size {
			return errno.err, errno.e2big
		}
		mut extra := [64]u8{}
		mut offset := u64(sizeof(LinuxOpenHow))
		for offset < size {
			mut chunk := size - offset
			if chunk > u64(extra.len) {
				chunk = u64(extra.len)
			}
			if !usercopy.copy_from_user(voidptr(&extra[0]), how_ptr + offset, chunk) {
				return errno.err, errno.efault
			}
			for i := u64(0); i < chunk; i++ {
				if extra[i] != 0 {
					return errno.err, errno.e2big
				}
			}
			offset += chunk
		}
	}

	if how.flags & ~u64(linux_open_flags) != 0 || how.mode & ~u64(0o7777) != 0 {
		return errno.err, errno.einval
	}
	if how.resolve != 0 {
		// Ignoring a path-resolution constraint would turn a security request
		// into an unrestricted open.
		return errno.err, errno.eopnotsupp
	}
	if how.flags & u64(resource.o_path) != 0 {
		path_flags := resource.o_path | resource.o_directory | resource.o_nofollow |
			resource.o_cloexec
		if how.flags & ~u64(path_flags) != 0 {
			return errno.err, errno.einval
		}
	}
	if how.flags & u64(linux_o_tmpfile_bit) != 0 {
		return errno.err, errno.eopnotsupp
	}
	if how.mode != 0 && how.flags & u64(resource.o_creat) == 0 {
		return errno.err, errno.einval
	}

	return fs.syscall_openat(gpr_state, dirfd, path, int(how.flags), u32(how.mode))
}

fn syscall_linux_getrlimit(gpr_state voidptr, which_resource int, old_limit u64) (u64, u64) {
	return syscall_linux_prlimit64(gpr_state, 0, which_resource, 0, old_limit)
}

fn syscall_linux_setrlimit(gpr_state voidptr, which_resource int, new_limit u64) (u64, u64) {
	return syscall_linux_prlimit64(gpr_state, 0, which_resource, new_limit, 0)
}

fn syscall_linux_getcpu(_ voidptr, cpu_ptr u64, node_ptr u64, _cache u64) (u64, u64) {
	cpu_number := u32(cpu.read_tpidr_el1())
	node := u32(0)
	if cpu_ptr != 0 && !usercopy.copy_to_user(cpu_ptr, voidptr(&cpu_number), sizeof(u32)) {
		return errno.err, errno.efault
	}
	if node_ptr != 0 && !usercopy.copy_to_user(node_ptr, voidptr(&node), sizeof(u32)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

fn syscall_linux_sched_rr_get_interval(_ voidptr, pid int, interval_ptr u64) (u64, u64) {
	if pid < 0 {
		return errno.err, errno.einval
	}
	if interval_ptr == 0 {
		return errno.err, errno.efault
	}
	if pid != 0 {
		proc.lock_table()
		exists := proc.process_at(pid) != unsafe { nil }
		proc.unlock_table()
		if !exists {
			return errno.err, errno.esrch
		}
	}
	// The scheduler's ordinary round-robin timeslice is five milliseconds.
	interval := time.TimeSpec{
		tv_nsec: 5000000
	}
	if !usercopy.copy_to_user(interval_ptr, voidptr(&interval), sizeof(time.TimeSpec)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// membarrier is first and foremost a feature-discovery ABI.  Vinix does not
// yet have the cross-CPU rendezvous needed to promise any of Linux's barrier
// commands, so report an empty supported-command mask.  This is preferable to
// ENOSYS: runtimes can cache the result and select their documented fallback.
fn syscall_linux_membarrier(_ voidptr, command int, flags u32, _cpu_id int) (u64, u64) {
	if command == 0 { // MEMBARRIER_CMD_QUERY
		if flags != 0 {
			return errno.err, errno.einval
		}
		return 0, 0
	}
	return errno.err, errno.einval
}
