@[has_globals]
module ext2

import katomic
import klock
import memory

#flag -Dvinix_stack_alloc=__builtin_alloca
fn C.vinix_stack_alloc(bytes u64) voidptr

const page_size = u64(4096)
const higher_half = u64(0)

struct TestStat {
mut:
	ino u64
	mode u32 = 0x8000
	size i64
	blocks u64
	mtim TestTime
	ctim TestTime
}
struct TestTime { mut: tv_sec i64 tv_nsec i64 }
struct EXT2Filesystem {
mut:
	l klock.Lock
	bytes [4096]u8
	fail_read bool
	fail_write bool
	short_write bool
	read_only bool
	writes int
	during_write fn () = unsafe { nil }
}
struct EXT2Inode {
mut:
	size32l u32 = 4096
	size32h u32
	sector_cnt u64
	mod_time i64
	creation_time i64
}
fn (inode &EXT2Inode) size() u64 { return u64(inode.size32l) | (u64(inode.size32h) << 32) }
struct EXT2Resource {
mut:
	l klock.Lock
	filesystem &EXT2Filesystem
	stat TestStat
	refcount int = 1
	mapped_pages []&EXT2MappedPage
	mapped_previous &EXT2Resource = unsafe { nil }
	mapped_next &EXT2Resource = unsafe { nil }
	mapped_serial u64
	mapped_registered bool
	freed bool
}

fn (mut inode EXT2Inode) read_entry(mut filesystem EXT2Filesystem, _ino u32) ? {
	if filesystem.fail_read { return none }
}
fn (mut inode EXT2Inode) read(mut filesystem EXT2Filesystem, bytes voidptr, offset u64, count u64) ?i64 {
	if filesystem.fail_read { return none }
	unsafe { C.memcpy(bytes, &filesystem.bytes[offset], count) }
	return i64(count)
}
fn (mut inode EXT2Inode) write(mut filesystem EXT2Filesystem, bytes voidptr, _ino u32, offset u64, count u64) ?i64 {
	// Registry callbacks must execute with the registry lock released.
	assert mapped_resources_lock.test_and_acquire()
	mapped_resources_lock.release()
	if filesystem.fail_write { return none }
	if filesystem.short_write { return i64(count / 2) }
	filesystem.writes++
	unsafe { C.memcpy(&filesystem.bytes[offset], bytes, count) }
	if filesystem.during_write != unsafe { nil } {
		hook := filesystem.during_write
		filesystem.during_write = unsafe { nil }
		hook()
	}
	return i64(count)
}
fn (mut resource EXT2Resource) unref(_handle voidptr) ? {
	assert resource.l.test_and_acquire()
	resource.l.release()
	assert resource.filesystem.l.test_and_acquire()
	resource.filesystem.l.release()
	assert mapped_resources_lock.test_and_acquire()
	mapped_resources_lock.release()
	if katomic.dec(mut &resource.refcount) { return }
	assert !resource.mapped_registered && resource.mapped_pages.len == 0
	resource.freed = true
}
fn flush_on_return() {}

fn mapped_resource() &EXT2Resource {
	mut resource := &EXT2Resource{filesystem: &EXT2Filesystem{}, stat: TestStat{size: 4096}}
	resource.mapped_pages.flags |= .noslices
	resource.mapped_pages << &EXT2MappedPage{
		physical: memory.pmm_alloc_fallible(1)
		refs: 1
		shared_dirty: true
	}
	resource.register_mapped_resource()
	return resource
}

