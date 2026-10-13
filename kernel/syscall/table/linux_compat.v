// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module table

// Linux compatibility calls which do not map one-for-one onto an existing
// Vinix syscall. musl exposes these directly (notably the vectored
// positioned-I/O family), so their argument layout must follow the kernel ABI
// rather than the C library function prototype. The layout is the same on
// arm64 and x86-64.

import errno
import file
import fs
import proc
import resource
import stat
import time
import usercopy

// Native arm64/x86-64 pass the complete loff_t in pos_l. Linux's pos_from_hilo
// shifts pos_h by BITS_PER_LONG, so that argument contributes nothing here.
// Splitting two 32-bit halves is the compat ABI, not either native ABI.
fn native_vector_offset(low u64, _high u64) i64 {
	return i64(low)
}

fn syscall_linux_preadv(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int, pos_low u64, pos_high u64) (u64, u64) {
	// Only v2 gives -1 the current-position meaning.
	if native_vector_offset(pos_low, pos_high) < 0 { return errno.err, errno.einval }
	return syscall_linux_preadv2(gpr_state, fdnum, iov_ptr, iovcnt, pos_low, pos_high,
		0)
}

fn syscall_linux_pwritev(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int, pos_low u64, pos_high u64) (u64, u64) {
	if native_vector_offset(pos_low, pos_high) < 0 { return errno.err, errno.einval }
	return syscall_linux_pwritev2(gpr_state, fdnum, iov_ptr, iovcnt, pos_low, pos_high,
		0)
}

fn syscall_linux_preadv2(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int, pos_low u64, pos_high u64, flags u32) (u64, u64) {
	offset := native_vector_offset(pos_low, pos_high)
	if offset < -1 { return errno.err, errno.einval }

	if offset == -1 {
		return linux_readv_flags(gpr_state, fdnum, iov_ptr, iovcnt, flags)
	}
	return linux_positioned_iov(fdnum, iov_ptr, iovcnt, offset, false, flags)
}

fn syscall_linux_pwritev2(gpr_state voidptr, fdnum int, iov_ptr u64, iovcnt int, pos_low u64, pos_high u64, flags u32) (u64, u64) {
	offset := native_vector_offset(pos_low, pos_high)
	if offset < -1 { return errno.err, errno.einval }

	if offset == -1 {
		return linux_writev_flags(gpr_state, fdnum, iov_ptr, iovcnt, flags)
	}
	return linux_positioned_iov(fdnum, iov_ptr, iovcnt, offset, true, flags)
}

