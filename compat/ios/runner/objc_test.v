// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho

fn test_objc_arc_pool_and_strong_replacement() {
	objc_start()
	defer { objc_stop() }
	pool := objc_pool_push()
	first := objc_autorelease(objc_allocate(ios_runtime.names['NSObject']))
	second := objc_autorelease(objc_allocate(ios_runtime.names['NSObject']))
	mut strong := u64(0)
	objc_store_strong(&strong, first)
	objc_store_strong(&strong, second)
	assert ios_runtime.live == 2
	objc_pool_pop(pool)
	assert ios_runtime.live == 1
	assert strong == second
	objc_store_strong(&strong, 0)
	assert ios_runtime.live == 0
}

fn test_objc_nil_returns_integer_and_hfa_zero() {
	objc_start()
	defer { objc_stop() }
	mut frame := RegisterFrame{}
	frame.x[1] = u64(c'bounds')
	for i in 0 .. frame.q.len { frame.q[i] = ~u64(0) }
	assert objc_dispatch(mut frame, 0) == 0
	assert frame.x[0] == 0
	assert frame.x[1] == 0
	for i in 0 .. 8 {
		assert frame.q[i] == 0
	}
}

fn test_objc_metadata_rejects_ranges_and_invalid_method_lists() {
	mut data := []u8{len: 256}
	base := u64(data.data)
	m := ObjMetadata{
		image:  macho.Image{ segments: [macho.Segment{ name: '__DATA', address: 0x1000, filesize: 256, size: 256, prot: 3 }] }
		layout: macho.Layout{ base: 0x1000, size: 256 }
		base:   base
	}
	m.range(base, 256, true) or { assert false }
	m.range(base + 255, 2, false) or {
		assert err.msg().contains('outside')
		return
	}
	assert false
}

fn test_objc_method_list_count_and_format_rejected() {
	mut data := []u8{len: 256}
	base := u64(data.data)
	m := ObjMetadata{
		image:  macho.Image{ segments: [macho.Segment{ name: '__DATA', address: 0x1000, filesize: 256, size: 256, prot: 3 }] }
		layout: macho.Layout{ base: 0x1000, size: 256 }
		base:   base
	}
	write32(base, 24)
	write32(base + 4, 5000)
	m.methods(base) or {
		assert err.msg().contains('method list')
		return
	}
	assert false
}
