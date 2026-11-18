import aarch64.cpu
import drm
import drm.gem
import gpu.agx.bo
import memory

fn count_kind(kind string) int {
	mut count := 0
	for i in 0 .. cpu.count() { if cpu.at(i).kind == kind { count++ } }
	return count
}

fn check_bbm(pages int, clean bool) {
	assert count_kind('tlbi') == pages
	mut last_clean := -1
	mut first_tlbi := -1
	for i in 0 .. cpu.count() {
		event := cpu.at(i)
		if event.kind == 'civac' {
			last_clean = i
			assert event.pte & (u64(7) << 2) == 0, 'clean must precede NC descriptors'
		}
		if event.kind != 'tlbi' { continue }
		if first_tlbi < 0 { first_tlbi = i }
		assert event.pte == 0, 'BBM must remove the old descriptor before invalidation'
		assert cpu.at(i - 1).kind == 'dsb_ishst' && cpu.at(i - 1).pte == 0
		assert cpu.at(i + 1).kind == 'dsb_ish' && cpu.at(i + 1).pte == 0
		assert cpu.at(i + 2).kind == 'isb' && cpu.at(i + 2).pte == 0
		assert cpu.at(i + 3).kind == 'dsb_ishst' && cpu.at(i + 3).pte != 0
		assert cpu.at(i + 4).kind == 'isb' && cpu.at(i + 4).pte != 0
	}
	if clean { assert last_clean >= 0 && last_clean < first_tlbi && cpu.at(last_clean + 1).kind == 'dsb_sy' }
	else { assert last_clean == -1 }
}

fn check_cache_lines() int {
	mut cases := 0
	for log_words in [u64(3), 4, 5, 6, 7] {
		line := u64(4) << log_words
		cpu.set_ctr(log_words << 16)
		for address in [u64(0), 1, line - 1, line, line + 1, ~u64(0) - 511] {
			for length in [u64(0), 1, 31, 32, 127, 128, 255, 511] {
				cpu.reset()
				cpu.clean_invalidate_data_cache_to_poc(address, length)
				if length == 0 { assert cpu.count() == 0; cases++; continue }
				first := address / line * line
				count := int((address - first + length + line - 1) / line)
				assert cpu.count() == count + 2 && cpu.at(0).kind == 'dsb_sy' && cpu.at(cpu.count() - 1).kind == 'dsb_sy'
				for i in 0 .. count { assert cpu.at(i + 1).kind == 'civac' && cpu.at(i + 1).address == first + u64(i) * line }
				cases++
			}
		}
	}
	return cases
}

fn check_constructors() int {
	mut cases := 0
	for _ in 0 .. 20 {
		for writeback in [false, true] {
			for identity in [u64(0), 17] {
				for size in [u64(1), 16384, 16385, 49152] {
					memory.prepare()
					object := gem.create_aligned_with_cache(size, 16384, identity, writeback) or { panic('GEM create') }
					assert object.size == (size + 16383) & ~u64(16383)
					assert object.vm_private_identity == identity
					assert object.pte_extra == if writeback { u64(0) } else { memory.pte_uncached }
					assert drm.prime_cache_attributes(object) == object.pte_extra
					assert memory.live() == 1 && !memory.locked()
					for i in 0 .. int(object.size / 4096) {
						pte := memory.leaf_pte(i)
						assert pte & (u64(7) << 2) == if writeback { u64(0) } else { u64(2) << 2 }
						assert pte & (u64(3) << 8) == if writeback { u64(3) << 8 } else { u64(2) << 8 }
						assert pte & ((u64(1) << 10) | (u64(1) << 53) | (u64(1) << 54)) == (u64(1) << 10) | (u64(1) << 53) | (u64(1) << 54)
					}
					if !writeback {
						assert count_kind('civac') == int(object.size / 128)
						check_bbm(int(object.size / 4096), true)
					} else { assert cpu.count() == 0 }
					gem.ref_obj(object)
					cpu.reset(); gem.unref(object)
					assert cpu.count() == 0 && memory.live() == 1
					handle := object.handle
					gem.unref(object)
					assert memory.live() == 0 && !memory.locked()
					assert cpu.at(cpu.count() - 1).kind == 'pmm_free'
					if !writeback { check_bbm(int(object.size / 4096), false) }
					if _ := gem.get_by_handle(handle) { assert false }
					cases++
				}
			}
		}
	}
	return cases
}

