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
	gem.unref(external) // production external-object unref also frees metadata
	assert memory.live() == 0
	println('GEM private construction: 200 identities visible at first handle lookup, size alignment, refcount/backing release, invalid identity/size/OOM and ordinary/external defaults passed')
}
