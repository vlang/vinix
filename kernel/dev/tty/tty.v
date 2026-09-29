module tty

import dev.console
import dev.pty
import errno
import event.eventstruct
import fs
import katomic
import klock
import proc
import resource
import stat

// /dev/tty: whichever terminal controls the session of the process opening
// it. Nothing is ever read or written through this node itself; open hands
// back the terminal, so every descriptor opened here is one on that terminal.
struct DevTty {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this DevTty) open(flags int) ?&resource.Resource {
	session := proc.current_thread().process.tty_session
	if terminal := pty.open_session_terminal(session, flags) {
		return terminal
	}
	if terminal := console.session_terminal(session) {
		return terminal
	}
	// No controlling terminal, as for a daemon or a process that has called
	// setsid(2) since.
	errno.set(errno.enxio)
	return none
}

fn (mut this DevTty) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

fn (mut this DevTty) read(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.enxio)
	return none
}

fn (mut this DevTty) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.enxio)
	return none
}

fn (mut this DevTty) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this DevTty) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this DevTty) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this DevTty) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this DevTty) grow(_handle voidptr, _new_size u64) ? {
}

pub fn initialise() {
	mut device := &DevTty{}
	device.stat.blksize = 4096
	device.stat.rdev = resource.create_dev_id()
	device.stat.mode = 0o666 | stat.ifchr
	fs.devtmpfs_add_device(device, 'tty')
}
