@[has_globals]
module fs

import proc
import kbudget
import stat
import errno
import klock
import memory
import memory.mmap
import numa
import resource
import lib
import event.eventstruct
import katomic
import file
import sched

@[heap]
struct TmpFSResource {
pub mut:
	kernel_charge kbudget.Charge
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	mapping_id u64

	storage  &u8
	capacity u64
	// The interface box every node and descriptor of it holds, made once and
	// freed with it. Converting `this` at each use made a 384-byte box, as
	// the box carries copies of the interface's fields, that nothing freed.
	box &resource.Resource = unsafe { nil }
	// Initramfs files initially point straight into the Limine module.  The
	// module remains reserved for the life of the kernel, so keeping that
	// pointer avoids allocating and copying the whole root filesystem during
	// boot.  The first operation which can modify the backing store turns it
	// into an ordinary tmpfs allocation.
	storage_owned bool
	// memfd_create(2) files take seals; nothing else does.
	memfd bool
	// Made by create_anonymous(), with no place in any directory: a memfd,
	// a System V shared memory segment. Its link count says 1 all the same.
	nameless bool
	seals u32
	// A file with mapped cache pages can no longer live in one movable
	// buffer: growing it would relocate pages a mapping already points at.
	// It switches to a sparse list of physical pages, which stay put until
	// truncate revokes their mappings. Reservations need no frames for
	// untouched pages.
	paged bool
	pages []u64
	allocated_pages u64
	// Extended attributes, nil until one is set; see xattr.v.
	xattrs &XAttrSet = unsafe { nil }
	// chattr's immutable and append-only bits; see fs/attributes.v.
	attr_bits u32
	shared_mapping_ranges u64
	writable_mapping_ranges u64
	// Pagemap callers can query or edit policies without taking the data lock.
	policy_lock klock.Lock
	shared_policies numa.SharedPolicies
}

// Cover the resource and its interface box with room for slab rounding.
// VFS nodes and names, sparse page metadata and file contents are charged separately.
const tmpfs_resource_charge = u64(2) * (u64(sizeof(TmpFSResource)) + u64(sizeof(resource.Resource)))

__global tmpfs_mapping_sequence u64

fn (mut this TmpFSResource) attribute_bits() u32 {
	return katomic.load(&this.attr_bits)
}

fn (mut this TmpFSResource) set_attribute_bits(bits u32) ? {
	this.l.acquire()
	defer { this.l.release() }
	if bits & resource.attributes_kept != 0 && this.shared_mapping_ranges != 0 {
		errno.set(errno.ebusy)
		return none
	}
	katomic.store(mut &this.attr_bits, bits & resource.attributes_kept)
}

fn (mut this TmpFSResource) admit_mapping_range(_handle voidptr, _offset u64, _length u64,
	mut request resource.MappingAdmission) bool {
	if request.flags & mmap.map_shared == 0 { return true }
	this.l.acquire()
	defer { this.l.release() }
	if this.seals & (f_seal_write | f_seal_future_write) != 0 {
		if request.writable {
			errno.set(errno.eperm)
			return false
		}
		request.flags |= mmap.map_no_write
	}
	return this.retain_shared_range_locked(request.flags)
}

fn (mut this TmpFSResource) mapping_can_grow() bool {
	return true
}

// Each global range, and any in-flight fault using it, retains the original
// permissions. The count includes writable-capable ranges without faulted pages.
fn (mut this TmpFSResource) retain_mapping_range(_handle voidptr, _offset u64, _length u64, flags int) bool {
	if flags & mmap.map_shared == 0 { return true }
	this.l.acquire()
	defer { this.l.release() }
	return this.retain_shared_range_locked(flags)
}

fn (mut this TmpFSResource) retain_shared_range_locked(flags int) bool {
	if this.attr_bits & resource.attributes_kept != 0 {
		errno.set(errno.eperm)
		return false
	}
	this.shared_mapping_ranges++
	if flags & mmap.map_no_write == 0 {
		this.writable_mapping_ranges++
	}
	return true
}

