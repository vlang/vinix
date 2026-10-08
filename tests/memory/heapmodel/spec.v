// The ten original independent model scenarios, with the same seeded plan.
module heapmodel

import os
import regex
import math.big

pub fn source_geometry(root string) ! {
	source := os.read_file(os.join_path(root, 'kernel/memory/physical.v'))!
	mut pattern := regex.regex_opt(r'slabs\[\d+\]\.init\((\d+)\)')!
	actual := pattern.find_all_str(source).map(it.all_after('.init(').all_before(')').int())
	assert actual == classes
	assert header_offset() == 176
	slab_source := os.read_file(os.join_path(root, 'kernel/memory/slab.v'))!
	assert slab_source.contains('const slab_bitmap_words = 16')
	mut used := regex.regex_opt(r'used\s+\[slab_bitmap_words\]u64')!
	start, _ := used.find(slab_source)
	assert start >= 0
	assert slab_source.contains('const slab_alignment = u64(16)')
	for size in classes {
		assert size % 16 == 0
		assert (page_size - header_offset()) / u64(size) >= 1
		assert (page_size - header_offset()) / u64(size) <= 256
	}
}

pub fn bit_search() {
	for bit in 0 .. 64 {
		assert first_zero(mask ^ (u64(1) << bit)) or { panic(err) } == bit
	}
	mut rng := random(12345)
	for _ in 0 .. 20000 {
		word := rng.bits(64)
		if word != mask {
			available := ~word
			lowest := available & (~available + u64(1))
			mut oracle := 0
			mut value := lowest
			for value > 1 {
				value >>= 1
				oracle++
			}
			assert first_zero(word) or { panic(err) } == oracle
		}
	}
}

pub fn all_classes_lifecycle() {
	for size in classes {
		mut pmm := &PMM{}
		mut allocator := slab(pmm, size)
		capacity := int((page_size - header_offset()) / u64(size))
		mut objects := []u64{}
		for _ in 0 .. 3 * capacity + 1 { objects << allocator.allocate() }
		assert pmm.pages.len == 4
		allocator.check()
		for parity in 0 .. 2 {
			for i := parity; i < objects.len; i += 2 {
				allocator.release(objects[i]) or { panic(err) }
				allocator.check()
			}
		}
		assert pmm.pages.len == 1
		assert allocator.trim() == page_size
		assert allocator.trim() == 0
		allocator.check()
		assert pmm.pages.len == 0
		assert pmm.allocations == pmm.frees
	}
}

pub fn single_slot() {
	mut pmm := &PMM{}
	mut allocator := slab(pmm, 2048)
	a := allocator.allocate()
	b := allocator.allocate()
	allocator.release(a) or { panic(err) }
	allocator.release(b) or { panic(err) }
	allocator.check()
	assert pmm.pages.len == 1
	assert allocator.allocate() == a
	allocator.check()
}

pub fn partial_before_spare() {
	mut pmm := &PMM{}
	mut allocator := slab(pmm, 1024)
	mut objects := []u64{}
	for _ in 0 .. 7 { objects << allocator.allocate() }
	allocator.release(objects[6]) or { panic(err) }
	allocator.release(objects[1]) or { panic(err) }
	assert allocator.allocate() == objects[1]
	assert allocator.spare != 0
	allocator.check()
}

pub fn poison_and_zero() {
	mut pmm := &PMM{}
	mut allocator := slab(pmm, 64)
	a := allocator.allocate()
	keeper := allocator.allocate()
	mut page := pmm.page(a & ~(page_size - 1))
	offset := int(a % page_size)
	for i in offset .. offset + 64 { page.payload[i] = 0x13 }
	allocator.release(a) or { panic(err) }
	for i in offset .. offset + 64 {
		assert page.payload[i] == 0xaa
	}
	assert allocator.allocate() == a
	for i in offset .. offset + 64 {
		assert page.payload[i] == 0
	}
	allocator.release(a) or { panic(err) }
	allocator.release(keeper) or { panic(err) }
	allocator.check()
}

pub fn invalid_free() {
	mut allocator := slab(&PMM{}, 64)
	a := allocator.allocate()
	keeper := allocator.allocate()
	for bad in [a + 1, a - 1, a & ~(page_size - 1)] {
		allocator.release(bad) or { continue }
		assert false
	}
	allocator.release(a) or { panic(err) }
	allocator.release(a) or {
		assert err.msg() == 'double free'
		allocator.release(keeper) or { panic(err) }
		allocator.check()
		return
	}
	assert false
}

pub struct Live {
pub:
	slab    int
	address u64
}

pub fn mixed_size_churn() {
	mut rng := random(0x584e55)
	mut pmm := &PMM{}
	mut slabs := []Slab{}
	for size in classes { slabs << slab(pmm, size) }
	mut live := []Live{}
	for i in 0 .. 100000 {
		if live.len == 0 || (live.len < 2048 && rng.fraction() < 0.52) {
			index := rng.below(slabs.len)
			live << Live{index, slabs[index].allocate()}
		} else {
			index := rng.below(live.len)
			item := live[index]
			live[index] = live.last()
			live.delete_last()
			slabs[item.slab].release(item.address) or { panic(err) }
		}
		if i % 251 == 0 {
			slabs[rng.below(slabs.len)].trim()
			for allocator in slabs { allocator.check() }
		}
	}
	for i := live.len - 1; i > 0; i-- {
		j := rng.below(i + 1)
		live[i], live[j] = live[j], live[i]
	}
	for item in live { slabs[item.slab].release(item.address) or { panic(err) } }
	assert pmm.pages.len <= classes.len
	for mut allocator in slabs {
		allocator.trim()
		allocator.check()
	}
	assert pmm.pages.len == 0
	assert pmm.allocations == pmm.frees
}

pub fn arithmetic_guards(root string) ! {
	checked_product(u64(1) << 63, 2) or {
		assert checked_product(mask, 0) or { panic('zero rejected') } == 0
		assert checked_product(7, 13) or { panic('ordinary product rejected') } == 91
		maximum := (mask / page_size - 1) * page_size
		limit := big.integer_from_u64(mask)
		page := big.integer_from_u64(page_size)
		one := big.integer_from_int(1)
		for value in [u64(0), 1, 2049, maximum - 1, maximum] {
			pages := (big.integer_from_u64(value) + page - one) / page
			assert (pages + one) * page <= limit
		}
		pages := (big.integer_from_u64(maximum) + one + page - one) / page
		assert (pages + one) * page > limit
		source := os.read_file(os.join_path(root, 'kernel/memory/physical.v'))!
		assert source.contains('if b != 0 && a > u64(-1) / b')
		assert source.contains('if new_ptr == unsafe { nil }')
		assert source.count('(u64(-1) / page_size - 1) * page_size') == 2
		return
	}
	assert false, 'overflow accepted'
}

pub fn irq_snapshot(root string) ! {
	source := os.read_file(os.join_path(root, 'kernel/klock/klock_amd64.v'))!
	release := source.all_after('pub fn (mut l Lock) release() {').all_before('\n}')
	saved := release.index('ints := l.ints') or { return error('Missing IRQ snapshot') }
	store := release.index('katomic.store') or { return error('Missing unlock publication') }
	assert saved < store
	assert release.contains('cpu.interrupt_toggle(ints)')
}
