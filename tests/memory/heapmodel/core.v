// Independent slab transition specification. No kernel module is imported.
module heapmodel

pub const page_size = u64(4096)
pub const bitmap_words = 16
pub const classes = [16, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
pub const mask = u64(0xffffffffffffffff)

struct HeaderLayout {
	slab     u64
	magic    u64
	prev     u64
	next     u64
	capacity u64
	in_use   u64
	used     [16]u64
}

pub fn header_offset() u64 { return (u64(sizeof(HeaderLayout)) + 15) & ~u64(15) }

pub fn first_zero(word u64) !int {
	mut bits := ~word
	if bits == 0 { return error('requires a zero bit') }
	mut index := 0
	for shift in [32, 16, 8, 4, 2] {
		if bits & ((u64(1) << shift) - 1) == 0 {
			index += shift
			bits >>= shift
		}
	}
	if bits & 1 == 0 { index++ }
	return index
}

pub struct Page {
pub mut:
	base    u64
	size    int
	prev    u64
	next    u64
	count   int
	bits    [16]u64
	payload [4096]u8
}

pub fn (page Page) capacity() int { return int((page_size - header_offset()) / u64(page.size)) }

@[heap]
pub struct PMM {
pub mut:
	pages       map[u64]&Page
	returned    []u64
	next_base   u64 = page_size
	allocations int
	frees       int
}

pub fn (pmm &PMM) page(base u64) &Page { return pmm.pages[base] or { panic('invalid page') } }

pub fn (mut pmm PMM) allocate(size int) &Page {
	mut base := pmm.next_base
	if pmm.returned.len > 0 { base = pmm.returned.pop() } else { pmm.next_base += page_size }
	mut page := &Page{ base: base, size: size }
	for i in 0 .. bitmap_words { page.bits[i] = mask }
	for i in 0 .. 4096 { page.payload[i] = 0xaa }
	for slot in 0 .. page.capacity() { page.bits[slot / 64] &= ~(u64(1) << (slot % 64)) }
	pmm.pages[base] = page
	pmm.allocations++
	return page
}

pub fn (mut pmm PMM) release(page &Page) {
	assert page.count == 0
	assert pmm.page(page.base) == page
	pmm.pages.delete(page.base)
	pmm.returned << page.base
	pmm.frees++
}

pub struct Slab {
pub mut:
	pmm     &PMM = unsafe { nil }
	size    int
	partial u64
	spare   u64
	owned   map[u64]bool
	live    map[u64]bool
}

pub fn slab(pmm &PMM, size int) Slab { return Slab{ pmm: pmm, size: size } }

fn (mut slab Slab) add(mut page Page) {
	page.prev = 0
	page.next = slab.partial
	if slab.partial != 0 {
		mut first := slab.pmm.page(slab.partial)
		first.prev = page.base
	}
	slab.partial = page.base
}

fn (mut slab Slab) remove(mut page Page) {
	if page.prev == 0 {
		slab.partial = page.next
	} else {
		mut previous := slab.pmm.page(page.prev)
		previous.next = page.next
	}
	if page.next != 0 {
		mut next := slab.pmm.page(page.next)
		next.prev = page.prev
	}
	page.prev = 0
	page.next = 0
}

pub fn (mut slab Slab) allocate() u64 {
	if slab.partial == 0 {
		mut page := &Page(unsafe { nil })
		if slab.spare != 0 {
			page = slab.pmm.page(slab.spare)
			slab.spare = 0
		} else {
			page = slab.pmm.allocate(slab.size)
			slab.owned[page.base] = true
		}
		slab.add(mut page)
	}
	mut page := slab.pmm.page(slab.partial)
	mut slot := -1
	for i, word in page.bits {
		if word != mask {
			bit := first_zero(word) or { panic(err) }
			page.bits[i] |= u64(1) << bit
			slot = i * 64 + bit
			break
		}
	}
	assert slot >= 0, 'no slot on a partial page'
	assert slot < page.capacity()
	page.count++
	if page.count == page.capacity() { slab.remove(mut page) }
	address := page.base + header_offset() + u64(slot * slab.size)
	assert address !in slab.live && address % 16 == 0
	slab.live[address] = true
	offset := int(address - page.base)
	for i in offset .. offset + slab.size { page.payload[i] = 0 }
	return address
}

pub fn (mut slab Slab) release(address u64) ! {
	if address == 0 { return }
	base := address & ~(page_size - 1)
	offset := address & (page_size - 1)
	if base !in slab.owned || offset < header_offset() { return error('invalid header') }
	mut page := slab.pmm.page(base)
	slot := int((offset - header_offset()) / u64(slab.size))
	remainder := (offset - header_offset()) % u64(slab.size)
	if remainder != 0 || slot >= page.capacity() { return error('invalid alignment') }
	word := slot / 64
	bit := u64(1) << (slot % 64)
	if page.bits[word] & bit == 0 || page.count == 0 { return error('double free') }
	full := page.count == page.capacity()
	for i in int(offset) .. int(offset) + slab.size { page.payload[i] = 0xaa }
	page.bits[word] &= ~bit
	page.count--
	assert address in slab.live
	slab.live.delete(address)
	if page.count == 0 {
		if !full { slab.remove(mut page) }
		if slab.spare == 0 {
			slab.spare = base
		} else {
			slab.owned.delete(base)
			slab.pmm.release(page)
		}
	} else if full {
		slab.add(mut page)
	}
}

pub fn (mut slab Slab) trim() u64 {
	if slab.spare == 0 { return 0 }
	base := slab.spare
	slab.spare = 0
	slab.owned.delete(base)
	slab.pmm.release(slab.pmm.page(base))
	return page_size
}

pub fn (slab Slab) check() {
	mut linked := map[u64]bool{}
	mut base := slab.partial
	mut prev := u64(0)
	for base != 0 {
		assert base !in linked
		linked[base] = true
		page := slab.pmm.page(base)
		assert page.prev == prev && page.count > 0 && page.count < page.capacity()
		prev = base
		base = page.next
	}
	mut expected_partial := map[u64]bool{}
	mut expected_live := map[u64]bool{}
	for owned in slab.owned.keys() {
		page := slab.pmm.page(owned)
		assert page.count >= 0 && page.count <= page.capacity()
		mut active := 0
		for slot in 0 .. 256 {
			used := page.bits[slot / 64] & (u64(1) << (slot % 64)) != 0
			if slot >= page.capacity() {
				assert used, 'tail slot became available'
			} else if used {
				active++
				expected_live[owned + header_offset() + u64(slot * slab.size)] = true
			}
		}
		assert active == page.count
		if page.count == 0 {
			assert owned == slab.spare && page.prev == 0 && page.next == 0
		} else if page.count < page.capacity() {
			expected_partial[owned] = true
		} else {
			assert page.prev == 0 && page.next == 0
		}
	}
	assert linked == expected_partial
	assert slab.live == expected_live
	if slab.spare != 0 {
		assert slab.spare in slab.owned
	}
}

pub fn checked_product(a u64, b u64) ?u64 {
	if b != 0 && a > mask / b { return none }
	return a * b
}