fn (mut this TmpFSResource) release_mapping_range(_handle voidptr, _offset u64, _length u64, flags int) {
	if flags & mmap.map_shared == 0 { return }
	this.l.acquire()
	defer { this.l.release() }
	if this.shared_mapping_ranges == 0 {
		lib.kpanic(unsafe { nil }, c'tmpfs: shared mapping reference underflow')
		return
	}
	this.shared_mapping_ranges--
	if flags & mmap.map_no_write == 0 {
		if this.writable_mapping_ranges == 0 {
			lib.kpanic(unsafe { nil }, c'tmpfs: writable mapping reference underflow')
			return
		}
		this.writable_mapping_ranges--
	}
}

// A file larger than this lives in individual pages rather than in one buffer.
// Growing a buffer by doubling needs a contiguous run of physical memory as
// large as the file, which a fragmented machine eventually cannot supply, and
// the allocator panics rather than fail: runc copies its ~10 MiB binary into a
// memfd for every container it starts, and that brought the kernel down after
// a handful of containers.
//
// The limit is the largest object the heap keeps in a slab. A buffer past
// that is whole pages with a page of bookkeeping in front, and doubling made
// it a power of two besides: a file of 100 bytes took two pages, 32 KiB of
// them on a machine with 16 KiB pages, and one of 70 KiB took 132 KiB. On a
// system that runs from memory that is what a package costs to install.
// Pages hold a file of any size to within a page, and a slab object one of a
// few hundred bytes to within its size class.
const tmpfs_contiguous_limit = u64(2048)

// The smallest buffer a file is given.
const tmpfs_smallest_buffer = u64(64)

const f_seal_seal = u32(0x1)
const f_seal_shrink = u32(0x2)
const f_seal_grow = u32(0x4)
const f_seal_write = u32(0x8)
const f_seal_future_write = u32(0x10)
const f_seal_exec = u32(0x20)

// The caller holds l so execute-bit changes and seals serialize together.
fn (this &TmpFSResource) check_exec_seal_locked(mode u32) ? {
	if this.seals & f_seal_exec != 0 && (this.stat.mode ^ mode) & 0o111 != 0 {
		errno.set(errno.eperm)
		return none
	}
}

fn (mut this TmpFSResource) get_seals() ?u32 {
	if !this.memfd {
		errno.set(errno.einval)
		return none
	}
	this.l.acquire()
	defer { this.l.release() }
	return this.seals
}

fn (mut this TmpFSResource) add_seals(seals u32) ? {
	if !this.memfd || seals & ~u32(0x3f) != 0 {
		errno.set(errno.einval)
		return none
	}
	this.l.acquire()
	defer {
		this.l.release()
	}
	if this.seals & f_seal_seal != 0 {
		errno.set(errno.eperm)
		return none
	}
	if seals & f_seal_write != 0 && this.seals & f_seal_write == 0 && this.writable_mapping_ranges != 0 {
		errno.set(errno.ebusy)
		return none
	}
	this.seals |= seals
	// Linux checks for busy mappings only for an explicitly requested write
	// seal. An execute seal on an executable inode then implies four seals.
	if seals & f_seal_exec != 0 && this.stat.mode & 0o111 != 0 {
		this.seals |= f_seal_shrink | f_seal_grow | f_seal_write | f_seal_future_write
	}
}

// Tmpfs metadata and file contents already live in the resource's in-memory
// backing store, and a shared mapping maps that store itself: there is no
// device to flush, nothing to write back and nothing to prefetch. Spelled out
// all the same, because the amd64 kernel has no other file system implementing
// these optional hooks, and V3 compiles `res is MetadataResource` for an
// interface nothing implements as a non-nil check whose call then panics --
// chmod, fsync, msync and fadvise all brought the amd64 kernel down that way.
fn (mut this TmpFSResource) persist_metadata() ? { this.sync_acl_mode()? }

fn (mut this TmpFSResource) sync(_handle voidptr) ? {}

fn (mut this TmpFSResource) sync_mapping(_handle voidptr, _offset u64, _length u64) ? {}

fn (mut this TmpFSResource) advise(_handle voidptr, _offset u64, _length u64, _advice int) ? {}

