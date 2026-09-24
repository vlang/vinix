module resource

import katomic

// Optional capabilities keep stream/device resources and in-memory files from
// needing dummy callbacks merely because disk-backed resources cache writes.
pub interface SyncableResource {
	Resource
mut:
	sync(handle voidptr) ?
}

pub interface AdvisableResource {
	Resource
mut:
	advise(handle voidptr, offset u64, length u64, advice int) ?
}

// Anonymous pipes expose their buffer size through fcntl rather than stat.
// Keep that optional operation out of Resource so ordinary files and devices
// do not need dummy pipe-capacity methods.
pub interface PipeCapacityResource {
mut:
	pipe_capacity() u64
	set_pipe_capacity(requested u64) ?u64
}

// Disk filesystems use this hook after the VFS changes ownership, mode or
// timestamps in the common Stat object. In-memory resources need no callback.
pub interface MetadataResource {
	Resource
mut:
	persist_metadata() ?
}

// File-backed mappings may keep physical pages outside the block-device cache.
// These optional hooks let msync/fsync write those pages back and let the VM
// return disposable MAP_PRIVATE pages when the final mapping goes away.
pub interface MappingSyncResource {
	Resource
mut:
	sync_mapping(handle voidptr, offset u64, length u64) ?
}

pub interface MappingReleaseResource {
mut:
	release_mapping(handle voidptr, page u64, physical voidptr, flags int)
}

pub struct FileSystemStat {
pub mut:
	@type   u64
	bsize   u64
	blocks  u64
	bfree   u64
	bavail  u64
	files   u64
	ffree   u64
	namelen u64 = 255
	frsize  u64
	flags   u64
}

pub interface FileSystemStatResource {
mut:
	filesystem_stat() FileSystemStat
}

pub fn sync_resource(mut res Resource, handle voidptr) ? {
	if mut res is SyncableResource {
		res.sync(handle) or { return none }
	}
}

pub fn sync_mapping(mut res Resource, handle voidptr, offset u64, length u64) ? {
	if mut res is MappingSyncResource {
		res.sync_mapping(handle, offset, length)?
	}
}

pub fn release_mapping(mut res Resource, handle voidptr, page u64, physical voidptr, flags int) {
	if mut res is MappingReleaseResource {
		res.release_mapping(handle, page, physical, flags)
	}
}

// Mappings created directly by the ELF loader have no open-file Handle to
// retain. Keep the underlying inode alive until their final global range is
// destroyed, including after the executable has been unlinked.
pub fn retain_resource(mut res Resource) {
	katomic.inc(mut &res.refcount)
}

pub fn release_resource(mut res Resource) {
	res.unref(unsafe { nil }) or {}
}

pub fn advise_resource(mut res Resource, handle voidptr, offset u64, length u64, advice int) ? {
	if mut res is AdvisableResource {
		res.advise(handle, offset, length, advice) or { return none }
	}
}

pub fn pipe_capacity(mut res Resource) ?u64 {
	if mut res is PipeCapacityResource {
		return res.pipe_capacity()
	}
	return none
}

pub fn set_pipe_capacity(mut res Resource, requested u64) ?u64 {
	if mut res is PipeCapacityResource {
		return res.set_pipe_capacity(requested)
	}
	return none
}

pub fn persist_metadata(mut res Resource) ? {
	if mut res is MetadataResource {
		res.persist_metadata()?
	}
}

// A shared file mapping backed by a movable buffer must reserve its whole
// extent before any page of it is handed out: a later per-page fault that grew
// the buffer would move the pages already mapped. tmpfs implements this; a
// resource whose pages never move does not need to.
pub interface ReservableMapping {
mut:
	reserve_shared_mapping(offset u64, length u64) bool
}

pub fn reserve_shared_mapping(mut res Resource, offset u64, length u64) bool {
	if mut res is ReservableMapping {
		return res.reserve_shared_mapping(offset, length)
	}
	return true
}

// memfd seals, from fcntl(F_ADD_SEALS/F_GET_SEALS). Only a memfd is sealable;
// every other resource answers EINVAL.
pub interface SealableResource {
mut:
	get_seals() ?u32
	add_seals(seals u32) ?
}

pub fn get_seals(mut res Resource) ?u32 {
	if mut res is SealableResource {
		return res.get_seals()
	}
	return none
}

pub fn add_seals(mut res Resource, seals u32) ? {
	if mut res is SealableResource {
		res.add_seals(seals)?
		return
	}
	return none
}

pub fn filesystem_stat(mut res Resource) FileSystemStat {
	if mut res is FileSystemStatResource {
		return res.filesystem_stat()
	}
	return FileSystemStat{
		@type:   0
		bsize:   4096
		namelen: 255
		frsize:  4096
	}
}
