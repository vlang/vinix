// signalfd.v: Userspace signals.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module userland

import stat
import klock
import event.eventstruct
import proc
import file
import errno

struct SFDSiginfo {
	ssi_signo    u32
	ssi_errno    i32
	ssi_code     i32
	ssi_pid      u32
	ssi_uid      u32
	ssi_fd       i32
	ssi_tid      u32
	ssi_band     u32
	ssi_overrun  u32
	ssi_trapno   u32
	ssi_status   i32
	ssi_int      i32
	ssi_ptr      u64
	ssi_utime    u64
	ssi_stime    u64
	ssi_addr     u64
	ssi_addr_lsb u16
	pad          [46]u8
}

struct SignalFD {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event

	mask  u64
	queue []&SFDSiginfo
}

fn (mut this SignalFD) mmap(page u64, flags int) voidptr {
	panic('')
}

fn (mut this SignalFD) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return none
}

fn (mut this SignalFD) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return none
}

fn (mut this SignalFD) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return none
}

fn (mut this SignalFD) unref(handle voidptr) ? {
	return none
}

fn (mut this SignalFD) link(handle voidptr) ? {
	return none
}

fn (mut this SignalFD) unlink(handle voidptr) ? {
	return none
}

fn (mut this SignalFD) grow(handle voidptr, new_size u64) ? {
	return none
}

pub fn syscall_signalfd(_ voidptr, fdnum int, mask u64, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: signalfd(%d, 0x%llx, 0x%x)\n', process.name.str, fdnum, mask, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut signalfd := &SignalFD(unsafe { nil })
	mut newfd := int(0)

	mut t := proc.current_thread()

	t.signalfds_lock.acquire()
	defer {
		t.signalfds_lock.release()
	}

	if fdnum == -1 {
		signalfd = &SignalFD{
			refcount: 1
		}

		newfd = file.fdnum_create_from_resource(unsafe { nil }, mut signalfd, flags, 0, false) or {
			return errno.err, errno.get()
		}

		t.signalfds << voidptr(signalfd)
	} else {
		mut fd := file.fd_from_fdnum(unsafe { nil }, fdnum) or { return errno.err, errno.get() }

		signalfd = unsafe { &SignalFD(fd.handle.resource) }

		fd.unref()

		newfd = fdnum
	}

	signalfd.mask = mask

	return u64(newfd), 0
}
