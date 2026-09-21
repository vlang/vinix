@[has_globals; manualfree]
module memory

import klock
import lib
import xnualloc

// The default bitmap path remains the independent Vinix implementation.
// -d xnu_bitmap selects the APSL-preserving translation in xnualloc.
// This does not select XNU magazines, VM expansion, or the full zone allocator.
// Each size class has a list of nonempty, nonfull pages and at most one
// empty spare page. Full pages are reached through their objects' headers.
// Allocation bits live in the header, never in freed object payloads.
// Headers remain in the same writable page: this is NOT metadata isolation
// or XNU's virtual-address/type sequestering.
const slab_magic = u64(0x56494e4958534c42)
const slab_alignment = u64(16)

pub struct Slab {
mut:
	@lock    klock.Lock
	ent_size u64
	partial  u64
	spare    u64
	// XNU scan cursor, serialized by the class lock (not per-CPU yet).
	alloc_rr u16
}

struct SlabHeader {
mut:
	slab     &Slab = unsafe { nil }
	magic    u64
	prev     u64
	next     u64
	capacity u64
	in_use   u64
	// Default: 1 = allocated/tail. With xnu_bitmap: 1 = free, 0 = used/tail.
	used     [4]u64
}

fn slab_data_offset() u64 {
	return lib.align_up(u64(sizeof(SlabHeader)), slab_alignment)
}

// Initialization is boot-only. Slab instances must not move after use.
// Pages are acquired lazily, without recursing through malloc.
pub fn (mut this Slab) init(ent_size u64) {
	if ent_size == 0 || ent_size > page_size / 2 || this.ent_size != 0 {
		lib.kpanic(unsafe { nil }, c'Slab: invalid initialization')
		return
	}
	this.ent_size = lib.align_up(ent_size, slab_alignment)
	capacity := (page_size - slab_data_offset()) / this.ent_size
	if capacity == 0 || capacity > 256 {
		lib.kpanic(unsafe { nil }, c'Slab: unsupported page geometry')
	}
}

// All list and bitmap operations require this.@lock.
fn (mut this Slab) add_partial(mut hdr SlabHeader) {
	hdr.prev = 0
	hdr.next = this.partial
	if this.partial != 0 {
		mut next := unsafe { &SlabHeader(this.partial) }
		next.prev = u64(hdr)
	}
	this.partial = u64(hdr)
}

fn (mut this Slab) remove_partial(mut hdr SlabHeader) {
	if hdr.prev == 0 {
		this.partial = hdr.next
	} else {
		mut prev := unsafe { &SlabHeader(hdr.prev) }
		prev.next = hdr.next
	}
	if hdr.next != 0 {
		mut next := unsafe { &SlabHeader(hdr.next) }
		next.prev = hdr.prev
	}
	hdr.prev = 0
	hdr.next = 0
}

// The argument must contain a zero bit. Bounded binary bit search, in V.
fn slab_first_zero(word u64) u64 {
	mut bits := ~word
	mut index := u64(0)
	if bits & u64(0xffffffff) == 0 {
		index += 32
		bits >>= 32
	}
	if bits & u64(0xffff) == 0 {
		index += 16
		bits >>= 16
	}
	if bits & u64(0xff) == 0 {
		index += 8
		bits >>= 8
	}
	if bits & u64(0xf) == 0 {
		index += 4
		bits >>= 4
	}
	if bits & u64(3) == 0 {
		index += 2
		bits >>= 2
	}
	if bits & u64(1) == 0 {
		index++
	}
	return index
}

fn (mut this Slab) grow() {
	base := u64(pmm_alloc_nozero(1)) + higher_half
	mut hdr := unsafe { &SlabHeader(base) }
	unsafe {
		C.memset(voidptr(hdr), 0, sizeof(SlabHeader))
		hdr.slab = this
	}
	hdr.magic = slab_magic
	hdr.capacity = (page_size - slab_data_offset()) / this.ent_size
	$if xnu_bitmap ? {
		xnualloc.zone_bits_init_ref(unsafe { &hdr.used[0] }, 4, u32(hdr.capacity))
	} $else {
		for i := 0; i < 4; i++ {
			hdr.used[i] = u64(-1)
		}
		for i := u64(0); i < hdr.capacity; i++ {
			hdr.used[int(i / 64)] &= ~(u64(1) << (i % 64))
		}
	}
	this.add_partial(mut hdr)
}