// materialize_locked gives a borrowed (or as-yet empty) file a writable buffer
// of its own with room for `min_capacity` bytes, which with the file's own
// size is no more than tmpfs_contiguous_limit: the caller keeps anything
// larger in pages. The caller holds this.l.
fn (mut this TmpFSResource) materialize_locked(min_capacity u64) bool {
	if this.storage_owned && min_capacity <= this.capacity {
		return true
	}

	// Room for what the file holds as well as for what is asked. A borrowed
	// file's capacity is that of the image it points into, not a buffer's.
	held := u64(this.stat.size)
	wanted := if min_capacity > held { min_capacity } else { held }
	mut new_capacity := tmpfs_smallest_buffer
	for new_capacity < wanted && new_capacity < tmpfs_contiguous_limit {
		new_capacity *= 2
	}
	if new_capacity < wanted {
		return false
	}

	// At most one new page for the slab. A file is refused what programs
	// need to run in (memory/reserve.v), and so never asks malloc() for what
	// is not there, which stops the kernel.
	if !memory.file_room(1) {
		return false
	}
	new_storage := memory.malloc(new_capacity)
	if new_storage == unsafe { nil } {
		return false
	}
	old_size := u64(this.stat.size)
	copy_size := if old_size < new_capacity { old_size } else { new_capacity }
	if copy_size != 0 && this.storage != unsafe { nil } {
		unsafe { C.memcpy(new_storage, this.storage, copy_size) }
	}
	if this.storage_owned {
		memory.free(this.storage)
	}

	this.storage = new_storage
	this.capacity = new_capacity
	this.storage_owned = true
	return true
}

// tmpfs_borrow_storage installs immutable backing supplied by an initramfs
// module.  Limine keeps executable-and-module memory reserved, and Vinix maps
// it in the HHDM, so the bytes remain valid after boot.  Writes, truncation and
// shared mappings transparently copy the file into owned tmpfs memory.
pub fn tmpfs_borrow_storage(mut res resource.Resource, storage voidptr, size u64) bool {
	if mut res is TmpFSResource {
		res.l.acquire()
		defer {
			res.l.release()
		}
		if res.storage_owned {
			memory.free(res.storage)
		}
		res.storage = unsafe { &u8(storage) }
		res.capacity = size
		res.storage_owned = false
		res.stat.size = size
		res.stat.blocks = lib.div_roundup(size, u64(res.stat.blksize))
		return true
	}
	return false
}

// Reserve stable page slots for the in-file part of a shared mapping. Physical
// pages are allocated on first touch; a page past EOF must remain absent.
fn (mut this TmpFSResource) reserve_shared_mapping(offset u64, length u64) bool {
	if offset > u64(-1) - length {
		return false
	}
	this.l.acquire()
	defer {
		this.l.release()
	}
	if !this.ensure_paged_locked(this.outlives_mappers()) {
		return false
	}
	mut end := offset + length
	if end > u64(this.stat.size) {
		end = u64(this.stat.size)
	}
	return this.grow_pages_locked(lib.div_roundup(end, page_size))
}

fn (mut this TmpFSResource) lazy_shared_mapping() bool {
	return true
}

fn (mut this TmpFSResource) private_mapping_cow() bool {
	return true
}

fn (this &TmpFSResource) mapping_truncate_id() u64 {
	return this.mapping_id
}

fn (mut this TmpFSResource) numa_policy_at(offset u64) proc.NumaPolicy {
	this.policy_lock.acquire()
	defer { this.policy_lock.release() }
	return this.shared_policies.lookup(offset)
}

fn (mut this TmpFSResource) shared_policy_at(offset u64) (i32, u64) {
	policy := this.numa_policy_at(offset)
	return policy.mode, policy.mask
}

fn (mut this TmpFSResource) replace_shared_policy(begin u64, end u64, mode i32, mask u64) ? {
	this.policy_lock.acquire()
	defer { this.policy_lock.release() }
	this.shared_policies.replace(proc.kernel_owner(), begin, end, proc.NumaPolicy{mode: mode, mask: mask})?
}

// A page of the file's. One taken for a write is file data, which leaves
// programs their memory: the write fails with ENOSPC before it takes that.
// One taken for a shared mapping of a file nothing names is the mapping
// process' own memory, as an anonymous page would be, and running out is
// that process' to answer for.
fn tmpfs_page(file_data bool, preferred_node int) voidptr {
	if preferred_node < 0 {
		return if file_data { memory.pmm_alloc_file(1) } else { memory.pmm_alloc_user(1) }
	}
	if file_data {
		if !memory.file_room(1) { return unsafe { nil } }
	} else if !memory.user_room(1) {
		return unsafe { nil }
	}
	page := memory.pmm_alloc_on_node(1, preferred_node, false)
	if !file_data && page == unsafe { nil } {
		memory.note_exhaustion()
	}
	return page
}

