// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Memory a device reads and writes by itself.
//
// A driver used to take pages from the physical allocator and write their
// physical address into a device register, on the assumption that the address
// the device puts on the bus is the address the CPU uses. That holds on a PC
// with no IOMMU and nowhere else, and it leaves every device able to read and
// write all of memory. Here a driver asks for memory *for a device* and is
// told two addresses: where the kernel sees it (`virt`) and what to tell the
// device (`bus`).
//
// Behind that, each device has a domain: the set of pages it has been given.
// With no IOMMU in front of the device the domain is only a list, and `bus`
// is the physical address. With one (see iommu.v) the domain is a set of page
// tables, the device can reach the pages in its list and nothing else, and a
// device with no domain at all can reach nothing.
//
// The list is also what makes unbinding safe. A driver that is removed frees
// its buffers; whatever it forgot is unmapped and freed by release() when the
// device core takes the device back, so no page stays reachable by a device
// that no longer has a driver -- and with an IOMMU, a device whose driver gave
// up on it mid-transfer is cut off before its memory is reused.
//
// The bus address handed out is the physical address even behind an IOMMU:
// the domain maps each page at the address it already has. Giving out other
// addresses would hide the layout of memory from the device, which nothing
// here needs, at the price of an allocator per domain. What a device cannot
// address -- memory above 4 GiB for one with 32-bit registers -- is refused
// rather than remapped (set_address_bits()).
@[has_globals]
module dma

import devcore
import klock
import lib
import memory

pub struct Buffer {
pub:
	// Where the kernel reads and writes it.
	virt u64
	// What the device is told.
	bus u64
	// As asked for; the pages behind it are whole.
	bytes u64
}

// One run of pages a device may reach.
struct Mapping {
mut:
	next  &Mapping = unsafe { nil }
	phys  u64
	pages u64
	// Whether the pages came from alloc_buffer() and go back to the allocator.
	owned bool
}

@[heap]
pub struct Domain {
pub mut:
	lock     klock.Lock
	mappings &Mapping = unsafe { nil }
	// How many pages the device can reach now, and the most it ever could.
	pages      u64
	peak_pages u64
	// The highest address the device can be told; see set_address_bits().
	limit u64 = ~u64(0)
	// The IOMMU in front of the device and its page tables for it, or nil.
	iommu  &Iommu = unsafe { nil }
	cookie voidptr
	// Every page of RAM is mapped: a driver that has not been taught to ask.
	identity bool
}

__global (
	// Guards a device's pointer to its domain, and the list of IOMMUs.
	dma_lock klock.Lock
)

// The device's domain, made when its driver first asks for memory. That is in
// its probe, which the device core runs one at a time for a device, so two
// CPUs do not make one each; dma_lock only orders the publication against a
// reader of sysfs.
fn domain_of(mut dev devcore.Device) &Domain {
	if dev.dma != unsafe { nil } {
		return unsafe { &Domain(dev.dma) }
	}
	devcore.set_dma_hooks(release, block, describe)
	// Freed by release().
	mut domain := &Domain{} @[freed]
	domain.limit = ~u64(0)
	domain.iommu = iommu_for(dev)
	if domain.iommu != unsafe { nil } {
		domain.cookie = domain.iommu.attach(domain.iommu, mut dev)
		if domain.cookie == unsafe { nil } {
			// The unit could not make page tables for it. The device stays
			// blocked, which is what a device nothing vouches for should be.
			C.kprintf(c'dma: %.*s could not be attached to its IOMMU; it will be refused memory\n',
				i32(dev.name.len), dev.name.str)
		}
	}
	dma_lock.acquire()
	dev.dma = voidptr(domain)
	dma_lock.release()
	return domain
}

fn pages_for(bytes u64) u64 {
	return lib.div_roundup(bytes, page_size)
}

// Tell the core how many address bits the device's registers hold, when it is
// fewer than 64. Memory it could not be told the address of is then refused.
pub fn set_address_bits(mut dev devcore.Device, bits u8) {
	mut domain := domain_of(mut dev)
	domain.limit = if bits >= 64 { ~u64(0) } else { (u64(1) << bits) - 1 }
}

