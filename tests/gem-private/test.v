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
