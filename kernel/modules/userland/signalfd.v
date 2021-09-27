module userland

import resource
import stat
import klock
import event.eventstruct
import proc
import file
import errno

struct SFDSiginfo {
	ssi_signo u32
	ssi_errno i32
	ssi_code i32
	ssi_pid u32
	ssi_uid u32
	ssi_fd i32
	ssi_tid u32
	ssi_band u32
	ssi_overrun u32
	ssi_trapno u32
	ssi_status i32
	ssi_int i32
	ssi_ptr u64
	ssi_utime u64
	ssi_stime u64
	ssi_addr u64
	ssi_addr_lsb u16
	pad [46]u8
}

struct SignalFD {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	status   int
	can_mmap bool
	event    eventstruct.Event

	mask u64
	queue []&SFDSiginfo
}

fn (mut this SignalFD) mmap(page u64, flags int) voidptr {
	panic('')
}

fn (mut this SignalFD) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return error('')
}

fn (mut this SignalFD) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return error('')
}

fn (mut this SignalFD) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return error('')
}

fn (mut this SignalFD) unref(handle voidptr) ? {
	return error('')
}

fn (mut this SignalFD) grow(handle voidptr, new_size u64) ? {
	return error('')
}

fn (mut this SignalFD) bind(handle voidptr, _addr voidptr, addrlen u64) ? {
	return resource.default_bind(handle, _addr, addrlen)
}

fn (mut this SignalFD) listen(handle voidptr, backlog int) ? {
	return resource.default_listen(handle, backlog)
}

pub fn syscall_signalfd(_ voidptr, fdnum int, mask u64, flags int) (u64, u64) {
	C.printf(c'\n\e[32mstrace\e[m: signalfd(%d, 0x%llx, 0x%x)\n', fdnum, mask, flags)
	defer {
		C.printf(c'\e[32mstrace\e[m: returning\n')
	}

	mut signalfd := &SignalFD(0)
	mut newfd := int(0)

	mut thread := proc.current_thread()

	thread.signalfds_lock.acquire()
	defer {
		thread.signalfds_lock.release()
	}

	if fdnum == -1 {
		signalfd = &SignalFD{refcount: 1}

		newfd = file.fdnum_create_from_resource(voidptr(0), mut signalfd, flags, 0, false) or {
			return -1, errno.get()
		}

		thread.signalfds << voidptr(signalfd)
	} else {
		mut fd := file.fd_from_fdnum(voidptr(0), fdnum) or {
			return -1, errno.get()
		}

		signalfd = unsafe { &SignalFD(fd.handle.resource) }

		fd.unref()

		newfd = fdnum
	}

	signalfd.mask = mask

	return u64(newfd), 0
}