// Whether a page a shared mapping takes is file data all the same: the file
// has a name, so the page outlives every process that maps it, and killing
// one for it would give nothing back. Writing a file through a mapping --
// a linker does -- then stops where write(2) does, with a fault in place of
// ENOSPC. A memfd, a shared memory segment or a file that has been unlinked
// is memory its mappers share, and theirs to answer for: an X client's
// MIT-SHM image is as much its own as what it mallocs.
fn (this &TmpFSResource) outlives_mappers() bool {
	return !this.nameless && this.stat.nlink > 0
}

// Give the file discrete, immovable physical pages. The contiguous buffer,
// borrowed or owned, is copied across page by page and then let go.
// `file_data` is for tmpfs_page().
fn (mut this TmpFSResource) ensure_paged_locked(file_data bool) bool {
	if this.paged {
		return true
	}
	page_count := lib.div_roundup(u64(this.stat.size), page_size)
	if !this.reserve_page_metadata(page_count * 16) { return false }
	// Kept as this.pages, which unref() frees.
	mut pages := []u64{cap: int(page_count)} @[freed]
	size := u64(this.stat.size)
	for i := u64(0); i < page_count; i++ {
		phys := tmpfs_page(file_data, -1)
		if phys == unsafe { nil } {
			for allocated in pages {
				memory.pmm_free(voidptr(allocated), 1)
			}
			unsafe { pages.free() }
			kbudget.shrink(mut this.kernel_charge, page_count * 16)
			return false
		}
		offset := i * page_size
		if this.storage != unsafe { nil } && offset < size {
			copy_size := if page_size < size - offset { page_size } else { size - offset }
			unsafe { C.memcpy(voidptr(u64(phys) + higher_half), &this.storage[offset], copy_size) }
		}
		pages << u64(phys)
	}
	if this.storage_owned && this.storage != unsafe { nil } {
		memory.free(this.storage)
	}
	this.storage = unsafe { nil }
	this.capacity = 0
	this.storage_owned = false
	this.pages = pages
	this.paged = true
	this.allocated_pages = page_count
	this.stat.blocks = page_count * page_size / u64(this.stat.blksize)
	return true
}

// Reserve slots without allocating pages for the file's untouched holes.
fn (mut this TmpFSResource) grow_pages_locked(page_count u64) bool {
	// Room is made here, doubling, rather than by pushing: an array grown by
	// << leaves its old buffer behind in this kernel, one for every step of a
	// file written a page at a time.
	if page_count > u64(this.pages.cap) {
		mut wanted := if this.pages.cap < 16 { 16 } else { this.pages.cap * 2 }
		if u64(wanted) < page_count {
			wanted = int(page_count)
		}
		if !this.reserve_page_metadata(u64(wanted) * 16) { return false }
		// Kept as this.pages, which unref() frees.
		mut larger := []u64{cap: wanted} @[freed]
		larger << this.pages
		old_bytes := u64(this.pages.cap) * 16
		unsafe { this.pages.free() }
		kbudget.shrink(mut this.kernel_charge, old_bytes)
		this.pages = larger
	}
	for u64(this.pages.len) < page_count {
		this.pages << u64(0)
	}
	return true
}

fn (mut this TmpFSResource) materialize_page_locked(index int, file_data bool) bool {
	if this.pages[index] != 0 {
		return true
	}
	policy := this.numa_policy_at(u64(index) * page_size)
	policy_index := this.stat.ino + u64(index)
	phys := if policy.mode == numa.mpol_default {
		tmpfs_page(file_data, numa.weighted_task_node(policy_index))
	} else {
		numa.alloc_shared_policy_page(policy, policy_index, file_data)
	}
	if phys == unsafe { nil } {
		return false
	}
	this.pages[index] = u64(phys)
	this.allocated_pages++
	this.stat.blocks = this.allocated_pages * page_size / u64(this.stat.blksize)
	return true
}