fn (mut domain Domain) track(phys u64, pages u64, owned bool) bool {
	allocation := memory.malloc_packed_fallible(sizeof(Mapping))
	if allocation == unsafe { nil } {
		return false
	}
	mut mapping := unsafe { &Mapping(allocation) }
	unsafe {
		*mapping = Mapping{
			phys:  phys
			pages: pages
			owned: owned
		}
	}
	domain.lock.acquire()
	mapping.next = domain.mappings
	domain.mappings = mapping
	domain.pages += pages
	if domain.pages > domain.peak_pages {
		domain.peak_pages = domain.pages
	}
	domain.lock.release()
	return true
}

// Take the record for the run starting at `phys` off the list. None if the
// device was never given it.
fn (mut domain Domain) untrack(phys u64) ?Mapping {
	domain.lock.acquire()
	mut previous := &Mapping(unsafe { nil })
	mut mapping := domain.mappings
	for mapping != unsafe { nil } {
		if mapping.phys == phys {
			if previous == unsafe { nil } {
				domain.mappings = mapping.next
			} else {
				previous.next = mapping.next
			}
			domain.pages -= mapping.pages
			domain.lock.release()
			found := Mapping{
				phys:  mapping.phys
				pages: mapping.pages
				owned: mapping.owned
			}
			memory.free(voidptr(mapping))
			return found
		}
		previous = mapping
		mapping = mapping.next
	}
	domain.lock.release()
	return none
}

// Let the device reach `pages` pages at `phys`, on every path there is.
fn (mut domain Domain) open(phys u64, pages u64) bool {
	if phys + pages * page_size - 1 > domain.limit {
		return false
	}
	if domain.iommu == unsafe { nil } || domain.identity {
		return true
	}
	if domain.cookie == unsafe { nil } {
		return false
	}
	return domain.iommu.map(domain.cookie, phys, phys, pages * page_size)
}

// Whether a run still on the list covers the page at `phys`.
fn (mut domain Domain) still_covers(phys u64) bool {
	domain.lock.acquire()
	defer {
		domain.lock.release()
	}
	for mapping := domain.mappings; mapping != unsafe { nil }; mapping = mapping.next {
		if phys >= mapping.phys && phys < mapping.phys + mapping.pages * page_size {
			return true
		}
	}
	return false
}

// Stop the device reaching `pages` pages at `phys`, whose record has just come
// off the list -- except the pages another record still covers. Two requests
// that were mapped separately can share a page, and taking it from the device
// when the first of them finishes would take it from the second.
fn (mut domain Domain) close(phys u64, pages u64) {
	if domain.iommu == unsafe { nil } || domain.cookie == unsafe { nil } || domain.identity {
		return
	}
	mut start := u64(0)
	mut run := u64(0)
	for i := u64(0); i < pages; i++ {
		page := phys + i * page_size
		if domain.still_covers(page) {
			if run != 0 {
				domain.iommu.unmap(domain.cookie, start, run * page_size)
				run = 0
			}
			continue
		}
		if run == 0 {
			start = page
		}
		run++
	}
	if run != 0 {
		domain.iommu.unmap(domain.cookie, start, run * page_size)
	}
}

// Zeroed, physically contiguous memory for `dev` to read and write: a
// descriptor ring, a command table, a block of frame buffers. None when there
// is no memory, or none the device can address or be allowed to reach.
pub fn alloc_buffer(mut dev devcore.Device, bytes u64) ?Buffer {
	if bytes == 0 {
		return none
	}
	mut domain := domain_of(mut dev)
	pages := pages_for(bytes)
	phys := u64(memory.pmm_alloc_fallible(pages))
	if phys == 0 {
		return none
	}
	if !domain.open(phys, pages) {
		memory.pmm_free(voidptr(phys), pages)
		return none
	}
	if !domain.track(phys, pages, true) {
		domain.close(phys, pages)
		memory.pmm_free(voidptr(phys), pages)
		return none
	}
	return Buffer{
		virt:  phys + memory.get_hhdm_offset()
		bus:   phys
		bytes: bytes
	}
}

// Give back what alloc_buffer() gave. The device must already have been told to stop
// using it: once this returns the pages belong to someone else.
pub fn free_buffer(mut dev devcore.Device, buffer Buffer) {
	if buffer.bus == 0 || dev.dma == unsafe { nil } {
		return
	}
	mut domain := unsafe { &Domain(dev.dma) }
	mapping := domain.untrack(buffer.bus) or { return }
	domain.close(mapping.phys, mapping.pages)
	if mapping.owned {
		memory.pmm_free(voidptr(mapping.phys), mapping.pages)
	}
}

