// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module compatcore

// Reusable page slabs. Links precede payloads so constructors run only once
// and free/reuse preserves object contents, exactly as in the C implementation.
struct CacheList {
mut:
	next &CacheList
	prev &CacheList
}

struct CacheSlot {
mut:
	slab      &CacheSlab
	free_next &CacheSlot
	index     usize
	allocated bool
}

struct CacheSlab {
mut:
	owner      &Cache
	all        CacheList
	available  CacheList
	free_slots &CacheSlot
	objects    voidptr
	capacity   usize
	live       usize
	pages      usize
}

struct Cache {
mut:
	guard          u32
	slabs          CacheList
	available      CacheList
	name           &char
	object_size    u32
	alignment      usize
	stride         usize
	pages_per_slab usize
	live_objects   usize
	active_refills usize
	ctor           fn (voidptr)
	closing        bool
}

pub fn list_init(head &CacheList) {
	unsafe {
		head.next = head
		head.prev = head
	}
}

pub fn list_empty(head &CacheList) bool {
	unsafe {
		return head.next == head
	}
}

pub fn list_add_tail(node &CacheList, head &CacheList) {
	unsafe {
		node.prev = head.prev
		node.next = head
		head.prev.next = node
		head.prev = node
	}
}

pub fn list_del(node &CacheList) {
	unsafe {
		node.next.prev = node.prev
		node.prev.next = node.next
	}
}

pub fn list_del_init(node &CacheList) {
	unsafe {
		list_del(node)
		list_init(node)
	}
}

pub fn slab_all(node &CacheList) &CacheSlab {
	unsafe {
		return &CacheSlab(usize(node) - __offsetof(CacheSlab, all))
	}
}

pub fn slab_available(node &CacheList) &CacheSlab {
	unsafe {
		return &CacheSlab(usize(node) - __offsetof(CacheSlab, available))
	}
}

pub fn cache_geometry(size u32, requested u32, flags u32, alignment &usize, stride &usize, pages &usize) bool {
	unsafe {
		if size == 0 || (requested != 0 && (requested & (requested - 1)) != 0) { return false }
		mut align := usize(requested)
		if (flags & 0x2000) != 0 {
			mut hardware := usize(64)
			for usize(size) <= hardware / 2 { hardware /= 2 }
			if align < hardware { align = hardware }
		}
		if align < 16 { align = 16 }
		if usize(size) > usize(-1) - sizeof(CacheSlot) { return false }
		mut step := sizeof(CacheSlot) + usize(size)
		if step > usize(-1) - (align - 1) { return false }
		step += align - 1
		step &= ~(align - 1)
		mut minimum := sizeof(CacheSlab) + sizeof(CacheSlot)
		if minimum > usize(-1) - (align - 1) { return false }
		minimum += align - 1
		if minimum > usize(-1) - usize(size) { return false }
		minimum += usize(size)
		page := C.vinix_linuxkpi_page_size()
		if page == 0 || (page & (page - 1)) != 0 || minimum > usize(-1) - (page - 1) {
			return false
		}
		minimum += page - 1
		*alignment = align
		*stride = step
		*pages = minimum / page
		return *pages != 0
	}
}

@[export: 'kmem_cache_create']
pub fn cache_create(name &char, size u32, alignment u32, flags u32, ctor fn (voidptr)) &Cache {
	unsafe {
		mut actual := usize(0)
		mut stride := usize(0)
		mut pages := usize(0)
		if usize(name) == 0 || !C.vinix_linuxkpi_may_sleep() || (flags & ~u32(0x2000)) != 0 || !cache_geometry(size, alignment, flags, &actual, &stride, &pages) {
			return nil
		}
		length := C.strlen(name)
		if length == usize(-1) { return nil }
		name_size := length + 1
		cache := &Cache(C.kzalloc(sizeof(Cache), 3264))
		if usize(cache) == 0 { return nil }
		cache.name = &char(C.kmalloc(name_size, 3264))
		if usize(cache.name) == 0 {
			C.kfree(cache)
			return nil
		}
		C.memcpy(cache.name, name, name_size)
		C.vkp_spin_init(&cache.guard)
		list_init(&cache.slabs)
		list_init(&cache.available)
		cache.object_size = size
		cache.alignment = actual
		cache.stride = stride
		cache.pages_per_slab = pages
		cache.ctor = ctor
		return cache
	}
}

