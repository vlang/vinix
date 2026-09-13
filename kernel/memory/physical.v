@[has_globals; manualfree]
module memory

import lib
import klock
import katomic
import limine

__global (
	pmm_lock            klock.Lock
	pmm_bitmap          = unsafe { nil }
	pmm_bitmap_phys     = u64(0)
	pmm_bitmap_size     = u64(0)
	pmm_refcounts       = unsafe { nil }
	pmm_refcounts_phys  = u64(0)
	pmm_refcounts_size  = u64(0)
	pmm_avl_page_count  = u64(0)
	pmm_last_used_index = u64(0)
	free_pages          = u64(0)
	// Usable pages the memory map declared, counted once at init. free_pages
	// falls as memory is handed out; this does not, so the two together say
	// how much of the machine's RAM is in use.
	pmm_total_pages     = u64(0)
	higher_half         = u64(0)
)

// Subsystems which hold regenerable physical memory can register a bounded
// reclaimer. The PMM invokes these only after an allocation scan failed and
// only while its own lock is dropped. That ordering is important: reclaimers
// eventually call pmm_free(), and may themselves be entered from an allocation
// made while one of their locks is held.
const max_reclaimers = 8

__global (
	reclaimers       [max_reclaimers]fn (u64) u64
	reclaimers_len   = int(0)
	reclaimers_lock  klock.Lock
	// A word, not a bool: katomic.cas only implements the 32- and 64-bit
	// widths, and panicked on a one-byte operand. Every attempt to reclaim
	// memory stopped the machine instead, which is to say the reclaimer had
	// never run.
	reclaim_inflight = u32(0)
)

pub fn register_reclaimer(reclaimer fn (u64) u64) bool {
	reclaimers_lock.acquire()
	defer { reclaimers_lock.release() }
	if reclaimers_len == max_reclaimers {
		return false
	}
	reclaimers[reclaimers_len] = reclaimer
	reclaimers_len++
	return true
}

fn reclaim_pages(wanted u64) u64 {
	// A reclaimer may allocate for bookkeeping. Do not recursively enter all
	// reclaimers in that case, and do not wait on one already running elsewhere.
	if !katomic.cas(mut &reclaim_inflight, u32(0), u32(1)) {
		return 0
	}
	defer { katomic.store(mut &reclaim_inflight, u32(0)) }

	mut reclaimed := u64(0)
	count := reclaimers_len
	for i := 0; i < count && reclaimed < wanted; i++ {
		reclaimed += reclaimers[i](wanted - reclaimed)
	}
	return reclaimed
}

@[_linker_section: '.requests']
@[cinit]
__global (
	volatile hhdm_req = limine.LimineHHDMRequest{
		response: unsafe { nil }
	}
)

pub fn get_hhdm_offset() u64 {
	return higher_half
}

// total_bytes and free_bytes report the machine's usable RAM and how much of
// it is unallocated. Both are page counts scaled to bytes, which is what a
// reader outside this module wants to say to a person.
pub fn total_bytes() u64 {
	return pmm_total_pages * page_size
}

pub fn free_bytes() u64 {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	return free_pages * page_size
}

pub fn print_free() {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	C.printf(c'pmm: Free pages: %llu\n', free_pages)
}

