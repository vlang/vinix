@[has_globals]
module resource

import stat
import katomic
import klock
import ioctl
import errno
import event.eventstruct

pub const o_path = 0o10000000

pub const o_accmode = (0o03 | o_path)
pub const o_exec = o_path
pub const o_rdonly = 0o00
pub const o_rdwr = 0o02
pub const o_search = o_path
pub const o_wronly = 0o01
pub const o_append = 0o2000
pub const o_creat = 0o100
pub const o_excl = 0o200
pub const o_noctty = 0o400
pub const o_trunc = 0o1000
pub const o_nonblock = 0o4000
pub const o_dsync = 0o10000
pub const o_rsync = 0o4010000
pub const o_sync = 0o4010000
pub const o_cloexec = 0o2000000
pub const o_async = 0o20000

pub const file_creation_flags_mask = o_creat | o_directory | o_excl | o_noctty | o_nofollow | o_trunc
pub const file_descriptor_flags_mask = o_cloexec
pub const file_status_flags_mask = ~(file_creation_flags_mask | file_descriptor_flags_mask)
// What fcntl(F_SETFL) may change. The access mode and the creation flags are
// settled at open time and have to survive it.
pub const file_settable_flags_mask = o_append | o_nonblock | o_dsync | o_sync

pub interface Resource {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	grow(handle voidptr, new_size u64) ?
	read(handle voidptr, buf voidptr, loc u64, count u64) ?i64
	write(handle voidptr, buf voidptr, loc u64, count u64) ?i64
	ioctl(handle voidptr, request u64, argp voidptr) ?int
	unref(handle voidptr) ?
	link(handle voidptr) ?
	unlink(handle voidptr) ?
	mmap(handle voidptr, page u64, flags int) voidptr
}

// Device nodes such as /dev/ptmx manufacture a distinct resource for every
// open file description. Keeping this separate from Resource means ordinary
// files and fixed devices do not need a meaningless open callback.
pub interface OpenableResource {
mut:
	open(flags int) ?&Resource
}

// An immutable backend stays read-only through every mount alias. Mode bits
// and per-mount flags alone cannot describe that guarantee to a filesystem.
pub interface ReadOnlyResource {
	read_only_backend() bool
}

// Some readiness (signalfd's private signals) belongs to the calling thread.
// A descriptor retains the backend for this synchronous, borrowed callback.
pub interface PollableResource {
mut:
	poll_status() int
}

struct PollScratch {
mut:
	backend PollableResource
}

pub fn poll_status(mut res Resource) int {
	if mut res is PollableResource {
		mut scratch := unsafe { &PollScratch(C.__builtin_alloca(sizeof(PollScratch))) }
		unsafe { scratch.backend = PollableResource(res) }
		return scratch.backend.poll_status()
	}
	return res.status
}

struct ReadOnlyScratch {
mut:
	backend ReadOnlyResource
}

pub fn backend_is_read_only(mut res Resource) bool {
	if mut res is ReadOnlyResource {
		mut scratch := unsafe { &ReadOnlyScratch(C.__builtin_alloca(sizeof(ReadOnlyScratch))) }
		unsafe { scratch.backend = ReadOnlyResource(res) }
		return scratch.backend.read_only_backend()
	}
	return false
}

// A dynamic endpoint must retain its result before releasing the lookup/state
// lock. The descriptor adopts this reference instead of retaining it later.
pub interface OwnedOpenableResource {
mut:
	open_owned(flags int) ?&Resource
}

pub struct OpenedResource {
pub:
	resource &Resource = unsafe { nil }
	owned bool
}


__global (
	dev_id_counter = u64(1)
)

pub fn create_dev_id() u64 {
	return katomic.inc(mut &dev_id_counter)
}

pub fn default_ioctl(handle voidptr, request u64, _ voidptr) ?int {
	match request {
		ioctl.tcgets, ioctl.tcsets, ioctl.tiocsctty, ioctl.tiocgwinsz {
			errno.set(errno.enotty)
			return none
		}
		else {
			// Linux answers an unrecognised ioctl on something that is not a
			// terminal with ENOTTY, and callers key their fallbacks off it.
			errno.set(errno.enotty)
			return none
		}
	}
}