fn check_refusal_and_original_policy() int {
	mut cases := 0
	memory.prepare()
	for size in [u64(0), ~u64(0)] {
		if _ := gem.create_aligned_with_cache(size, 16384, 0, false) { assert false }
		assert memory.live() == 0 && cpu.count() == 0
		cases++
	}
	memory.fail_allocations(true)
	metadata_before := memory.metadata_frees()
	if _ := gem.create_aligned_with_cache(16384, 16384, 0, false) { assert false }
	memory.fail_allocations(false)
	assert memory.live() == 0 && cpu.count() == 0 && memory.metadata_frees() == metadata_before + 1
	cases++
	for missing in 0 .. 8 {
		memory.prepare(); memory.fail_new_mapping(missing)
		before := memory.metadata_frees()
		if _ := gem.create_aligned_with_cache(32768, 16384, 0, false) { assert false }
		assert memory.metadata_frees() == before + 1
		assert memory.live() == 0 && count_kind('civac') == 0 && count_kind('tlbi') == 0 && !memory.locked()
		cases++
	}
	for ordinary in [false, true] {
		memory.prepare()
		object := if ordinary { gem.create_aligned_private(16384, 16384, 27) or { panic('private') } }
			else { gem.create_aligned(16384, 16384) or { panic('ordinary') } }
		assert object.pte_extra == 0 && cpu.count() == 0
		gem.unref(object)
		assert memory.live() == 0 && count_kind('tlbi') == 0
		cases++
	}
	memory.prepare()
	mut external := gem.create_external(16384) or { panic('external') }
	external.phys_addr = 0x100000
	external.pte_extra = memory.pte_uncached
	before_free := memory.frees()
	gem.unref(external)
	assert cpu.count() == 0 && memory.frees() == before_free && memory.live() == 0
	cases++
	// Transition refusal itself must not change any valid neighboring leaf.
	memory.prepare()
	physical := memory.pmm_alloc_aligned_fallible(2, 1)
	original := memory.leaf_pte(3)
	for broken in [original & ~u64(3), original | (u64(1) << 7), original | (u64(1) << 2), original ^ u64(0x1000)] {
		memory.set_leaf(3, broken); cpu.reset()
		assert !memory.set_ram_direct_map_uncached(u64(physical), 32768, true)
		assert cpu.count() == 0 && memory.leaf_pte(3) == broken && !memory.locked()
		memory.set_leaf(3, original); cases++
	}
	cpu.set_root(0x5000)
	assert !memory.set_ram_direct_map_uncached(u64(physical), 32768, true) && cpu.count() == 0
	cpu.set_root(0x4000); cases++
	memory.initialized(false)
	assert !memory.set_ram_direct_map_uncached(u64(physical), 32768, true) && cpu.count() == 0
	memory.initialized(true); cases++
	for span in [[u64(0), 0]!, [u64(1), 4096]!, [u64(0), 1]!, [~u64(0) - 4095, 8192]!] {
		assert !memory.set_ram_direct_map_uncached(span[0], span[1], true) && cpu.count() == 0
		cases++
	}
	memory.pmm_free(physical, 2)
	return cases
}

fn check_metadata_refusal() int {
	memory.prepare()
	first := gem.create_aligned_with_cache(16384, 16384, 0, true) or { panic('sentinel GEM') }
	expected_handle := first.handle + 1
	expected_offset := first.mmap_offset + first.size
	before := memory.backing_attempts()
	memory.fail_metadata(true)
	for _ in 0 .. 100 {
		for writeback in [false, true] {
			if _ := gem.create_aligned_with_cache(16384, 16384, 17, writeback) {
				panic('metadata OOM must refuse GEM creation')
			}
		}
		if _ := gem.create_external(16384) { panic('metadata OOM must refuse external GEM creation') }
		assert memory.backing_attempts() == before && memory.live() == 1 && cpu.count() == 0
		if _ := gem.get_by_handle(expected_handle) { panic('failed constructor published a handle') }
		visible := gem.get_by_handle(first.handle) or { panic('existing handle disappeared') }
		assert voidptr(visible) == voidptr(first) && first.refcount == 1
	}
	memory.fail_metadata(false)
	retry := gem.create_aligned_with_cache(16384, 16384, 17, false) or { panic('GEM retry') }
	assert retry.handle == expected_handle && retry.mmap_offset == expected_offset
	gem.unref(retry)
	gem.unref(first)
	assert memory.live() == 0
	// The host fixture owns all pointers and can release retained metadata.
	unsafe {
		free(voidptr(retry))
		free(voidptr(first))
	}
	return 300
}

fn check_authorized_aliases() {
	for reversed in [false, true] {
		memory.prepare()
		first := gem.create_aligned_with_cache(16384, 16384, 0, reversed) or { panic('first') }
		second := gem.create_aligned_with_cache(16384, 16384, 0, !reversed) or { panic('second') }
		mut table := bo.Table{}
		table.add_created(first); table.add_created(second)
		a := gem.create_mmap_offset(first); b := gem.create_mmap_offset(second)
		assert b == a + first.size && !table.valid_mmap_range(a, first.size)
		_ = table.authorize_mmap(first.handle) or { panic('authorize first') }
		_ = table.authorize_mmap(second.handle) or { panic('authorize second') }
		assert table.mmap_attributes(a) == first.pte_extra && table.mmap_attributes(b) == second.pte_extra
		assert table.valid_mmap_range(a, first.size) && table.valid_mmap_range(b, second.size)
		assert !table.valid_mmap_range(a, first.size + 16384) && !table.valid_mmap_range(a + 16383, 2)
		assert table.mmap_page(a / 16384) == voidptr(first.phys_addr)
		assert table.mmap_page(b / 16384) == voidptr(second.phys_addr)
		removed := table.remove(first.handle) or { panic('close handle') }
		cpu.reset(); gem.unref(removed)
		assert memory.live() == 2 && cpu.count() == 0 && first.refcount == 1
		table.release_all()
		assert memory.live() == 0
	}
}

fn main() {
	lines := check_cache_lines()
	constructors := check_constructors()
	refusals := check_refusal_and_original_policy()
	metadata := check_metadata_refusal()
	check_authorized_aliases()
	println('AGX CPU cache: ${lines} cache-line cases, ${constructors} real GEM constructors/final releases, ${refusals} refusal/default-policy cases; actual retag/BBM/cache-loop bodies, full-span validation, WB/NC aliases, PRIME policy, clean-before-retype, TLBI ordering, authorization, retained references and WB-before-PMM reuse passed')
	println('AGX GEM metadata: ${metadata} injected failures preserve backing, cache state, handle and mmap offset. Backing and retag failures free unpublished metadata.')
}