pub fn pmm_init() {
	if hhdm_req.response == unsafe { nil } {
		lib.kpanic(unsafe { nil }, c'HHDM bootloader response missing')
	}
	higher_half = hhdm_req.response.offset

	C.printf(c'pmm: Higher half direct map at: %p\n', higher_half)

	if memmap_req.response == unsafe { nil } {
		lib.kpanic(unsafe { nil }, c'Memory map bootloader response missing')
	}
	memmap := memmap_req.response

	mut no_usable_entries := false
	mut bitmap_alloc_failed := false
	unsafe {
		mut highest_address := u64(0)
		mut entries := memmap.entries

		// Calculate how big the memory map needs to be.
		for i := 0; i < memmap.entry_count; i++ {
			C.printf(c'pmm: Memory map entry %d: 0x%llx->0x%llx  0x%llx\n', i, entries[i].base, entries[i].length, entries[i].@type)

			// Size PMM strictly from usable RAM. Including non-usable high
			// regions (e.g. firmware reclaimable areas at large addresses)
			// can over-inflate the bitmap and fail early on real hardware.
			if entries[i].@type != u32(limine.limine_memmap_usable) {
				continue
			}
			top := entries[i].base + entries[i].length
			if top > highest_address {
				highest_address = top
			}
		}
		if highest_address == 0 {
			no_usable_entries = true
			return
		}

		// Calculate the needed size for the bitmap in bytes and align it to page size.
		// Use ceiling division for the byte count: a page count that is not a
		// multiple of 8 still needs a full trailing byte, and flooring here can
		// under-size the bitmap by a page after alignment (e.g. 32769 pages).
		pmm_avl_page_count = lib.div_roundup(highest_address, page_size)
		bitmap_size := lib.align_up(lib.div_roundup(pmm_avl_page_count, 8), page_size)
		refcounts_size := lib.align_up(pmm_avl_page_count * sizeof(u32), page_size)
		metadata_size := bitmap_size + refcounts_size

		C.printf(c'pmm: Bitmap size: %llu\n', bitmap_size)

		// Find a hole for the bitmap in the memory map. The entry is NOT
		// shrunk to exclude it: the memory map is also what vmm_init maps into
		// the higher half, so carving the bitmap out of it left the bitmap's
		// own pages unmapped once the kernel's page tables went live. QEMU
		// never showed it (its RAM is below 4 GiB, which vmm_init maps
		// wholesale); on Apple Silicon RAM starts at 32 GiB, so the first
		// pmm_alloc after the switch faulted on the bitmap. The bitmap's pages
		// are instead marked used in the bitmap itself, below.
		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].@type != u32(limine.limine_memmap_usable) {
				continue
			}
			if entries[i].length >= metadata_size {
				pmm_bitmap_phys = entries[i].base
				pmm_bitmap_size = bitmap_size
				pmm_bitmap = voidptr(pmm_bitmap_phys + higher_half)
				pmm_refcounts_phys = pmm_bitmap_phys + bitmap_size
				pmm_refcounts_size = refcounts_size
				pmm_refcounts = voidptr(pmm_refcounts_phys + higher_half)

				// Initialise entire bitmap to 1 (non-free)
				C.memset(pmm_bitmap, 0xff, bitmap_size)
				C.memset(pmm_refcounts, 0, refcounts_size)
				break
			}
		}
		if pmm_bitmap == 0 {
			bitmap_alloc_failed = true
			return
		}

		// Populate free bitmap entries according to the memory map.
		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].@type != u32(limine.limine_memmap_usable) {
				continue
			}

			for j := u64(0); j < entries[i].length; j += page_size {
				free_pages++
				lib.bitreset(pmm_bitmap, (entries[i].base + j) / page_size)
			}
		}

		// Every usable page has now been counted. The bitmap's own pages come
		// off the free count below but are still RAM the machine has, so the
		// total is taken here rather than after.
		pmm_total_pages = free_pages

		// The bitmap occupies the head of a usable entry; take those pages
		// back so they are never handed out.
		for j := u64(0); j < pmm_bitmap_size + pmm_refcounts_size; j += page_size {
			page_index := (pmm_bitmap_phys + j) / page_size
			lib.bitset(pmm_bitmap, page_index)
			(&u32(pmm_refcounts))[page_index] = 1
			free_pages--
		}
	}
	if no_usable_entries {
		lib.kpanic(unsafe { nil }, c'PMM: no usable memory entries in memmap')
	}
	if bitmap_alloc_failed {
		lib.kpanic(unsafe { nil }, c'PMM: failed to allocate PMM bitmap from usable memory')
	}
	print_free()

	// Size classes are initialized without allocating backing pages.
	slabs[0].init(16)
	slabs[1].init(32)
	slabs[2].init(48)
	slabs[3].init(64)
	slabs[4].init(96)
	slabs[5].init(128)
	slabs[6].init(192)
	slabs[7].init(256)
	slabs[8].init(384)
	slabs[9].init(512)
	slabs[10].init(768)
	slabs[11].init(1024)
	slabs[12].init(1536)
	slabs[13].init(2048)

	$if xnu_zone ? {
		xnu_heap_init()
	}

	$if heap_selftest ? {
		heap_selftest()
	}
}

