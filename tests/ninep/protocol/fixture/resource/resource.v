@[has_globals]
module resource

import stat
import klock
import event.eventstruct

pub const o_path = 0o10000000
pub const o_rdonly = 0
pub const o_wronly = 1
pub const o_rdwr = 2

fn C.vinix_stack_alloc(usize) voidptr

pub interface Resource {
mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	grow(voidptr, u64) ?
	read(voidptr, voidptr, u64, u64) ?i64
	write(voidptr, voidptr, u64, u64) ?i64
	ioctl(voidptr, u64, voidptr) ?int
	unref(voidptr) ?
	link(voidptr) ?
	unlink(voidptr) ?
	mmap(voidptr, u64, int) voidptr
}

pub struct PermissionMetadata {
pub:
	mode u32
	uid  u32
	gid  u32
}

pub interface PermissionResource {
mut:
	snapshot_permissions(mut acl []u8) ?PermissionMetadata
}

pub interface OpenableResource {
mut:
	open(int) ?&Resource
}

pub interface OwnedOpenableResource {
mut:
	open_owned(int) ?&Resource
}

pub struct OpenedResource {
pub:
	resource &Resource = unsafe { nil }
	owned bool
}

pub interface MetadataResource {
mut:
	persist_metadata() ?
}

pub interface ModeResource {
mut:
	chmod_mode(mode u32) ?
}

pub interface SyncableResource {
mut:
	sync(voidptr) ?
}

pub interface AppendWriteResource {
mut:
	append_data(voidptr, voidptr, u64, u64, &u64) ?i64
}

__global device_id u64

pub fn create_dev_id() u64 {
	device_id++
	return device_id
}

pub fn default_ioctl(_ voidptr, _ u64, _ voidptr) ?int { return none }