fn test_private_clean_pages_share_pmm_refs_and_release_cache_owner_after_fork() {
	mut item := &EXT2Resource{filesystem: &EXT2Filesystem{}, stat: TestStat{size: 4096}}
	item.filesystem.bytes[17] = 0x83
	first := item.mmap(unsafe { nil }, 0, 2)
	second := item.mmap(unsafe { nil }, 0, 2)
	assert first != unsafe { nil } && first == second
	assert memory.pmm_refcount(first) == 3 && memory.live_pages == 1
	assert item.mapped_pages[0].refs == 0 && !item.mapped_pages[0].shared_dirty
	assert item.private_mapping_cow()
	// Private clean pages cause no inode or data I/O on global writeback.
	item.filesystem.fail_read = true
	assert sync_mapped_resources() && item.filesystem.writes == 0
	assert memory.pmm_retain(first, 1) // fork's additional private global
	item.release_mapping(unsafe { nil }, 0, first, 2)
	assert memory.pmm_refcount(first) == 3 && item.mapped_registered
	item.release_mapping(unsafe { nil }, 0, second, 2)
	assert memory.pmm_refcount(first) == 2
	item.release_mapping(unsafe { nil }, 0, first, 2)
	assert item.mapped_pages.len == 0 && !item.mapped_registered
	assert memory.live_pages == 0 && item.refcount == 1
	dispose(mut item)
}

fn test_read_only_release_keeps_private_readers_and_skips_writeback() {
	mut item := &EXT2Resource{filesystem: &EXT2Filesystem{read_only: true}, stat: TestStat{size: 4096}}
	item.filesystem.bytes[17] = 0x83
	first := item.mmap(unsafe { nil }, 0, 2)
	second := item.mmap(unsafe { nil }, 0, 2)
	shared_page := item.mmap(unsafe { nil }, 0, 1)
	assert first != unsafe { nil } && first == second && first == shared_page
	assert memory.pmm_refcount(first) == 3 && item.mapped_pages[0].refs == 1
	// A read-only MAP_SHARED page cannot dirty the immutable backend. Even
	// when metadata/device access now fails, release must retain every
	// private reader until its own physical reference has been returned.
	item.filesystem.fail_read = true
	item.filesystem.fail_write = true
	item.release_mapping(unsafe { nil }, 0, shared_page, 1)
	assert item.mapped_pages.len == 1 && memory.pmm_refcount(first) == 3
	assert !item.mapped_pages[0].shared_dirty && item.filesystem.writes == 0
	item.release_mapping(unsafe { nil }, 0, first, 2)
	assert item.mapped_pages.len == 1 && memory.pmm_refcount(second) == 2
	assert unsafe { (&u8(second))[17] } == 0x83
	item.release_mapping(unsafe { nil }, 0, second, 2)
	assert item.mapped_pages.len == 0 && !item.mapped_registered
	assert memory.live_pages == 0 && item.refcount == 1 && item.filesystem.writes == 0
	dispose(mut item)
}

fn test_shared_and_private_cache_ownership_keeps_failed_dirty_page_for_retry() {
	mut item := &EXT2Resource{filesystem: &EXT2Filesystem{}, stat: TestStat{size: 4096}}
	private := item.mmap(unsafe { nil }, 0, 2)
	shared_page := item.mmap(unsafe { nil }, 0, 1)
	assert private == shared_page && memory.pmm_refcount(private) == 2
	change(item, 0x51)
	item.filesystem.fail_write = true
	item.release_mapping(unsafe { nil }, 0, shared_page, 1)
	assert item.mapped_pages[0].refs == 0 && item.mapped_pages[0].shared_dirty
	item.release_mapping(unsafe { nil }, 0, private, 2)
	assert memory.pmm_refcount(private) == 1 && item.mapped_registered
	item.filesystem.fail_write = false
	assert sync_mapped_resources()
	assert item.filesystem.bytes[17] == 0x51 && memory.live_pages == 0
	dispose(mut item)
}