fn inner_alloc(count u64, limit u64) voidptr {
	mut p := 0

	for pmm_last_used_index < limit {
		if !lib.bittest(pmm_bitmap, pmm_last_used_index) {
			pmm_last_used_index++
			p++
			if u64(p) == count {
				page := pmm_last_used_index - count
				for i := page; i < pmm_last_used_index; i++ {
					lib.bitset(pmm_bitmap, i)
					unsafe { (&u32(pmm_refcounts))[i] = 1 }
				}
				charge_node_pages(page, count)
				return voidptr(page * page_size)
			}
		} else {
			pmm_last_used_index++
			p = 0
		}
	}
	return 0
}

// inner_alloc confined to one window of the bitmap, [start, limit). This is
// how a node-restricted allocation scans only the pages its node owns; see
// physical_numa.v. Accounting for the pages it takes is the caller's, which
// already knows the node and so does not have to look each page up again.
fn inner_alloc_range(count u64, start u64, limit u64) voidptr {
	mut p := u64(0)

	for i := start; i < limit; i++ {
		if !lib.bittest(pmm_bitmap, i) {
			p++
			if p == count {
				page := i + 1 - count
				for j := page; j <= i; j++ {
					lib.bitset(pmm_bitmap, j)
					unsafe { (&u32(pmm_refcounts))[j] = 1 }
				}
				return voidptr(page * page_size)
			}
		} else {
			p = 0
		}
	}
	return 0
}

fn try_alloc_nozero(count u64) voidptr {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}

	last := pmm_last_used_index
	mut ret := inner_alloc(count, pmm_avl_page_count)

	if ret == 0 {
		pmm_last_used_index = 0

		ret = inner_alloc(count, last)
		if ret == 0 {
			return unsafe { nil }
		}
	}

	free_pages -= count

	return ret
}

pub fn pmm_alloc_nozero(count u64) voidptr {
	mut ret := try_alloc_nozero(count)
	if ret == unsafe { nil } {
		reclaim_pages(count)
		ret = try_alloc_nozero(count)
		if ret == unsafe { nil } {
			lib.kpanic(unsafe { nil }, c'Out of memory after reclaim')
		}
	}
	return ret
}

pub fn pmm_alloc(count u64) voidptr {
	ret := pmm_alloc_nozero(count)

	// We always zero out memory for security reasons
	unsafe {
		mut ptr := &u64(u64(ret) + higher_half)
		for i := u64(0); i < (count * page_size) / 8; i++ {
			ptr[i] = 0
		}
	}
	return ret
}

// Fallible allocator variants for callers that can recover from exhaustion
// (e.g. user-controlled GEM/driver allocations). Unlike pmm_alloc these return
// nil on out-of-memory instead of panicking, so resource pressure cannot be
// turned into a kernel panic by a userspace request.
pub fn pmm_alloc_nozero_fallible(count u64) voidptr {
	mut ret := try_alloc_nozero(count)
	if ret == unsafe { nil } {
		reclaim_pages(count)
		ret = try_alloc_nozero(count)
	}
	return ret
}

pub fn pmm_alloc_fallible(count u64) voidptr {
	ret := pmm_alloc_nozero_fallible(count)
	if ret == unsafe { nil } {
		return unsafe { nil }
	}

	// We always zero out memory for security reasons
	unsafe {
		mut ptr := &u64(u64(ret) + higher_half)
		for i := u64(0); i < (count * page_size) / 8; i++ {
			ptr[i] = 0
		}
	}
	return ret
}