// Zero [from, to) in the pages that exist. The retained partial page can
// contain bytes beyond EOF, including writes through a shared view.
fn (mut this TmpFSResource) zero_pages_locked(from u64, to u64) {
	limit := u64(this.pages.len) * page_size
	end := if to < limit { to } else { limit }
	mut at := from
	for at < end {
		in_page := at % page_size
		mut chunk := page_size - in_page
		if chunk > end - at {
			chunk = end - at
		}
		phys := this.pages[int(at / page_size)]
		if phys != 0 {
			unsafe { C.memset(voidptr(phys + higher_half + in_page), 0, chunk) }
		}
		at += chunk
	}
}

fn (mut this TmpFSResource) mmap(_handle voidptr, page u64, flags int) voidptr {
	this.l.acquire()
	defer {
		this.l.release()
	}
	if page > u64(-1) / page_size {
		return unsafe { nil }
	}
	offset := page * page_size
	file_size := u64(this.stat.size)
	if offset >= file_size { return resource.mapping_eof }
	is_shared := flags & mmap.map_shared != 0

	// Private mappings of borrowed initramfs data copy only the pages
	// they touch.
	if is_shared || this.paged || this.storage_owned {
		file_data := this.outlives_mappers()
		if !this.ensure_paged_locked(file_data) {
			return unsafe { nil }
		}
		if !this.grow_pages_locked(page + 1)
			|| !this.materialize_page_locked(int(page), file_data) {
			return unsafe { nil }
		}
		physical := voidptr(this.pages[int(page)])
		// The inode owns the cache page. Each private shadow has a separate
		// PMM reference, which makes the existing COW path copy on write.
		if !is_shared && !memory.pmm_retain(physical, 1) { return unsafe { nil } }
		return physical
	}

	copy_page := numa.alloc_range_page(this.numa_policy_at(offset), this.stat.ino + page, true)
	if copy_page == unsafe { nil } {
		return unsafe { nil }
	}
	copy_size := if page_size < file_size - offset { page_size } else { file_size - offset }
	if this.storage != unsafe { nil } {
		unsafe {
			C.memcpy(voidptr(u64(copy_page) + higher_half), &this.storage[offset], copy_size)
		}
	}

	return copy_page
}

fn (mut this TmpFSResource) release_mapping(_handle voidptr, _page u64,
	physical voidptr, flags int) {
	if flags & mmap.map_shared == 0 {
		memory.pmm_free(physical, 1)
	}
}

fn (mut this TmpFSResource) read(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer {
		this.l.release()
	}

	file_size := u64(this.stat.size)
	if loc >= file_size {
		return 0
	}
	actual_count := if count > file_size - loc { file_size - loc } else { count }

	if this.paged {
		this.paged_copy(buf, loc, actual_count, false)
	} else {
		unsafe { C.memcpy(buf, &this.storage[loc], actual_count) }
	}

	return i64(actual_count)
}

// Copy between a user/kernel buffer and the file's pages. `to_file` writes the
// buffer into the pages; otherwise it reads the pages into the buffer.
fn (mut this TmpFSResource) paged_copy(buf voidptr, loc u64, count u64, to_file bool) {
	mut done := u64(0)
	for done < count {
		absolute := loc + done
		index := int(absolute / page_size)
		in_page := absolute % page_size
		mut chunk := page_size - in_page
		if chunk > count - done {
			chunk = count - done
		}
		if index < this.pages.len && this.pages[index] != 0 {
			page_addr := this.pages[index] + higher_half + in_page
			src_or_dst := u64(buf) + done
			if to_file {
				unsafe { C.memcpy(voidptr(page_addr), voidptr(src_or_dst), chunk) }
			} else {
				unsafe { C.memcpy(voidptr(src_or_dst), voidptr(page_addr), chunk) }
			}
		} else if !to_file {
			unsafe { C.memset(voidptr(u64(buf) + done), 0, chunk) }
		}
		done += chunk
	}
}

fn (mut this TmpFSResource) write(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	this.l.acquire()
	defer { this.l.release() }
	return this.write_locked(_handle, buf, loc, count)
}

fn (mut this TmpFSResource) append_data(handle voidptr, buf voidptr, count u64, limit u64, end &u64) ?i64 {
	this.l.acquire()
	defer { this.l.release() }
	location := u64(this.stat.size)
	if count != 0 && location >= limit {
		errno.set(errno.efbig)
		return none
	}
	allowed := if count != 0 && count > limit - location { limit - location } else { count }
	written := this.write_locked(handle, buf, location, allowed)?
	unsafe { *end = location + u64(written) }
	return written
}