fn test_private_eof_and_detached_cow_pages_are_disposable() {
	mut item := &EXT2Resource{filesystem: &EXT2Filesystem{}, stat: TestStat{size: 4096}}
	past_eof := item.mmap(unsafe { nil }, 1, 2)
	assert past_eof != unsafe { nil } && item.mapped_pages.len == 0
	assert memory.pmm_refcount(past_eof) == 1
	item.release_mapping(unsafe { nil }, 1, past_eof, 2)
	copy := memory.pmm_alloc_fallible(1)
	item.release_mapping(unsafe { nil }, 0, copy, 2)
	assert memory.live_pages == 0
	dispose(mut item)
}
fn change(resource &EXT2Resource, byte u8) {
	unsafe { (&u8(resource.mapped_pages[0].physical))[17] = byte }
}
fn release(mut resource EXT2Resource) {
	physical := resource.mapped_pages[0].physical
	resource.release_mapping(unsafe { nil }, 0, physical, 1)
}
fn dispose(mut resource EXT2Resource) {
	if !resource.freed { resource.unref(unsafe { nil }) or { panic('unref') } }
	assert resource.freed
	unsafe { resource.mapped_pages.free(); free(resource.filesystem); free(resource) }
}

fn test_live_mapping_rewrites_after_sync_and_drops_registry_ref_outside_locks() {
	mut resource := mapped_resource()
	assert resource.refcount == 2
	change(resource, 0x31)
	assert sync_mapped_resources()
	assert resource.filesystem.bytes[17] == 0x31
	change(resource, 0x72)
	assert sync_mapped_resources()
	assert resource.filesystem.bytes[17] == 0x72 && resource.filesystem.writes == 2
	release(mut resource)
	assert !resource.mapped_registered && resource.refcount == 1
	dispose(mut resource)
	assert memory.live_pages == 0
}

fn test_failed_final_unmap_holds_unlinked_inode_and_retries_without_stranding_others() {
	for mode in 0 .. 3 {
		mut broken := mapped_resource()
		mut healthy := mapped_resource()
		change(broken, 0x93)
		change(healthy, 0xa4)
		broken.filesystem.fail_read = mode == 0
		broken.filesystem.fail_write = mode == 1
		broken.filesystem.short_write = mode == 2
		release(mut broken)
		assert broken.mapped_registered && broken.mapped_pages[0].refs == 0
		// Close/unlink the last non-registry owner, as the VM does on teardown.
		broken.unref(unsafe { nil }) or { panic('unref') }
		assert broken.refcount == 1 && !broken.freed
		assert !sync_mapped_resources()
		assert broken.refcount == 1 && !broken.freed
		assert healthy.filesystem.bytes[17] == 0xa4
		broken.filesystem.fail_read = false
		broken.filesystem.fail_write = false
		broken.filesystem.short_write = false
		assert sync_mapped_resources()
		assert broken.freed && broken.filesystem.bytes[17] == 0x93
		dispose(mut broken)
		release(mut healthy)
		dispose(mut healthy)
	}
	assert memory.live_pages == 0 && mapped_resources_first == unsafe { nil }
}

__global (new_registration &EXT2Resource = unsafe { nil })
fn register_during_write() { new_registration = mapped_resource(); change(new_registration, 0xd6) }

fn test_batched_sweep_bounds_new_registrations_and_repeated_mapping_lifetimes() {
	mut resources := []&EXT2Resource{cap: 40}
	for _ in 0 .. 40 { resources << mapped_resource() }
	resources[0].filesystem.during_write = register_during_write
	assert sync_mapped_resources()
	for item in resources { assert item.filesystem.writes == 1 && item.refcount == 2 }
	assert new_registration.filesystem.writes == 0
	assert sync_mapped_resources()
	assert new_registration.filesystem.bytes[17] == 0xd6
	for mut item in resources { release(mut item); dispose(mut item) }
	release(mut new_registration)
	dispose(mut new_registration)
	unsafe { resources.free() }
	for _ in 0 .. 1000 {
		mut item := mapped_resource()
		release(mut item)
		dispose(mut item)
	}
	assert memory.live_pages == 0 && mapped_resources_first == unsafe { nil }
}