// Allocate `count` contiguous pages whose physical base is aligned to
// `alignment_pages`. The PMM is 4 KiB-granular, so this over-allocates and
// returns the unused prefix and suffix before exposing the aligned range.
fn pmm_alloc_aligned_inner(count u64, alignment_pages u64, fallible bool) voidptr {
	if count == 0 || alignment_pages == 0 || alignment_pages & (alignment_pages - 1) != 0
		|| count > u64(-1) - (alignment_pages - 1)
		|| alignment_pages > u64(-1) / page_size {
		return unsafe { nil }
	}
	if alignment_pages == 1 {
		if fallible {
			return pmm_alloc_fallible(count)
		}
		return pmm_alloc(count)
	}

	total_pages := count + alignment_pages - 1
	mut raw := unsafe { nil }
	if fallible {
		raw = pmm_alloc_nozero_fallible(total_pages)
	} else {
		raw = pmm_alloc_nozero(total_pages)
	}
	if raw == unsafe { nil } {
		return unsafe { nil }
	}
	raw_addr := u64(raw)
	alignment := alignment_pages * page_size
	aligned_addr := lib.align_up(raw_addr, alignment)
	prefix_pages := (aligned_addr - raw_addr) / page_size
	suffix_pages := total_pages - prefix_pages - count

	if prefix_pages != 0 {
		pmm_free(raw, prefix_pages)
	}
	if suffix_pages != 0 {
		pmm_free(voidptr(aligned_addr + count * page_size), suffix_pages)
	}

	unsafe {
		C.memset(voidptr(aligned_addr + higher_half), 0, count * page_size)
	}
	return voidptr(aligned_addr)
}

pub fn pmm_alloc_aligned(count u64, alignment_pages u64) voidptr {
	return pmm_alloc_aligned_inner(count, alignment_pages, false)
}

pub fn pmm_alloc_aligned_fallible(count u64, alignment_pages u64) voidptr {
	return pmm_alloc_aligned_inner(count, alignment_pages, true)
}

pub fn pmm_free(ptr voidptr, count u64) {
	page := u64(ptr) / page_size
	if count == 0 || page >= pmm_avl_page_count || count > pmm_avl_page_count - page {
		return
	}
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	for i := page; i < page + count; i++ {
		mut refs := unsafe { &u32(pmm_refcounts) }
		if unsafe { refs[i] } > 1 {
			unsafe { refs[i]-- }
			continue
		}
		if unsafe { refs[i] } == 0 {
			continue
		}
		unsafe {
			mut words := &u64(i * page_size + higher_half)
			for word := u64(0); word < page_size / 8; word++ {
				words[word] = 0xaaaaaaaaaaaaaaaa
			}
			refs[i] = 0
		}
		lib.bitreset(pmm_bitmap, i)
		discharge_node_page(i)
		free_pages++
	}
}

// Retain physical pages which are installed into another private address
// space by fork.  The bitmap and reference array share pmm_lock, so a final
// unmap cannot return a page while fork is taking its reference.
pub fn pmm_retain(ptr voidptr, count u64) bool {
	page := u64(ptr) / page_size
	if page >= pmm_avl_page_count || count > pmm_avl_page_count - page {
		return false
	}
	pmm_lock.acquire()
	defer { pmm_lock.release() }
	mut refs := unsafe { &u32(pmm_refcounts) }
	for i := page; i < page + count; i++ {
		if !lib.bittest(pmm_bitmap, i) || unsafe { refs[i] } == 0
			|| unsafe { refs[i] } == u32(-1) {
			return false
		}
	}
	for i := page; i < page + count; i++ {
		unsafe { refs[i]++ }
	}
	return true
}

pub fn pmm_refcount(ptr voidptr) u32 {
	page := u64(ptr) / page_size
	if page >= pmm_avl_page_count {
		return 0
	}
	pmm_lock.acquire()
	defer { pmm_lock.release() }
	return unsafe { (&u32(pmm_refcounts))[page] }
}

