module fs

import stat
import errno
import klock
import memory
import memory.mmap
import resource
import lib
import event.eventstruct
import katomic

@[heap]
struct TmpFSResource {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	storage  &u8
	capacity u64
	// Initramfs files initially point straight into the Limine module.  The
	// module remains reserved for the life of the kernel, so keeping that
	// pointer avoids allocating and copying the whole root filesystem during
	// boot.  The first operation which can modify the backing store turns it
	// into an ordinary tmpfs allocation.
	storage_owned bool
	// memfd_create(2) files take seals; nothing else does.
	memfd bool
	seals u32
	// A file that is mapped MAP_SHARED can no longer live in one movable
	// buffer: growing it would relocate the pages a mapping already points at.
	// It switches to a list of individually allocated physical pages, which
	// stay put for the life of the file, and every access goes through those
	// pages from then on.
	paged bool
	pages []u64
	// Extended attributes, nil until one is set; see xattr.v.
	xattrs &XAttrSet = unsafe { nil }
}

// A file larger than this lives in individual pages rather than in one buffer.
// Growing a buffer by doubling needs a contiguous run of physical memory as
// large as the file, which a fragmented machine eventually cannot supply, and
// the allocator panics rather than fail: runc copies its ~10 MiB binary into a
// memfd for every container it starts, and that brought the kernel down after
// a handful of containers.
const tmpfs_contiguous_limit = u64(1) << 20

const f_seal_seal = u32(0x1)
const f_seal_shrink = u32(0x2)
const f_seal_grow = u32(0x4)
const f_seal_write = u32(0x8)
const f_seal_future_write = u32(0x10)
const f_seal_exec = u32(0x20)

fn (mut this TmpFSResource) get_seals() ?u32 {
	if !this.memfd {
		errno.set(errno.einval)
		return none
	}
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
	this.seals |= seals
}

