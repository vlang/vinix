module resource

import katomic

// Optional capabilities keep stream/device resources and in-memory files from
// needing dummy callbacks merely because disk-backed resources cache writes.
pub interface SyncableResource {
mut:
	sync(handle voidptr) ?
}

pub interface AdvisableResource {
mut:
	advise(handle voidptr, offset u64, length u64, advice int) ?
}

// Disk filesystems use this hook after the VFS changes ownership, mode or
// timestamps in the common Stat object. In-memory resources need no callback.
pub interface MetadataResource {
mut:
	persist_metadata() ?
}

// File-backed mappings may keep physical pages outside the block-device cache.
// These optional hooks let msync/fsync write those pages back and let the VM
// return disposable MAP_PRIVATE pages when the final mapping goes away.
pub interface MappingSyncResource {
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

pub fn persist_metadata(mut res Resource) ? {
	if mut res is MetadataResource {
		res.persist_metadata()?
	}
}

pub fn filesystem_stat(mut res Resource) FileSystemStat {
	if mut res is FileSystemStatResource {
		return res.filesystem_stat()
	}
	return FileSystemStat{
		@type: 0
		bsize: 4096
		namelen: 255
		frsize: 4096
	}
}