pub fn cache_refill(cache &Cache, flags u32) &CacheSlab {
	unsafe {
		C.vkp_cache_ctor_warning(usize(cache.ctor) != 0 && (flags & 0x100) != 0)
		base := C.vinix_linuxkpi_alloc_gfp_pages(cache.pages_per_slab, flags)
		if usize(base) == 0 { return nil }
		page := C.vinix_linuxkpi_page_size()
		if page != 0 && cache.pages_per_slab > usize(-1) / page {
			C.vinix_linuxkpi_free_pages(base, cache.pages_per_slab)
			return nil
		}
		bytes := cache.pages_per_slab * page
		if usize(base) > usize(-1) - bytes || usize(base) > usize(-1) - sizeof(CacheSlab) {
			C.vinix_linuxkpi_free_pages(base, cache.pages_per_slab)
			return nil
		}
		end := usize(base) + bytes
		mut start := usize(base) + sizeof(CacheSlab)
		if start > usize(-1) - sizeof(CacheSlot) {
			C.vinix_linuxkpi_free_pages(base, cache.pages_per_slab)
			return nil
		}
		start += sizeof(CacheSlot)
		if start > usize(-1) - (cache.alignment - 1) {
			C.vinix_linuxkpi_free_pages(base, cache.pages_per_slab)
			return nil
		}
		start += cache.alignment - 1
		start &= ~(cache.alignment - 1)
		require(start <= end && usize(cache.object_size) <= end - start)
		slab := &CacheSlab(base)
		slab.owner = cache
		list_init(&slab.all)
		list_init(&slab.available)
		slab.objects = voidptr(start)
		slab.capacity = 1 + (end - start - usize(cache.object_size)) / cache.stride
		slab.live = 0
		slab.pages = cache.pages_per_slab
		slab.free_slots = nil
		for index := slab.capacity; index != 0; index-- {
			object := voidptr(start + (index - 1) * cache.stride)
			slot := &CacheSlot(usize(object) - sizeof(CacheSlot))
			slot.slab = slab
			slot.free_next = slab.free_slots
			slot.index = index - 1
			slot.allocated = false
			slab.free_slots = slot
			if usize(cache.ctor) != 0 { cache.ctor(object) }
		}
		return slab
	}
}

pub fn cache_take_locked(cache &Cache, slab &CacheSlab) voidptr {
	unsafe {
		slot := slab.free_slots
		require(usize(slot) != 0 && !slot.allocated && slot.slab == slab && slab.live < slab.capacity && cache.live_objects != usize(-1))
		slab.free_slots = slot.free_next
		slot.free_next = nil
		slot.allocated = true
		slab.live++
		cache.live_objects++
		if usize(slab.free_slots) == 0 { list_del_init(&slab.available) }
		return voidptr(usize(slot) + sizeof(CacheSlot))
	}
}

@[export: 'kmem_cache_alloc']
pub fn cache_alloc(cache &Cache, flags u32) voidptr {
	unsafe {
		if usize(cache) == 0 || !C.vinix_linuxkpi_gfp_supported(flags) { return nil }
		mut irq := C.vkp_spin_lock_irqsave(&cache.guard)
		require(!cache.closing)
		mut object := voidptr(nil)
		if !list_empty(&cache.available) {
			object = cache_take_locked(cache, slab_available(cache.available.next))
			C.vkp_spin_unlock_irqrestore(&cache.guard, irq)
		} else {
			require(cache.active_refills != usize(-1))
			cache.active_refills++
			C.vkp_spin_unlock_irqrestore(&cache.guard, irq)
			slab := cache_refill(cache, flags)
			irq = C.vkp_spin_lock_irqsave(&cache.guard)
			require(cache.active_refills != 0 && !cache.closing)
			cache.active_refills--
			if usize(slab) == 0 {
				C.vkp_spin_unlock_irqrestore(&cache.guard, irq)
				return nil
			}
			list_add_tail(&slab.all, &cache.slabs)
			list_add_tail(&slab.available, &cache.available)
			object = cache_take_locked(cache, slab)
			C.vkp_spin_unlock_irqrestore(&cache.guard, irq)
		}
		if (flags & 0x100) != 0 { C.memset(object, 0, usize(cache.object_size)) }
		return object
	}
}

