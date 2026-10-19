// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn swiftui_text_storage_retain(first u64, second u64, tag u8) {
	if tag == 0 { swift_bridge_retain(second) }
	else if tag == 1 { swift_retain(first) }
	else { panic('iOS: invalid SwiftUI Text storage tag') }
}
fn swiftui_text_storage_release(first u64, second u64, tag u8) {
	if tag == 0 { swift_bridge_release(second) }
	else if tag == 1 { swift_release(first) }
	else { panic('iOS: invalid SwiftUI Text storage tag') }
}
fn swiftui_text_value_copy(destination u64, source u64, _metadata u64) u64 {
	first := read64(source); second := read64(source + 8); tag := unsafe { *(&u8(source + 16)) }
	swiftui_text_storage_retain(first, second, tag)
	unsafe { *(&u64(destination)) = first; *(&u64(destination + 8)) = second; *(&u8(destination + 16)) = tag }
	swift_array_copy(destination + 24, source + 24, 0)
	return destination
}
fn swiftui_text_value_destroy(value u64, _metadata u64) {
	swiftui_text_storage_release(read64(value), read64(value + 8), unsafe { *(&u8(value + 16)) })
	swift_array_destroy(value + 24, 0)
}
fn swiftui_text_value_assign(destination u64, source u64, taking bool) u64 {
	if destination == source { return destination }
	first := read64(source); second := read64(source + 8); tag := unsafe { *(&u8(source + 16)) }
	previous_first := read64(destination); previous_second := read64(destination + 8); previous_tag := unsafe { *(&u8(destination + 16)) }
	if !taking { swiftui_text_storage_retain(first, second, tag) }
	unsafe { *(&u64(destination)) = first; *(&u64(destination + 8)) = second; *(&u8(destination + 16)) = tag }
	swiftui_text_storage_release(previous_first, previous_second, previous_tag)
	if taking { swift_array_assign_take(destination + 24, source + 24, 0) }
	else { swift_array_assign_copy(destination + 24, source + 24, 0) }
	return destination
}
fn swiftui_text_value_assign_copy(destination u64, source u64, _metadata u64) u64 { return swiftui_text_value_assign(destination, source, false) }
fn swiftui_text_value_assign_take(destination u64, source u64, _metadata u64) u64 { return swiftui_text_value_assign(destination, source, true) }
fn swiftui_text_value_take(destination u64, source u64, _metadata u64) u64 {
	C.memmove(voidptr(destination), voidptr(source), 32)
	return destination
}
fn swiftui_text_enum_get(value u64, empty_cases u32, _metadata u64) u32 {
	if empty_cases == 0 { return 0 }
	if empty_cases > 0x7fffffff && unsafe { *(&u8(value + 32)) } != 0 { mut index:=u32(0);C.memcpy(unsafe { &index },voidptr(value),4);return index + u32(0x80000000) }
	mut owner := u64(0);C.memcpy(unsafe { &owner },voidptr(value+24),8)
	return if owner >> 32 == 0 { u32(owner) + u32(1) } else { u32(0) }
}
fn swiftui_text_enum_store(value u64, which_case u32, empty_cases u32, _metadata u64) {
	if empty_cases > 0x7fffffff { unsafe { *(&u8(value + 32)) = if which_case > 0x7fffffff { u8(1) } else { u8(0) } } }
	if which_case == 0 { return }
	if which_case <= 0x7fffffff { owner:=u64(which_case-1);C.memcpy(voidptr(value+24),unsafe { &owner },8) }
	else { index:=which_case-u32(0x80000000);C.memset(voidptr(value),0,32);C.memcpy(voidptr(value),unsafe { &index },4) }
}
fn swiftui_text_metadata() u64 {
	base := swiftui_text_view_arena_checked() or { panic(err) }
	return base + u64(C.getpagesize()) + 512
}
fn swiftui_text_box_allocate() u64 { return swift_heap_allocate(swiftui_text_metadata() + 176, 48, 7) }
fn swiftui_text_box_destroy(owner u64) {
	swiftui_text_value_destroy(owner + 16, 0)
	swift_heap_deallocate(owner, 48, 7)
}
fn swiftui_text_buffer_copy_checked(destination u64, source u64, metadata u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swiftui_text_view_retired || destination == 0 || source == 0
		|| destination & 7 != 0 || source & 7 != 0 || metadata != swiftui_text_metadata() { return swift_any_failure() }
	owner := read64(source)
	swift_any_box_checked(owner, metadata, 32)!
	swift_retain(owner)
	unsafe { *(&u64(destination)) = owner }
	return owner + 16
}
fn swiftui_text_buffer_copy(destination u64, source u64, metadata u64) u64 {
	return swiftui_text_buffer_copy_checked(destination, source, metadata) or { panic(err) }
}
fn swiftui_text_metadata_emit(code u64, data u64) {
	metadata := data + 512; witness := data + 560
	write32(code + 64, 0x58000080); write32(code + 68, 0xd2800001); write32(code + 72, 0xd65f03c0)
	unsafe {
		*(&u64(code + 80)) = metadata
		*(&u64(metadata - 8)) = witness
		*(&u64(metadata)) = 0x200; *(&u64(metadata + 8)) = data
	}
	// The struct's two field offsets are 32-bit words, at metadata word two.
	write32(metadata + 20, 24)
	for i, target in [u64(unsafe { voidptr(swiftui_text_buffer_copy) }), u64(unsafe { voidptr(swiftui_text_value_destroy) }),
		u64(unsafe { voidptr(swiftui_text_value_copy) }), u64(unsafe { voidptr(swiftui_text_value_assign_copy) }),
		u64(unsafe { voidptr(swiftui_text_value_take) }), u64(unsafe { voidptr(swiftui_text_value_assign_take) }),
		u64(unsafe { voidptr(swiftui_text_enum_get) }), u64(unsafe { voidptr(swiftui_text_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = target } }
	unsafe { *(&u64(witness + 64)) = 32; *(&u64(witness + 72)) = 32 }
	write32(witness + 80, 0x02030007); write32(witness + 84, 0x7fffffff)
	// Registered non-inline value box; the destructor receives Self in x20.
	unsafe { *(&u64(data + 672)) = code + 96; *(&u64(data + 688)) = 0x400; *(&u64(data + 696)) = metadata }
	write32(code + 96, 0xaa1403e0); write32(code + 100, 0x58000070); write32(code + 104, 0xd61f0200)
	unsafe { *(&u64(code + 112)) = u64(voidptr(swiftui_text_box_destroy)) }
}
