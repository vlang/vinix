module fs

// This is a stub
import resource
import stat
import klock
import file
import errno
import event.eventstruct
import proc

struct INotify {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

fn (mut this INotify) mmap(page u64, flags int) voidptr {
	return unsafe { nil }
}

fn (mut this INotify) read(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return none
}

fn (mut this INotify) write(handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	return none
}

fn (mut this INotify) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this INotify) unref(handle voidptr) ? {
	return none
}

fn (mut this INotify) link(handle voidptr) ? {
	return none
}

fn (mut this INotify) unlink(handle voidptr) ? {
	return none
}

fn (mut this INotify) grow(handle voidptr, new_size u64) ? {
	return none
}

pub fn syscall_inotify_init(_ voidptr, flags int) (u64, u64) {
	mut current_thread := proc.current_thread()
	mut process := current_thread.process

	C.printf(c'\n\e[32m%s\e[m: inotify_init(%d)\n', process.name.str, flags)
	defer {
		C.printf(c'\e[32m%s\e[m: returning\n', process.name.str)
	}

	mut inotify := &INotify{
		refcount: 1
	}

	fdnum := file.fdnum_create_from_resource(unsafe { nil }, mut inotify, 0, 0, false) or {
		return errno.err, errno.get()
	}

	return u64(fdnum), 0
}