// materialize_locked gives a borrowed (or as-yet empty) file writable tmpfs
// storage.  The caller holds this.l.  Keep the minimum allocation at one page:
// tmpfs.mmap returns physical pages and therefore needs a page-aligned big
// allocation rather than a small slab object.
fn (mut this TmpFSResource) materialize_locked(min_capacity u64) bool {
	if this.storage_owned && min_capacity <= this.capacity {
		return true
	}

	mut new_capacity := if this.storage_owned { this.capacity } else { u64(this.stat.size) }
	if new_capacity < page_size {
		new_capacity = page_size
	}
	for min_capacity > new_capacity {
		if new_capacity > u64(-1) / 2 {
			new_capacity = min_capacity
			break
		}
		new_capacity *= 2
	}
	// malloc's large allocations occupy complete physical pages. Record that
	// usable tail as capacity too, so mapping the last partial file page does
	// not trigger a needless second allocation (and exponential growth).
	if new_capacity <= u64(-1) - (page_size - 1) {
		new_capacity = lib.align_up(new_capacity, page_size)
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

// Back the in-file part of a shared mapping with immovable pages before any of
// them is returned. Only up to the file's end: a page past it must stay absent
// so touching it faults.
fn (mut this TmpFSResource) reserve_shared_mapping(offset u64, length u64) bool {
	if offset > u64(-1) - length {
		return false
	}
	this.l.acquire()
	defer {
		this.l.release()
	}
	if !this.ensure_paged_locked() {
		return false
	}
	mut end := offset + length
	if end > u64(this.stat.size) {
		end = u64(this.stat.size)
	}
	return this.grow_pages_locked(lib.div_roundup(end, page_size))
}

// Give the file discrete, immovable physical pages. Called before it is first
// shared-mapped. The contiguous buffer, borrowed or owned, is copied across
// page by page and then let go.
fn (mut this TmpFSResource) ensure_paged_locked() bool {
	if this.paged {
		return true
	}
	page_count := lib.div_roundup(u64(this.stat.size), page_size)
	mut pages := []u64{cap: int(page_count)}
	size := u64(this.stat.size)
	for i := u64(0); i < page_count; i++ {
		phys := memory.pmm_alloc(1)
		if phys == unsafe { nil } {
			for allocated in pages {
				memory.pmm_free(voidptr(allocated), 1)
			}
			unsafe { pages.free() }
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
	return true
}

// Add zero-filled pages so the file has at least `page_count` of them.
fn (mut this TmpFSResource) grow_pages_locked(page_count u64) bool {
	// Room is made here, doubling, rather than by pushing: an array grown by
	// << leaves its old buffer behind in this kernel, one for every step of a
	// file written a page at a time.
	if page_count > u64(this.pages.cap) {
		mut wanted := if this.pages.cap < 16 { 16 } else { this.pages.cap * 2 }
		if u64(wanted) < page_count {
			wanted = int(page_count)
		}
		mut larger := []u64{cap: wanted}
		larger << this.pages
		unsafe { this.pages.free() }
		this.pages = larger
	}
	for u64(this.pages.len) < page_count {
		phys := memory.pmm_alloc(1)
		if phys == unsafe { nil } {
			return false
		}
		this.pages << u64(phys)
	}
	return true
}

// A truncated file keeps its pages, and they still hold what was there. Zero
// [from, to) in whichever of them exist, so that growing the file again, by
// ftruncate or by writing past its end, reads back zeros.
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
		unsafe { C.memset(voidptr(this.pages[int(at / page_size)] + higher_half + in_page), 0, chunk) }
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

	if flags & mmap.map_shared != 0 {
		// Only pages that lie within the file are backed. A shared mapping may
		// extend past the end -- callers routinely map a rounded-up region --
		// and a page past the file must fault (SIGBUS) rather than make the
		// file grow to cover it.
		if offset >= u64(this.stat.size) {
			return unsafe { nil }
		}
		if !this.ensure_paged_locked() {
			return unsafe { nil }
		}
		if page >= u64(this.pages.len) {
			return unsafe { nil }
		}
		return voidptr(this.pages[int(page)])
	}

	copy_page := memory.pmm_alloc(1)
	file_size := u64(this.stat.size)
	if offset < file_size {
		copy_size := if page_size < file_size - offset { page_size } else { file_size - offset }
		if this.paged {
			if page < u64(this.pages.len) {
				unsafe {
					C.memcpy(voidptr(u64(copy_page) + higher_half),
						voidptr(this.pages[int(page)] + higher_half), copy_size)
				}
			}
		} else if this.storage != unsafe { nil } {
			unsafe {
				C.memcpy(voidptr(u64(copy_page) + higher_half), &this.storage[offset], copy_size)
			}
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
		if index < this.pages.len {
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
	defer {
		this.l.release()
	}

	if count > u64(-1) - loc {
		return none
	}
	if count == 0 {
		return 0
	}
	write_end := loc + count
	if this.seals & (f_seal_write | f_seal_future_write) != 0
		|| (this.seals & f_seal_grow != 0 && write_end > u64(this.stat.size)) {
		errno.set(errno.eperm)
		return none
	}
	if !this.paged && write_end > tmpfs_contiguous_limit && !this.ensure_paged_locked() {
		errno.set(errno.enospc)
		return none
	}
	if this.paged {
		// A hole from a seek past EOF reads back as zero: freshly allocated
		// pages already are, and pages kept from before a truncation are
		// cleared.
		if loc > u64(this.stat.size) {
			this.zero_pages_locked(u64(this.stat.size), loc)
		}
		if !this.grow_pages_locked(lib.div_roundup(write_end, page_size)) {
			return none
		}
		this.paged_copy(buf, loc, count, true)
	} else {
		if !this.storage_owned || write_end > this.capacity {
			if !this.materialize_locked(write_end) {
				return none
			}
		}
		old_size := u64(this.stat.size)
		if loc > old_size {
			// A write after a seek beyond EOF creates a zero-filled sparse hole.
			unsafe { C.memset(&this.storage[old_size], 0, loc - old_size) }
		}
		unsafe { C.memcpy(&this.storage[loc], buf, count) }
	}

	if write_end > this.stat.size {
		this.stat.size = write_end
		this.stat.blocks = lib.div_roundup(this.stat.size, this.stat.blksize)
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
		bfree: memory.free_bytes() / page_size
		bavail: memory.free_bytes() / page_size
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
			memory.pmm_free(voidptr(phys), 1)
		}
		unsafe { this.pages.free() }
	} else if stat.isreg(this.stat.mode) && this.storage_owned {
		memory.free(this.storage)
	}
	free_xattrs(this.xattrs)

	unsafe { free(this) }
}

fn (mut this TmpFSResource) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this TmpFSResource) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this TmpFSResource) grow(_handle voidptr, new_size u64) ? {
	this.l.acquire()
	defer {
		this.l.release()
	}

	old_size := u64(this.stat.size)
	if (new_size < old_size && this.seals & f_seal_shrink != 0)
		|| (new_size > old_size && this.seals & f_seal_grow != 0) {
		errno.set(errno.eperm)
		return none
	}
	if new_size <= old_size {
		// A shared-mapped file keeps its pages when truncated: another mapping
		// may still reach them, and a regrow must show the same page, not a
		// fresh one. An ordinary file's borrowed storage can stay borrowed and
		// re-materialise its still-visible prefix on the next grow.
		this.stat.size = new_size
		this.stat.blocks = lib.div_roundup(new_size, u64(this.stat.blksize))
		return
	}

	if !this.paged && new_size > tmpfs_contiguous_limit && !this.ensure_paged_locked() {
		errno.set(errno.enospc)
		return none
	}
	if this.paged {
		// Pages kept past the old end still hold stale bytes; new ones are zero.
		this.zero_pages_locked(old_size, new_size)
		if !this.grow_pages_locked(lib.div_roundup(new_size, page_size)) {
			return none
		}
	} else {
		if !this.materialize_locked(new_size) {
			return none
		}
		// Anything past the old end of the file has to read back as zero, whether
		// it got there by seeking past the end and writing or by ftruncate. realloc
		// makes no such promise about the memory it hands back.
		unsafe {
			C.memset(voidptr(u64(this.storage) + old_size), 0, new_size - old_size)
		}
	}

	this.stat.size = new_size
	this.stat.blocks = lib.div_roundup(new_size, u64(this.stat.blksize))
}

struct TmpFS {
pub mut:
	dev_id        u64
	inode_counter u64
}

fn (this TmpFS) instantiate() &FileSystem {
	new := &TmpFS{}
	return new
}

fn (this TmpFS) populate(_node &VFSNode) {}

fn (mut this TmpFS) mount(parent &VFSNode, name string, _source &VFSNode) ?&VFSNode {
	this.dev_id = resource.create_dev_id()
	return this.create(parent, name, 0o755 | stat.ifdir)
}

fn (mut this TmpFS) create(parent &VFSNode, name string, mode u32) &VFSNode {
	mut new_node := create_node(this, parent, name, stat.isdir(mode))

	mut new_resource := &TmpFSResource{
		storage: unsafe { nil }
		refcount: 1
	}

	if stat.isreg(mode) {
		new_resource.can_mmap = true
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

	new_node.resource = new_resource

	return new_node
}

fn (mut this TmpFS) link(parent &VFSNode, path string, mut old_node VFSNode) ?&VFSNode {
	mut new_node := create_node(this, parent, path, false)

	katomic.inc(mut &old_node.resource.refcount)
	katomic.inc(mut &old_node.resource.stat.nlink)

	new_node.resource = old_node.resource
	new_node.children = old_node.children

	return new_node
}

fn (mut this TmpFS) rename(_old_parent &VFSNode, _old_name string,
	_new_parent &VFSNode, _new_name string, _flags int) ? {}

fn (mut this TmpFS) symlink(parent &VFSNode, dest string, target string) &VFSNode {
	mut new_node := create_node(this, parent, target, false)

	mut new_resource := &TmpFSResource{
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

	new_node.resource = new_resource

	new_node.symlink_target = dest

	return new_node
}

// A tmpfs file with no name and no place in the directory tree, for
// memfd_create(2). It behaves like any other tmpfs file — it can be written,
// truncated and mapped — and goes away with its last descriptor.
pub fn create_anonymous(mode u32) &resource.Resource {
	mut new_resource := &TmpFSResource{
		storage: unsafe { nil }
		refcount: 1
	}

	new_resource.can_mmap = true

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

	return new_resource
}