fn (mut this TmpFSResource) clear_write_setid_locked() {
	mode := mode_after_write(this.stat.mode, this.stat.gid)
	if mode != this.stat.mode {
		this.stat.mode = mode
		this.stat.ctim = realtime_clock
	}
}

// Caller holds the resource lock through policy checks and data publication.
fn (mut this TmpFSResource) write_locked(_handle voidptr, buf voidptr, loc u64, count u64) ?i64 {
	append := _handle != unsafe { nil }
		&& unsafe { &file.Handle(_handle) }.flags & resource.o_append != 0
	if this.attr_bits & resource.attribute_immutable != 0
		|| (this.attr_bits & resource.attribute_append != 0 && !append) {
		errno.set(errno.eperm)
		return none
	}
	write_at := if append { u64(this.stat.size) } else { loc }

	if count > u64(-1) - write_at {
		return none
	}
	if count == 0 {
		return 0
	}
	write_end := write_at + count
	if this.seals & (f_seal_write | f_seal_future_write) != 0
		|| (this.seals & f_seal_grow != 0 && write_end > u64(this.stat.size)) {
		errno.set(errno.eperm)
		return none
	}
	// By what the file holds as well as by where the write ends: a small write
	// into a large file borrowed from the image copies it into pages too.
	if !this.paged && (write_end > tmpfs_contiguous_limit
		|| u64(this.stat.size) > tmpfs_contiguous_limit) && !this.ensure_paged_locked(true) {
		errno.set(errno.enospc)
		return none
	}
	this.clear_write_setid_locked()
	if this.paged {
		// A hole from a seek past EOF reads back as zero: freshly allocated
		// pages already are, and any existing tail bytes are cleared.
		if write_at > u64(this.stat.size) {
			this.zero_pages_locked(u64(this.stat.size), write_at)
		}
		if !this.grow_pages_locked(lib.div_roundup(write_end, page_size)) {
			errno.set(errno.enospc)
			return none
		}
		for index := int(write_at / page_size); index <= int((write_end - 1) / page_size); index++ {
			if !this.materialize_page_locked(index, true) {
				errno.set(errno.enospc)
				return none
			}
		}
		this.paged_copy(buf, write_at, count, true)
	} else {
		if !this.storage_owned || write_end > this.capacity {
			if !this.materialize_locked(write_end) {
				errno.set(errno.enospc)
				return none
			}
		}
		old_size := u64(this.stat.size)
		if write_at > old_size {
			// A write after a seek beyond EOF creates a zero-filled sparse hole.
			unsafe { C.memset(&this.storage[old_size], 0, write_at - old_size) }
		}
		unsafe { C.memcpy(&this.storage[write_at], buf, count) }
	}

	if write_end > this.stat.size {
		this.stat.size = write_end
		if !this.paged {
			this.stat.blocks = lib.div_roundup(this.stat.size, this.stat.blksize)
		}
	}

	return i64(count)
}

fn (mut this TmpFSResource) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this TmpFSResource) filesystem_stat() resource.FileSystemStat {
	return resource.FileSystemStat{
		@type: 0x01021994
		bsize: page_size
		blocks: memory.total_bytes() / page_size
		// What a file can still take: free memory less what is kept for
		// programs to run in.
		bfree: memory.file_room_bytes() / page_size
		bavail: memory.file_room_bytes() / page_size
		files: u64(-1)
		ffree: u64(-1)
		namelen: 255
		frsize: page_size
	}
}

fn (mut this TmpFSResource) unref(_handle voidptr) ? {
	// The count the decrement left, not one read after it: two last
	// references dropped at once could both read zero and free the file
	// twice.
	if katomic.dec(mut &this.refcount) {
		return
	}

	if this.paged {
		for phys in this.pages {
			if phys != 0 {
				memory.pmm_free(voidptr(phys), 1)
			}
		}
		unsafe { this.pages.free() }
	} else if stat.isreg(this.stat.mode) && this.storage_owned {
		memory.free(this.storage)
	}
	free_xattrs(this.xattrs)
	this.shared_policies.release()
	kbudget.release(this.kernel_charge)

	unsafe {
		free(voidptr(this.box))
		free(this)
	}
}

