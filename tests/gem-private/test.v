// SPDX-License-Identifier: GPL-2.0-or-later
import drm.gem
import memory

fn main() {
	for identity := u64(1); identity <= 200; identity++ {
		object := gem.create_aligned_private(16385, 16384, identity) or { panic('private GEM') }
		handle := object.handle
		visible := gem.get_by_handle(handle) or { panic('published GEM') }
		assert voidptr(visible) == voidptr(object)
		assert visible.vm_private_identity == identity && visible.size == 32768
		assert visible.refcount == 1 && !visible.external
		gem.ref_obj(object)
		assert object.refcount == 2
		gem.unref(object)
		assert object.refcount == 1 && memory.live() == 1
		gem.unref(object)
		assert object.refcount == 0 && memory.live() == 0
		if _ := gem.get_by_handle(handle) { panic('destroyed GEM handle retained') }
		assert memory.live() == 0
		// Normal GEM metadata currently has a separate retention policy in the
		// kernel. This isolated fixture has no borrowed pointers remaining and
		// explicitly frees that metadata; it does not change/measure that policy.
		unsafe { free(voidptr(object)) }
	}
	if _ := gem.create_aligned_private(16384, 16384, 0) { panic('zero private identity') }
	if _ := gem.create_aligned_private(~u64(0), 16384, 1) { panic('size overflow') }
	if _ := gem.create_aligned_private(0, 16384, 1) { panic('empty object') }
	assert memory.live() == 0
	memory.fail(true)
	if _ := gem.create_aligned_private(16384, 16384, 1) { panic('allocation failure ignored') }
	assert memory.live() == 0
	memory.fail(false)
	shareable := gem.create_aligned(16384, 16384) or { panic('shareable GEM') }
	assert shareable.vm_private_identity == 0 && !shareable.external
	gem.unref(shareable)
	unsafe { free(voidptr(shareable)) }
	external := gem.create_external(16384) or { panic('external GEM') }
	assert external.vm_private_identity == 0 && external.external
	// An external object has no backing until its driver installs an aperture.
	assert external.contiguous_phys() == none && external.page_phys(0) == none
	assert !external.write_bytes(0, voidptr(&external.size), 8)
	gem.unref(external) // production external-object unref also frees metadata
	assert memory.live() == 0
	check_backing_accessors()
	check_scattered_backing()
	println('GEM private construction: 200 identities visible at first handle lookup, size alignment, refcount/backing release, invalid identity/size/OOM and ordinary/external defaults passed')
}

// Every consumer reaches backing through these accessors; today an object is
// one physical run.
fn check_backing_accessors() {
	object := gem.create_aligned(3 * 16384, 16384) or { panic('accessor GEM') }
	base := object.contiguous_phys() or { panic('contiguous base') }
	assert base == object.phys_addr
	assert (object.page_phys(0) or { 0 }) == base
	assert (object.page_phys(object.size - 1) or { 0 }) == base + object.size - 1
	assert object.page_phys(object.size) == none
	phys, run := object.contiguous_run(16384, u64(1) << 40) or { panic('run') }
	assert phys == base + 16384 && run == object.size - 16384
	short_phys, short := object.contiguous_run(100, 50) or { panic('short run') }
	assert short_phys == base + 100 && short == 50
	_, empty := object.contiguous_run(0, 0) or { u64(1), u64(0) }
	_, past := object.contiguous_run(object.size, 1) or { u64(1), u64(0) }
	assert empty == 0 && past == 0
	// write_bytes copies through the object's mapping, or through the direct
	// map run by run when it has none, and refuses ranges past the end.
	data := [u8(1), 2, 3, 4]!
	assert object.write_bytes(16382, voidptr(&data[0]), 4)
	mut unmapped := *object
	unmapped.virt_addr = 0
	assert unmapped.write_bytes(object.size - 4, voidptr(&data[0]), 4)
	unsafe {
		bytes := &u8(object.virt_addr)
		assert bytes[16382] == 1 && bytes[16385] == 4
		assert bytes[object.size - 4] == 1 && bytes[object.size - 1] == 4
	}
	assert !object.write_bytes(object.size - 2, voidptr(&data[0]), 4)
	assert !object.write_bytes(object.size + 1, voidptr(&data[0]), 0)
	assert object.write_bytes(object.size, voidptr(&data[0]), 0)
	gem.unref(object)
	unsafe { free(voidptr(object)) }
	assert memory.live() == 0
	println('GEM backing accessors: page lookup, bounded runs, single-run base and direct-map writes passed')
}