@[export: 'kmem_cache_free']
pub fn cache_free(cache &Cache, object voidptr) {
	unsafe {
		if usize(object) == 0 { return }
		require(usize(cache) != 0 && usize(object) >= sizeof(CacheSlot))
		slot := &CacheSlot(usize(object) - sizeof(CacheSlot))
		slab := slot.slab
		irq := C.vkp_spin_lock_irqsave(&cache.guard)
		require(slab.owner == cache && slot.index < slab.capacity && usize(object) == usize(slab.objects) + slot.index * cache.stride && slot.allocated && slab.live != 0 && cache.live_objects != 0)
		was_full := usize(slab.free_slots) == 0
		slot.allocated = false
		slot.free_next = slab.free_slots
		slab.free_slots = slot
		slab.live--
		cache.live_objects--
		if was_full { list_add_tail(&slab.available, &cache.available) }
		C.vkp_spin_unlock_irqrestore(&cache.guard, irq)
		// Shrink can release the last empty slab now; no fields are read after unlock.
	}
}

pub fn cache_release_slabs(head_ &CacheList) {
	unsafe {
		for !list_empty(head_) {
			slab := slab_all(head_.next)
			pages := slab.pages
			list_del(&slab.all)
			C.vinix_linuxkpi_free_pages(slab, pages)
		}
	}
}

@[export: 'kmem_cache_shrink']
pub fn cache_shrink(cache &Cache) i32 {
	unsafe {
		require(usize(cache) != 0 && C.vinix_linuxkpi_may_sleep())
		mut detached := CacheList{}
		list_init(&detached)
		irq := C.vkp_spin_lock_irqsave(&cache.guard)
		require(!cache.closing)
		mut node := cache.slabs.next
		for node != &cache.slabs {
			next := node.next
			slab := slab_all(node)
			if slab.live == 0 {
				list_del_init(&slab.available)
				list_del(&slab.all)
				list_add_tail(&slab.all, &detached)
			}
			node = next
		}
		remaining := i32(!list_empty(&cache.slabs) || cache.active_refills != 0)
		C.vkp_spin_unlock_irqrestore(&cache.guard, irq)
		cache_release_slabs(&detached)
		return remaining
	}
}

@[export: 'kmem_cache_destroy']
pub fn cache_destroy(cache &Cache) {
	unsafe {
		if usize(cache) == 0 { return }
		require(C.vinix_linuxkpi_may_sleep())
		mut detached := CacheList{}
		list_init(&detached)
		irq := C.vkp_spin_lock_irqsave(&cache.guard)
		require(!cache.closing && cache.live_objects == 0 && cache.active_refills == 0)
		cache.closing = true
		for !list_empty(&cache.slabs) {
			slab := slab_all(cache.slabs.next)
			require(slab.live == 0)
			list_del_init(&slab.available)
			list_del(&slab.all)
			list_add_tail(&slab.all, &detached)
		}
		C.vkp_spin_unlock_irqrestore(&cache.guard, irq)
		cache_release_slabs(&detached)
		C.kfree(cache.name)
		C.kfree(cache)
	}
}

@[export: 'kmem_cache_size']
pub fn cache_size(cache &Cache) u32 {
	unsafe {
		require(usize(cache) != 0)
		return cache.object_size
	}
}