// Keep the selected open description and the imported headers through every
// segment. Descriptor/access and pipe/socket seek errors precede header import,
// including for empty vectors. Validate the aggregate position before I/O.
fn linux_positioned_iov(fdnum int, iov_ptr u64, iovcnt int, offset i64, write bool, flags u32) (u64, u64) {
	mut fd := file.fd_from_fdnum(unsafe { nil }, int(u32(fdnum))) or {
		return errno.err, errno.get()
	}
	defer { fd.unref() }
	if fd.handle.flags & resource.o_path != 0 { return errno.err, errno.ebadf }
	mode := fd.handle.resource.stat.mode
	if stat.isifo(mode) || stat.issock(mode) || mode & stat.ifmt == stat.ifpipe {
		return errno.err, errno.espipe
	}
	access_error := linux_iov_access_error(fd, write)
	if access_error != 0 { return errno.err, access_error }
	fast := C.vinix_stack_alloc(linux_iov_fast * sizeof(LinuxIOVec))
	vector := import_linux_iov(iov_ptr, iovcnt, fast) or { return errno.err, errno.get() }
	defer { vector.release() }
	if vector.total == 0 { return 0, 0 }
	if vector.total > u64(0x7fffffffffffffff) - u64(offset) { return errno.err, errno.einval }
	if flags != 0 {
		fd.handle.mac_check(if write { proc.mac_write } else { proc.mac_read }) or { return errno.err, errno.get() }
		return errno.err, errno.eopnotsupp
	}

	mut total := u64(0)
	for i := 0; i < iovcnt; i++ {
		iov := unsafe { vector.data[i] }
		if iov.len == 0 {
			continue
		}
		ret, err := if write {
			file.pwrite_pinned_descriptor(mut fd, voidptr(iov.base), iov.len, offset + i64(total))
		} else {
			file.pread_pinned_descriptor(mut fd, voidptr(iov.base), iov.len, offset + i64(total), true)
		}
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

// faccessat has no flags argument (syscall 48 on arm64, 269 on x86-64).
// Calling the five-argument VFS handler directly let an arbitrary live x3
// register become flags.
fn syscall_linux_faccessat(gpr_state voidptr, dirfd int, path charptr, mode u32) (u64, u64) {
	if mode & ~u32(0x7) != 0 {
		return errno.err, errno.einval
	}
	return fs.syscall_faccessat(gpr_state, dirfd, path, mode, 0)
}

// Linux only defines the low 32 bits of arguments declared as C `int` at the
// syscall boundary. In particular, qemu-user passes AT_FDCWD as 0xffffff9c
// when translating the x86 open syscall. Keep the boundary parameters i32 so
// V3 performs the required truncation before VFS compares dirfd with -100.
fn syscall_linux_openat(gpr_state voidptr, dirfd i32, path charptr, flags i32, mode u32) (u64, u64) {
	return fs.syscall_openat(gpr_state, int(dirfd), path, int(flags), mode)
}

fn syscall_linux_faccessat2(gpr_state voidptr, dirfd int, path charptr, mode u32, flags int) (u64, u64) {
	// R_OK | W_OK | X_OK; AT_EACCESS, AT_SYMLINK_NOFOLLOW, AT_EMPTY_PATH.
	if mode & ~u32(0x7) != 0 || flags & ~0x1300 != 0 {
		return errno.err, errno.einval
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
	resolve_known := u64(0x3f) // NO_XDEV|NO_MAGICLINKS|NO_SYMLINKS|BENEATH|IN_ROOT|CACHED
	if how.resolve & ~resolve_known != 0 || how.resolve & 0x18 == 0x18 {
		// Unknown bits and mutually exclusive BENEATH|IN_ROOT are invalid.
		return errno.err, errno.einval
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
	// Link constraints apply throughout the actual VFS walk and creation
	// retry; mount constraints check the actual alias route. Containment and
	// cache-only lookup still lack enforcement, so combinations requesting
	// either of those are refused.
	if how.resolve & ~u64(fs.resolve_no_xdev | fs.resolve_no_symlinks | fs.resolve_no_magiclinks) != 0 {
		return errno.err, errno.eopnotsupp
	}
	return fs.syscall_openat_resolved(gpr_state, dirfd, path, int(how.flags), u32(how.mode), how.resolve)
}

fn syscall_linux_getrlimit(gpr_state voidptr, which_resource int, old_limit u64) (u64, u64) {
	return syscall_linux_prlimit64(gpr_state, 0, which_resource, 0, old_limit)
}

fn syscall_linux_setrlimit(gpr_state voidptr, which_resource int, new_limit u64) (u64, u64) {
	return syscall_linux_prlimit64(gpr_state, 0, which_resource, new_limit, 0)
}

fn syscall_linux_sched_rr_get_interval(_ voidptr, pid int, interval_ptr u64) (u64, u64) {
	if interval_ptr == 0 {
		return errno.err, errno.efault
	}
	tid := sched_target_tid(pid) or { return errno.err, sched_target_errno(pid) }
	params := proc.thread_sched_params(tid) or { return errno.err, errno.get() }

	// Only SCHED_RR rotates on a quantum. Every other policy has none to
	// report, and says so with a zero interval, as Linux does.
	mut interval := time.TimeSpec{}
	if params.policy == proc.sched_rr {
		// The scheduler's round-robin timeslice is five milliseconds.
		interval.tv_nsec = 5000000
	}
	if !usercopy.copy_to_user(interval_ptr, voidptr(&interval), sizeof(time.TimeSpec)) {
		return errno.err, errno.efault
	}
	return 0, 0
}

// No eBPF interpreter, verifier, attachment or device-cgroup enforcement is
// implemented. Report the Linux absent-syscall error so callers can select an
// explicit fallback or refuse to launch. A dummy descriptor must never make a
// sandbox believe that its access policy was installed.
fn syscall_linux_bpf(_ voidptr, _cmd int, _attr u64, _size u32) (u64, u64) {
	return errno.err, errno.enosys
}

// Runtimes discover barrier support through QUERY and select their fallback.
// There is no cross-CPU rendezvous implementing any of Linux's commands yet.
fn syscall_linux_membarrier(_ voidptr, command int, flags u32, _cpu_id int) (u64, u64) {
	if command == 0 { // MEMBARRIER_CMD_QUERY
		if flags != 0 {
			return errno.err, errno.einval
		}
		return 0, 0
	}
	return errno.err, errno.einval
}
