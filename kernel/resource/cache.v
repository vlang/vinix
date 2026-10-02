module resource

import katomic
import errno

pub struct AppendResult {
pub:
	written i64
	end     u64
}

// A regular file chooses EOF, checks its size limit, and writes while one
// backend lock is held. Return the actual end so the open description does
// not retain an earlier EOF snapshot when another appender won the race.
pub interface AppendWriteResource {
mut:
	append_data(handle voidptr, buf voidptr, count u64, limit u64, end &u64) ?i64
}

pub fn append_write(mut res Resource, handle voidptr, buf voidptr, count u64, limit u64) ?AppendResult {
	if mut res is AppendWriteResource {
		// Returning a composite directly from the interface method makes V
		// promote its receiver. Primitive result plus a synchronous output
		// pointer keeps the borrowed interface and EOF value on the stack.
		mut writer := AppendWriteResource(res)
		mut stack_writer := unsafe { &writer }
		mut end := u64(0)
		written := stack_writer.append_data(handle, buf, count, limit, unsafe { &end })?
		return AppendResult{written: written, end: end}
	}
	location := u64(res.stat.size)
	if count != 0 && location >= limit {
		errno.set(errno.efbig)
		return none
	}
	allowed := if count != 0 && count > limit - location { limit - location } else { count }
	written := res.write(handle, buf, location, allowed)?
	return AppendResult{ written: written, end: location + u64(written) }
}

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

// Device mappings can own storage independently of the file descriptor and
// its ioctl handle. Keep that storage until the last VMA for this mapping is
// gone, including after GEM_CLOSE or a fork.
pub interface MappingLifetimeResource {
mut:
	retain_mapping_range(handle voidptr, offset u64, length u64, flags int) bool
	release_mapping_range(handle voidptr, offset u64, length u64, flags int)
}

pub fn retain_mapping_range(mut res Resource, handle voidptr, offset u64, length u64, flags int) bool {
	if mut res is MappingLifetimeResource {
		errno.set(errno.einval)
		mut lifetime := MappingLifetimeResource(res)
		mut stack_lifetime := unsafe { &lifetime }
		retained := stack_lifetime.retain_mapping_range(handle, offset, length, flags)
		return retained
	}
	return true
}

pub fn release_mapping_range(mut res Resource, handle voidptr, offset u64, length u64, flags int) {
	if mut res is MappingLifetimeResource {
		mut lifetime := MappingLifetimeResource(res)
		mut stack_lifetime := unsafe { &lifetime }
		stack_lifetime.release_mapping_range(handle, offset, length, flags)
	}
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
		// Direct dispatch on a narrowed mutable interface boxes it on the
		// heap once per page. The callback only needs this synchronous borrow.
		mut release := MappingReleaseResource(res)
		mut stack_release := unsafe { &release }
		stack_release.release_mapping(handle, page, physical, flags)
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
		mut backend := MetadataResource(res)
		mut stack := unsafe { &backend }
		stack.persist_metadata()?
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

// Resources with stable, independently allocated pages can leave a shared
// mapping unpopulated until a process touches each page. tmpfs uses this for
// sparse shared-memory files; disk resources still pre-fault their mappings.
pub interface LazySharedMapping {
mut:
	lazy_shared_mapping() bool
}

pub fn lazy_shared_mapping(mut res Resource) bool {
	if mut res is LazySharedMapping {
		return res.lazy_shared_mapping()
	}
	return false
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
		return res.add_seals(seals)
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

// A device aperture may contain buffers with different cache attributes.
// The driver supplies portable PTE bits for this mapping's buffer, once at
// mapping creation; aliases and inherited VMAs retain the same attributes.
pub interface MappingAttributesResource {
mut:
	mapping_attributes(handle voidptr, offset u64) u64
}

pub fn mapping_attributes(mut res Resource, handle voidptr, offset u64) u64 {
	if mut res is MappingAttributesResource {
		mut attributes := MappingAttributesResource(res)
		mut stack_attributes := unsafe { &attributes }
		// Returning the call directly makes V heap-promote the interface.
		bits := stack_attributes.mapping_attributes(handle, offset)
		return bits
	}
	return 0
}