// boxed is the resource as nodes and descriptors hold it; see `box`.
fn (mut this TmpFSResource) boxed() &resource.Resource {
	if this.box == unsafe { nil } {
		this.box = &resource.Resource(this) @[freed]
	}
	return this.box
}

fn (mut this TmpFSResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this TmpFSResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

// Returns with the data lock held. If a mapper was busy, let it finish and
// recheck size, seals and attributes before trying the untouched shrink again.
fn (mut this TmpFSResource) lock_resize(new_size u64) ?u64 {
	cutoff := lib.align_up(new_size, page_size)
	for {
		this.l.acquire()
		old_size := u64(this.stat.size)
		if this.attr_bits & resource.attributes_kept != 0
			|| (new_size < old_size && this.seals & f_seal_shrink != 0)
			|| (new_size > old_size && this.seals & f_seal_grow != 0) {
			this.l.release()
			errno.set(errno.eperm)
			return none
		}
		if new_size >= old_size || cutoff >= old_size
			|| mmap.try_truncate_file_mappings(voidptr(this.box), cutoff) {
			return old_size
		}
		can_yield := this.l.ints
		this.l.release()
		if can_yield { sched.yield(true) }
	}
	return none
}

fn (mut this TmpFSResource) shrink_pages_locked(new_size u64) {
	cutoff := lib.align_up(new_size, page_size)
	this.zero_pages_locked(new_size, cutoff)
	first := cutoff / page_size
	if first < u64(this.pages.len) {
		for i in int(first) .. this.pages.len {
			physical := this.pages[i]
			if physical == 0 { continue }
			memory.pmm_free(voidptr(physical), 1)
			this.allocated_pages--
		}
		this.pages.trim(int(first))
	}
	this.stat.blocks = this.allocated_pages * page_size / u64(this.stat.blksize)
}

fn (mut this TmpFSResource) grow(_handle voidptr, new_size u64) ? {
	old_size := this.lock_resize(new_size)?
	defer { this.l.release() }
	if new_size <= old_size {
		if this.paged && new_size < old_size { this.shrink_pages_locked(new_size) }
		this.clear_write_setid_locked()
		this.stat.size = new_size
		if !this.paged {
			this.stat.blocks = lib.div_roundup(new_size, u64(this.stat.blksize))
		}
		return
	}

	if !this.paged && new_size > tmpfs_contiguous_limit && !this.ensure_paged_locked(true) {
		errno.set(errno.enospc)
		return none
	}
	if this.paged {
		// Shared writes after EOF may have touched the old partial page.
		this.zero_pages_locked(old_size, new_size)
		if !this.grow_pages_locked(lib.div_roundup(new_size, page_size)) {
			return none
		}
	} else {
		if !this.materialize_locked(new_size) {
			errno.set(errno.enospc)
			return none
		}
		// Anything past the old end of the file has to read back as zero, whether
		// it got there by seeking past the end and writing or by ftruncate. realloc
		// makes no such promise about the memory it hands back.
		unsafe {
			C.memset(voidptr(u64(this.storage) + old_size), 0, new_size - old_size)
		}
	}

	this.clear_write_setid_locked()
	this.stat.size = new_size
	if !this.paged {
		this.stat.blocks = lib.div_roundup(new_size, u64(this.stat.blksize))
	}
}

struct TmpFSMountOptions {
	recorded bool
	mode u32
	uid u32
	gid u32
}

struct TmpFS {
pub mut:
	dev_id        u64
	inode_counter u64
	// The root's initial configuration, independent of chmod and chown.
	mount_options TmpFSMountOptions
	// See as_filesystem().
	box &FileSystem = unsafe { nil }
}

// The caller is preparing a filesystem root for its first publication.
fn capture_tmpfs_mount_options(root &VFSNode) {
	if root.resource == unsafe { nil } { return }
	mut backend := root.filesystem
	if mut backend is TmpFS {
		if backend.mount_options.recorded { return }
		backend.mount_options = TmpFSMountOptions{
			recorded: true
			mode: root.resource.stat.mode & 0o7777
			uid: root.resource.stat.uid
			gid: root.resource.stat.gid
		}
	}
}

// as_filesystem is the filesystem as the VFS holds it, boxed once. Passing
// `this` to create_node() boxed it again for every node made.
fn (mut this TmpFS) as_filesystem() &FileSystem {
	if this.box == unsafe { nil } {
		this.box = &FileSystem(this)
	}
	return this.box
}

fn (this TmpFS) instantiate() &FileSystem {
	mut new := &TmpFS{}
	return new.as_filesystem()
}

fn (this TmpFS) populate(_node &VFSNode) {}

fn (mut this TmpFS) mount(parent &VFSNode, name string, _source &VFSNode) ?&VFSNode {
	this.dev_id = resource.create_dev_id()
	return this.create(parent, name, 0o755 | stat.ifdir)
}

fn (mut this TmpFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	charge := proc.reserve_kernel(.file, tmpfs_resource_charge) or { return unsafe { nil } }
	mut new_node := create_node(this.as_filesystem(), parent, name, stat.isdir(mode))

	mut new_resource := &TmpFSResource{
		kernel_charge: charge
		storage: unsafe { nil }
		refcount: 1
	}

	if stat.isreg(mode) {
		new_resource.can_mmap = true
		new_resource.mapping_id = katomic.inc(mut &tmpfs_mapping_sequence) + 1
	}

	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = this.dev_id
	new_resource.stat.ino = this.inode_counter++
	new_resource.stat.mode = mode
	new_resource.stat.nlink = 1

	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	new_node.resource = new_resource.boxed()

	return new_node
}

fn (mut this TmpFS) link(parent &VFSNode, path string, mut old_node VFSNode) ?&VFSNode {
	mut new_node := create_node(this.as_filesystem(), parent, path, false)

	katomic.inc(mut &old_node.resource.refcount)
	katomic.inc(mut &old_node.resource.stat.nlink)

	new_node.resource = old_node.resource
	new_node.children = old_node.children

	return new_node
}

fn (mut this TmpFS) rename(_old_parent &VFSNode, _old_name string,
	_new_parent &VFSNode, _new_name string, _flags int) ? {}

fn (mut this TmpFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	charge := proc.reserve_kernel(.file, tmpfs_resource_charge) or { return unsafe { nil } }
	mut new_node := create_node(this.as_filesystem(), parent, target, false)

	mut new_resource := &TmpFSResource{
		kernel_charge: charge
		storage: unsafe { nil }
		refcount: 1
	}

	// A symlink's size is the length of the path it holds, not of its own name.
	new_resource.stat.size = i64(dest.len)
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = this.dev_id
	new_resource.stat.ino = this.inode_counter++
	new_resource.stat.mode = stat.iflnk | 0o777
	new_resource.stat.nlink = 1

	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	new_node.resource = new_resource.boxed()

	// A copy of its own, as every filesystem keeps: symlinkat(2) frees the
	// text it was given.
	new_node.symlink_target = dest.clone()

	return new_node
}

// A tmpfs file with no name and no place in the directory tree, for
// memfd_create(2). It behaves like any other tmpfs file — it can be written,
// truncated and mapped — and goes away with its last descriptor.
pub fn create_anonymous(mode u32) ?&resource.Resource {
	charge := proc.reserve_kernel(.file, tmpfs_resource_charge)?
	mut new_resource := &TmpFSResource{
		kernel_charge: charge
		storage: unsafe { nil }
		refcount: 1
		nameless: true
	}

	new_resource.can_mmap = true
	new_resource.mapping_id = katomic.inc(mut &tmpfs_mapping_sequence) + 1

	new_resource.stat.size = 0
	new_resource.stat.blocks = 0
	new_resource.stat.blksize = 512
	new_resource.stat.dev = resource.create_dev_id()
	new_resource.stat.ino = 1
	new_resource.stat.mode = stat.ifreg | mode
	new_resource.stat.nlink = 1

	new_resource.stat.atim = realtime_clock
	new_resource.stat.ctim = realtime_clock
	new_resource.stat.mtim = realtime_clock

	return new_resource.boxed()
}

fn (mut this TmpFSResource) reserve_page_metadata(bytes u64) bool {
	if this.kernel_charge.owner.slot == 0 && proc.kernel_owner().slot != 0 {
		this.kernel_charge = proc.reserve_kernel(.file, tmpfs_resource_charge) or { return false }
	}
	return proc.grow_kernel(mut this.kernel_charge, bytes)
}
