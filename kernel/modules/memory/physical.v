// physical.v: Page-frame allocator + slab allocator.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

@[manualfree]
module memory

import lib
import klock
import limine

__global (
	pmm_lock            klock.Lock
	pmm_bitmap          = voidptr(0)
	pmm_avl_page_count  = u64(0)
	pmm_last_used_index = u64(0)
	free_pages          = u64(0)
)

pub fn print_free() {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	C.printf(c'pmm: Free pages: %llu\n', free_pages)
}

pub fn pmm_init() {
	memmap := memmap_req.response

	unsafe {
		mut highest_address := u64(0)
		mut entries := memmap.entries

		// Calculate how big the memory map needs to be.
		for i := 0; i < memmap.entry_count; i++ {
			C.printf(c'pmm: Memory map entry %d: 0x%llx->0x%llx  0x%llx\n',
					 i, entries[i].base, entries[i].length, entries[i].@type)

			if entries[i].@type != u32(limine.limine_memmap_usable)
				&& entries[i].@type != u32(limine.limine_memmap_bootloader_reclaimable)
				&& entries[i].@type != u32(limine.limine_memmap_kernel_and_modules) {
				continue
			}
			top := entries[i].base + entries[i].length
			if top > highest_address {
				highest_address = top
			}
		}

		// Calculate the needed size for the bitmap in bytes and align it to page size.
		pmm_avl_page_count = lib.div_roundup(highest_address, page_size)
		bitmap_size := lib.align_up(pmm_avl_page_count / 8, page_size)

		C.printf(c'pmm: Bitmap size: %llu\n', bitmap_size)

		// Find a hole for the bitmap in the memory map.
		for i := 0; i < memmap.entry_count; i++ {
			if entries[i].@type != u32(limine.limine_memmap_usable) {
				continue
			}
			if entries[i].length >= bitmap_size {
				pmm_bitmap = voidptr(entries[i].base + higher_half)

				// Initialise entire bitmap to 1 (non-free)
				C.memset(pmm_bitmap, 0xff, bitmap_size)

				entries[i].length -= bitmap_size
				entries[i].base += bitmap_size

				break
			}
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
	}
	print_free()

	// Initialise slabs
	slabs[0].init(8)
	slabs[1].init(16)
	slabs[2].init(32)
	slabs[3].init(64)
	slabs[4].init(128)
	slabs[5].init(256)
	slabs[6].init(512)
	slabs[7].init(1024)
	slabs[8].init(2048)
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
				}
				return voidptr(page * page_size)
			}
		} else {
			pmm_last_used_index++
			p = 0
		}
	}
	return 0
}

pub fn pmm_alloc_nozero(count u64) voidptr {
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
			lib.kpanic(voidptr(0), c'Out of memory')
		}
	}

	free_pages -= count

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

pub fn pmm_free(ptr voidptr, count u64) {
	pmm_lock.acquire()
	defer {
		pmm_lock.release()
	}
	unsafe {
		mut p := &u64(u64(ptr) + higher_half)
		for i := u64(0); i < (count * page_size) / 8; i++ {
			p[i] = 0xaaaaaaaaaaaaaaaa
		}
	}
	page := u64(ptr) / page_size
	for i := page; i < page + count; i++ {
		lib.bitreset(pmm_bitmap, i)
	}
	free_pages += count
}

pub struct Slab {
mut:
	@lock      klock.Lock
	first_free u64
	ent_size   u64
}

struct SlabHeader {
mut:
	slab &Slab
}

pub fn (mut this Slab) init(ent_size u64) {
	this.ent_size = ent_size
	this.first_free = u64(pmm_alloc_nozero(1))
	this.first_free += higher_half

	avl_size := page_size - lib.align_up(sizeof(SlabHeader), ent_size)
	mut slabptr := &SlabHeader(this.first_free)
	unsafe {
		slabptr[0].slab = this
	}
	this.first_free += lib.align_up(sizeof(SlabHeader), ent_size)

	mut arr := &u64(this.first_free)
	max := avl_size / ent_size - 1
	fact := ent_size / 8
	for i := u64(0); i < max; i++ {
		unsafe {
			arr[i * fact] = u64(&arr[(i + 1) * fact])
		}
	}

	unsafe {
		arr[max * fact] = u64(0)
	}
}

pub fn (mut this Slab) alloc() voidptr {
	this.@lock.acquire()
	defer {
		this.@lock.release()
	}

	if this.first_free == 0 {
		this.init(this.ent_size)
	}

	mut old_free := &u64(this.first_free)
	this.first_free = unsafe { old_free[0] }

	unsafe { C.memset(voidptr(old_free), 0, this.ent_size) }

	return voidptr(old_free)
}

pub fn (mut this Slab) sfree(ptr voidptr) {
	this.@lock.acquire()
	defer {
		this.@lock.release()
	}

	if ptr == voidptr(0) {
		return
	}

	unsafe { C.memset(ptr, 0xaa, this.ent_size) }

	mut new_head := &u64(ptr)
	unsafe {
		new_head[0] = this.first_free
	}
	this.first_free = u64(new_head)
}

__global (
	slabs [9]Slab
)

struct MallocMetadata {
mut:
	pages u64
	size  u64
}

@[export: 'free']
pub fn free(ptr voidptr) {
	if ptr == voidptr(0) {
		return
	}

	if u64(ptr) & u64(0xfff) == 0 {
		big_free(ptr)
		return
	}

	mut slab_hdr := &SlabHeader(u64(ptr) & ~u64(0xfff))

	slab_hdr.slab.sfree(ptr)
}

fn big_free(ptr voidptr) {
	metadata := &MallocMetadata(u64(ptr) - page_size)

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
	mut slab := slab_for(size) or { return big_alloc(size) }

	return slab.alloc()
}

fn big_alloc(size u64) voidptr {
	page_count := lib.div_roundup(size, page_size)

	ptr := pmm_alloc(page_count + 1)

	if ptr == 0 {
		return 0
	}

	mut metadata := &MallocMetadata(u64(ptr) + higher_half)

	metadata.pages = page_count
	metadata.size = size

	return voidptr(u64(ptr) + higher_half + page_size)
}

@[export: 'realloc']
pub fn realloc(ptr voidptr, new_size u64) voidptr {
	if ptr == 0 {
		return malloc(new_size)
	}

	if u64(ptr) & u64(0xfff) == 0 {
		return big_realloc(ptr, new_size)
	}

	slab_hdr := &SlabHeader(u64(ptr) & ~u64(0xfff))
	mut slab := slab_hdr.slab

	if new_size > slab.ent_size {
		mut new_ptr := malloc(new_size)
		unsafe { C.memcpy(new_ptr, ptr, slab.ent_size) }
		slab.sfree(ptr)
		return new_ptr
	}

	return ptr
}

fn big_realloc(ptr voidptr, new_size u64) voidptr {
	mut metadata := &MallocMetadata(u64(ptr) - page_size)

	if lib.div_roundup(metadata.size, page_size) == lib.div_roundup(new_size, page_size) {
		metadata.size = new_size
		return ptr
	}

	new_ptr := unsafe { C.malloc(new_size) }
	if new_ptr == 0 {
		return 0
	}

	if metadata.size > new_size {
		unsafe { C.memcpy(new_ptr, ptr, new_size) }
	} else {
		unsafe { C.memcpy(new_ptr, ptr, metadata.size) }
	}

	C.free(ptr)

	return new_ptr
}

@[export: 'calloc']
pub fn calloc(a u64, b u64) voidptr {
	return unsafe { C.malloc(a * b) }
}