// Let `dev` reach memory the caller already has: the pages of a request that
// are read or written in place. `phys` and `bytes` are rounded out to whole
// pages, so nothing else that must stay private may share them. Returns the
// address to give the device.
pub fn map_memory(mut dev devcore.Device, phys u64, bytes u64) ?u64 {
	if bytes == 0 {
		return none
	}
	mut domain := domain_of(mut dev)
	base := lib.align_down(phys, page_size)
	pages := pages_for(phys + bytes - base)
	if !domain.open(base, pages) {
		return none
	}
	if !domain.track(base, pages, false) {
		domain.close(base, pages)
		return none
	}
	return phys
}

// Take back what map_memory() opened, by the address it returned.
pub fn unmap_memory(mut dev devcore.Device, bus u64) {
	if dev.dma == unsafe { nil } {
		return
	}
	mut domain := unsafe { &Domain(dev.dma) }
	mapping := domain.untrack(lib.align_down(bus, page_size)) or { return }
	domain.close(mapping.phys, mapping.pages)
}

// For a driver that still writes physical addresses of its own choosing into
// its device: let the device reach all of memory, as it could before there
// was an IOMMU. It keeps such a driver working behind one and isolates
// nothing, and sysfs says so.
pub fn allow_all(mut dev devcore.Device) bool {
	mut domain := domain_of(mut dev)
	if domain.identity {
		return true
	}
	if domain.iommu != unsafe { nil } {
		if domain.cookie == unsafe { nil } || !domain.iommu.map_all(domain.cookie) {
			return false
		}
	}
	domain.identity = true
	return true
}

// The device has no driver any more. Whatever the driver left mapped is
// closed and, if it was the driver's own, freed; then the domain goes, and
// behind an IOMMU the device is back to reaching nothing. Returns how many
// pages the driver had left behind.
pub fn release(mut dev devcore.Device) u64 {
	if dev.dma == unsafe { nil } {
		return 0
	}
	mut domain := unsafe { &Domain(dev.dma) }
	mut leaked := u64(0)
	for {
		domain.lock.acquire()
		mut mapping := domain.mappings
		if mapping == unsafe { nil } {
			domain.lock.release()
			break
		}
		domain.mappings = mapping.next
		domain.pages -= mapping.pages
		domain.lock.release()
		domain.close(mapping.phys, mapping.pages)
		if mapping.owned {
			memory.pmm_free(voidptr(mapping.phys), mapping.pages)
		}
		leaked += mapping.pages
		memory.free(voidptr(mapping))
	}
	if domain.iommu != unsafe { nil } && domain.cookie != unsafe { nil } {
		domain.iommu.detach(domain.cookie)
	}
	dma_lock.acquire()
	dev.dma = unsafe { nil }
	dma_lock.release()
	unsafe { free(domain) }
	return leaked
}

// The device's driver gave up on it and cannot be made to let go: the pages
// stay the driver's, but behind an IOMMU the device can no longer reach them,
// or anything else.
pub fn block(mut dev devcore.Device) {
	if dev.dma == unsafe { nil } {
		return
	}
	mut domain := unsafe { &Domain(dev.dma) }
	if domain.iommu != unsafe { nil } && domain.cookie != unsafe { nil } {
		domain.iommu.detach(domain.cookie)
		domain.cookie = unsafe { nil }
		domain.identity = false
	}
}

// What a device's `dma` file in sysfs says.
pub fn describe(dev &devcore.Device, mut text lib.Text) {
	// Held so that the domain is not freed under the reader.
	dma_lock.acquire()
	defer {
		dma_lock.release()
	}
	if dev.dma == unsafe { nil } {
		text.add('domain: none\n')
		return
	}
	domain := unsafe { &Domain(dev.dma) }
	text.add('domain: ')
	if domain.iommu == unsafe { nil } {
		text.add('direct\n')
	} else {
		text.add(domain.iommu.name)
		text.add(if domain.identity {
			' identity\n'
		} else if domain.cookie == unsafe { nil } {
			' blocked\n'
		} else {
			' isolated\n'
		})
	}
	text.add('pages: ')
	text.add_unsigned(domain.pages)
	text.add('\npeak_pages: ')
	text.add_unsigned(domain.peak_pages)
	text.add('\naddress_limit: 0x')
	text.add_radix(domain.limit, 16, 0)
	text.add_byte(`\n`)
}