__global (
	slabs [14]Slab
)

struct MallocMetadata {
mut:
	pages u64
	size  u64
}

@[export: 'free']
pub fn free(ptr voidptr) {
	if ptr == unsafe { nil } {
		return
	}

	if u64(ptr) & (page_size - 1) == 0 {
		big_free(ptr)
		return
	}

	$if xnu_zone ? {
		xnu_heap_free(ptr)
		return
	}

	mut slab_hdr := unsafe { &SlabHeader(u64(ptr) & ~(page_size - 1)) }

	if slab_hdr.magic != slab_magic {
		lib.kpanic(unsafe { nil }, c'Slab: invalid free')
		return
	}
	slab_hdr.slab.sfree(ptr)
}

fn big_free(ptr voidptr) {
	metadata := unsafe { &MallocMetadata(u64(ptr) - page_size) }

	pmm_free(voidptr(u64(metadata) - higher_half), metadata.pages + 1)
}

fn slab_for(size u64) ?&Slab {
	for mut s in slabs {
		if s.ent_size >= size {
			return unsafe { s }
		}
	}

	return none
}

@[export: 'malloc']
pub fn malloc(size u64) voidptr {
	$if xnu_zone ? {
		return xnu_heap_alloc(size)
	}
	mut slab := slab_for(size) or { return big_alloc(size) }

	return slab.alloc()
}

fn big_alloc(size u64) voidptr {
	// Include the metadata page without overflowing rounding or byte counts.
	if size > (u64(-1) / page_size - 1) * page_size {
		return unsafe { nil }
	}
	page_count := lib.div_roundup(size, page_size)

	ptr := pmm_alloc(page_count + 1)

	if ptr == 0 {
		return 0
	}

	mut metadata := unsafe { &MallocMetadata(u64(ptr) + higher_half) }

	metadata.pages = page_count
	metadata.size = size

	return voidptr(u64(ptr) + higher_half + page_size)
}

@[export: 'realloc']
pub fn realloc(ptr voidptr, new_size u64) voidptr {
	if ptr == 0 {
		return malloc(new_size)
	}

	if u64(ptr) & (page_size - 1) == 0 {
		return big_realloc(ptr, new_size)
	}

	$if xnu_zone ? {
		return xnu_heap_realloc(ptr, new_size)
	}

	slab_hdr := unsafe { &SlabHeader(u64(ptr) & ~(page_size - 1)) }
	if slab_hdr.magic != slab_magic {
		lib.kpanic(unsafe { nil }, c'Slab: invalid realloc')
		return unsafe { nil }
	}
	mut slab := slab_hdr.slab

	if new_size > slab.ent_size {
		mut new_ptr := malloc(new_size)
		if new_ptr == unsafe { nil } {
			return unsafe { nil }
		}
		unsafe { C.memcpy(new_ptr, ptr, slab.ent_size) }
		slab.sfree(ptr)
		return new_ptr
	}

	return ptr
}

fn big_realloc(ptr voidptr, new_size u64) voidptr {
	if new_size > (u64(-1) / page_size - 1) * page_size {
		return unsafe { nil }
	}
	mut metadata := unsafe { &MallocMetadata(u64(ptr) - page_size) }

	if lib.div_roundup(metadata.size, page_size) == lib.div_roundup(new_size, page_size) {
		metadata.size = new_size
		return ptr
	}

	new_ptr := unsafe { malloc(new_size) }
	if new_ptr == 0 {
		return 0
	}

	if metadata.size > new_size {
		unsafe { C.memcpy(new_ptr, ptr, new_size) }
	} else {
		unsafe { C.memcpy(new_ptr, ptr, metadata.size) }
	}

	free(ptr)

	return new_ptr
}

@[export: 'calloc']
pub fn calloc(a u64, b u64) voidptr {
	if b != 0 && a > u64(-1) / b {
		return unsafe { nil }
	}
	return unsafe { malloc(a * b) }
}