// With no contiguous run long enough, an AGX object falls back to single
// pages. The accessors merge adjacent pages into runs and split at gaps.
fn check_scattered_backing() {
	page := u64(16384)
	baseline := memory.live()
	memory.limit_contiguous(1)
	object := gem.create_aligned_with_cache(5 * page, page, 0, true, false) or { panic('scattered GEM') }
	assert object.phys_addr == 0 && object.virt_addr == 0 && object.pages != unsafe { nil }
	assert object.size == 5 * page && memory.live() == baseline + 5
	// Fresh pool: object pages 0-1 and 2-3 are adjacent pairs; page 4 stands alone.
	for index in u64(0) .. 5 {
		assert (object.page_phys(index * page + 7) or { 0 }) == memory.pool_page(index) + 7
	}
	assert object.page_phys(object.size) == none
	mut phys, mut run := object.contiguous_run(0, object.size) or { panic('first run') }
	assert phys == memory.pool_page(0) && run == 2 * page
	phys, run = object.contiguous_run(2 * page, object.size) or { panic('second run') }
	assert phys == memory.pool_page(2) && run == 2 * page
	phys, run = object.contiguous_run(4 * page, u64(1) << 40) or { panic('last run') }
	assert phys == memory.pool_page(4) && run == page
	phys, run = object.contiguous_run(100, object.size) or { panic('offset run') }
	assert phys == memory.pool_page(0) + 100 && run == 2 * page - 100
	phys, run = object.contiguous_run(page + 100, 10) or { panic('short run') }
	assert phys == memory.pool_page(1) + 100 && run == 10
	assert object.contiguous_phys() == none
	// A write across the gap between runs lands in both pages.
	data := [u8(1), 2, 3, 4, 5, 6, 7, 8]!
	assert object.write_bytes(2 * page - 4, voidptr(&data[0]), 8)
	unsafe {
		assert *&u8(memory.pool_page(1) + page - 4) == 1 && *&u8(memory.pool_page(1) + page - 1) == 4
		assert *&u8(memory.pool_page(2)) == 5 && *&u8(memory.pool_page(2) + 3) == 8
	}
	assert !object.write_bytes(object.size - 4, voidptr(&data[0]), 8)
	gem.unref(object)
	assert memory.live() == baseline
	unsafe { free(voidptr(object)) }

	$if arm64 {
		// Uncached objects set the policy per page and restore every page.
		uncached := gem.create_aligned_with_cache(3 * page, page, 0, false, false) or { panic('uncached scattered GEM') }
		assert uncached.pages != unsafe { nil } && memory.uncached() == 3
		gem.unref(uncached)
		assert memory.uncached() == 0 && memory.live() == baseline
		unsafe { free(voidptr(uncached)) }
	}
	// Running out partway releases the pages already taken.
	memory.fail_single_pages_after(2)
	if _ := gem.create_aligned_with_cache(4 * page, page, 0, true, false) { panic('partial scatter published') }
	assert memory.live() == baseline && memory.uncached() == 0
	memory.fail_single_pages_after(-1)
	// Only the AGX constructor at page alignment falls back.
	if _ := gem.create_aligned(4 * page, page) { panic('ordinary GEM scattered') }
	if _ := gem.create_aligned_with_cache(4 * page, 2 * page, 0, true, false) { panic('over-aligned GEM scattered') }
	assert memory.live() == baseline
	// A contiguous run is still preferred when one is available.
	memory.limit_contiguous(0)
	contiguous := gem.create_aligned_with_cache(4 * page, page, 0, true, false) or { panic('contiguous GEM') }
	assert contiguous.pages == unsafe { nil } && contiguous.phys_addr != 0
	assert (contiguous.contiguous_phys() or { 0 }) == contiguous.phys_addr
	gem.unref(contiguous)
	unsafe { free(voidptr(contiguous)) }
	assert memory.live() == baseline
	println('GEM scattered backing: single-page fallback, merged and split runs, writes across gaps, per-page cache policy and partial-failure release passed')
}