pub fn (mut this Slab) alloc() voidptr {
	this.@lock.acquire()
	if this.ent_size == 0 {
		this.@lock.release()
		lib.kpanic(unsafe { nil }, c'Slab: allocation before initialization')
		return unsafe { nil }
	}
	if this.partial == 0 {
		if this.spare != 0 {
			mut spare := unsafe { &SlabHeader(this.spare) }
			this.spare = 0
			this.add_partial(mut spare)
		} else {
			// Existing lock order: slab -> PMM. The PMM does not use malloc.
			this.grow()
		}
	}
	mut hdr := unsafe { &SlabHeader(this.partial) }
	mut slot := u64(256)
	$if xnu_bitmap ? {
		slot = xnualloc.zba_scan_bitmap_ref(unsafe { &hdr.used[0] }, 4, u64(this.alloc_rr) + 1)
		if slot != xnualloc.no_element {
			this.alloc_rr = u16(slot)
		}
	} $else {
		for i := 0; i < 4; i++ {
			if hdr.used[i] != u64(-1) {
				bit := slab_first_zero(hdr.used[i])
				hdr.used[i] |= u64(1) << bit
				slot = u64(i) * 64 + bit
				break
			}
		}
	}
	if slot >= hdr.capacity {
		this.@lock.release()
		lib.kpanic(unsafe { nil }, c'Slab: corrupt allocation bitmap')
		return unsafe { nil }
	}
	hdr.in_use++
	if hdr.in_use == hdr.capacity {
		this.remove_partial(mut hdr)
	}
	size := this.ent_size
	ptr := voidptr(u64(hdr) + slab_data_offset() + slot * size)
	this.@lock.release()

	// The reserved slot keeps its page live. Zeroing need not hold the lock.
	unsafe { C.memset(ptr, 0, size) }
	return ptr
}

pub fn (mut this Slab) sfree(ptr voidptr) {
	if ptr == unsafe { nil } {
		return
	}
	this.@lock.acquire()
	mut hdr := unsafe { &SlabHeader(u64(ptr) & ~(page_size - 1)) }
	offset := u64(ptr) & (page_size - 1)
	start := slab_data_offset()
	if hdr.magic != slab_magic || u64(hdr.slab) != unsafe { u64(&this) }
		|| this.ent_size == 0 || offset < start {
		this.@lock.release()
		lib.kpanic(unsafe { nil }, c'Slab: invalid free header')
		return
	}
	slot := (offset - start) / this.ent_size
	if (offset - start) % this.ent_size != 0 || slot >= hdr.capacity {
		this.@lock.release()
		lib.kpanic(unsafe { nil }, c'Slab: invalid free alignment')
		return
	}
	word := int(slot / 64)
	bit := u64(1) << (slot % 64)
	mut is_free := false
	$if xnu_bitmap ? {
		is_free = xnualloc.zone_bits_is_free_ref(unsafe { &hdr.used[0] }, 4, slot)
	} $else {
		is_free = hdr.used[word] & bit == 0
	}
	if is_free || hdr.in_use == 0 {
		this.@lock.release()
		lib.kpanic(unsafe { nil }, c'Slab: double free')
		return
	}
	was_full := hdr.in_use == hdr.capacity
	// Poison before publishing the slot as free.
	unsafe { C.memset(ptr, 0xaa, this.ent_size) }
	$if xnu_bitmap ? {
		// The class lock and preceding check guarantee success.
		if !xnualloc.zone_bits_mark_free_ref(unsafe { &hdr.used[0] }, 4, slot) {
			this.@lock.release()
			lib.kpanic(unsafe { nil }, c'Slab: corrupt XNU bitmap state')
			return
		}
	} $else {
		hdr.used[word] &= ~bit
	}
	hdr.in_use--
	mut release_page := u64(0)
	if hdr.in_use == 0 {
		if !was_full {
			this.remove_partial(mut hdr)
		}
		if this.spare == 0 {
			this.spare = u64(hdr)
		} else {
			release_page = u64(hdr)
			hdr.magic = 0
		}
	} else if was_full {
		this.add_partial(mut hdr)
	}
	this.@lock.release()
	if release_page != 0 {
		// Detached and empty: no valid outstanding object can reference it.
		pmm_free(voidptr(release_page - higher_half), 1)
	}
}

// Return empty spare pages explicitly; excess empty pages are already
// returned by sfree. Does not compact partially occupied pages. May be
// called concurrently, but never while holding a slab or PMM lock.
// Returns bytes released by this call, not a global free-memory snapshot.
pub fn heap_trim() u64 {
	$if xnu_zone ? {
		return xnu_heap_trim()
	}
	mut released := u64(0)
	for mut slab in slabs {
		slab.@lock.acquire()
		base := slab.spare
		slab.spare = 0
		if base != 0 {
			mut hdr := unsafe { &SlabHeader(base) }
			hdr.magic = 0
		}
		slab.@lock.release()
		if base != 0 {
			pmm_free(voidptr(base - higher_half), 1)
			released += page_size
		}
	}
	return released
}
