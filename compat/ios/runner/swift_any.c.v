// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftAnyFailure {}
fn (_ &SwiftAnyFailure) msg() string { return 'iOS: unsupported or invalid Swift Any value layout' }
fn (_ &SwiftAnyFailure) code() int { return 1 }
__global swift_any_failure_value = SwiftAnyFailure{}
fn swift_any_failure() IError { return unsafe { &swift_any_failure_value } }
struct SwiftAnyLayout { metadata u64 witness u64 size u64 boxed bool owner u64 }
type SwiftAnyCopyCall = fn (u64,u64,u64) u64
type SwiftAnyDestroyCall = fn (u64,u64)

fn swift_any_full_metadata() u64 { return swift_error_metadata_arena() + u64(C.getpagesize()) + 448 }
fn swift_any_box_metadata_checked(metadata u64) !u64 {
	full := swift_any_full_metadata()
	if metadata == full + 8 { return full + 176 }
	if (swift_collection_kind_checked(metadata,false) or { -1 }) == 1 { return metadata - 8 + 896 }
	if (swift_collection_kind_checked(metadata,true) or { -1 }) == 1 { return metadata - 168 + 928 }
	return swift_any_failure()
}
fn swift_any_box_checked(owner u64,metadata u64,size u64) ! {
	if owner == 0 || owner & 7 != 0 { return swift_any_failure() }
	box_metadata := swift_any_box_metadata_checked(metadata)!
	C.ios_objc_initialize_lock()
	storage := ios_runtime.swift_heap[owner] or { C.ios_objc_initialize_unlock();return swift_any_failure() }
	valid := !storage.deiniting && storage.metadata == box_metadata && storage.size == size + 16
		&& storage.mask == 7 && read64(owner) == box_metadata
	C.ios_objc_initialize_unlock()
	if !valid { return swift_any_failure() }
}
// Records/code and initialized 32-byte containers are borrowed caller-owned
// spans. Box provenance comes from existing canonical storage factories.
fn swift_any_layout(value u64) !SwiftAnyLayout {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || value == 0
		|| value & 7 != 0 || value > ~u64(0) - 32 { return swift_any_failure() }
	metadata := read64(value + 24)
	if metadata < 8 || metadata & 7 != 0 { return swift_any_failure() }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 88 { return swift_any_failure() }
	size := read64(witness + 64);stride := read64(witness + 72);flags := read32(witness + 80)
	alignment := u64(flags & 255) + 1;boxed := flags & 0x20000 != 0
	if size > 65536 || stride == 0 || stride < size || alignment > 8 || alignment & (alignment - 1) != 0
		|| stride & (alignment - 1) != 0 || flags & 0x00400000 != 0 || (!boxed && size > 24) { return swift_any_failure() }
	owner := if boxed { read64(value) } else { u64(0) }
	if boxed { swift_any_box_checked(owner,metadata,size)! }
	return SwiftAnyLayout{metadata,witness,size,boxed,owner}
}
fn swift_any_required(layout SwiftAnyLayout,slot u64) !u64 {
	entry := read64(layout.witness + slot * 8)
	if entry == 0 || entry & 3 != 0 { return swift_any_failure() }
	return entry
}
fn swift_any_copy_checked(destination u64,source u64) !u64 {
	if destination == 0 || destination & 7 != 0 || destination > ~u64(0) - 32 { return swift_any_failure() }
	layout := swift_any_layout(source)!
	entry := if layout.boxed { u64(0) } else { swift_any_required(layout,2)! }
	unsafe { *(&u64(destination + 24)) = layout.metadata }
	if layout.boxed {
		unsafe { *(&u64(destination)) = layout.owner };swift_retain(layout.owner)
	} else { call := unsafe { SwiftAnyCopyCall(voidptr(entry)) };call(destination,source,layout.metadata) }
	return destination
}
fn swift_any_copy(destination u64,source u64,_metadata u64) u64 { return swift_any_copy_checked(destination,source) or { panic(err) } }
fn swift_any_destroy_checked(value u64) ! {
	layout := swift_any_layout(value)!
	if layout.boxed { swift_release(layout.owner) }
	else { entry := swift_any_required(layout,1)!;call := unsafe { SwiftAnyDestroyCall(voidptr(entry)) };call(value,layout.metadata) }
}
fn swift_any_destroy(value u64,_metadata u64) { swift_any_destroy_checked(value) or { panic(err) } }
fn swift_any_take(destination u64,source u64,_metadata u64) u64 {
	// Native initializeWithTake transfers all32 bytes without reading metadata
	// or calling contained witnesses. The source becomes uninitialized.
	C.memmove(unsafe { voidptr(destination) },unsafe { voidptr(source) },32);return destination
}
fn swift_any_assign_checked(destination u64,source u64,taking bool) !u64 {
	if destination == source { return destination } // Native self assignment reads nothing.
	old := swift_any_layout(destination)!;next := swift_any_layout(source)!
	if old.metadata == next.metadata {
		if next.boxed {
			unsafe { *(&u64(destination)) = next.owner }
			if !taking { swift_retain(next.owner) };swift_release(old.owner)
		} else {
			entry := swift_any_required(next,if taking { u64(5) } else { u64(3) })!
			call := unsafe { SwiftAnyCopyCall(voidptr(entry)) };call(destination,source,next.metadata)
		}
		return destination
	}
	// Validate every needed entry before moving the old value or publishing.
	new_entry := if next.boxed { u64(0) } else { swift_any_required(next,if taking { u64(4) } else { u64(2) })! }
	old_take := if old.boxed { u64(0) } else { swift_any_required(old,4)! }
	old_destroy := if old.boxed { u64(0) } else { swift_any_required(old,1)! }
	temporary := u64(C.__builtin_alloca(24))
	if !old.boxed { move_old := unsafe { SwiftAnyCopyCall(voidptr(old_take)) };move_old(temporary,destination,old.metadata) }
	unsafe { *(&u64(destination + 24)) = next.metadata }
	if next.boxed {
		unsafe { *(&u64(destination)) = next.owner };if !taking { swift_retain(next.owner) }
	} else { construct := unsafe { SwiftAnyCopyCall(voidptr(new_entry)) };construct(destination,source,next.metadata) }
	if old.boxed { swift_release(old.owner) }
	else { destroy_old := unsafe { SwiftAnyDestroyCall(voidptr(old_destroy)) };destroy_old(temporary,old.metadata) }
	return destination
}
fn swift_any_assign_copy(destination u64,source u64,_metadata u64) u64 { return swift_any_assign_checked(destination,source,false) or { panic(err) } }
fn swift_any_assign_take(destination u64,source u64,_metadata u64) u64 { return swift_any_assign_checked(destination,source,true) or { panic(err) } }
fn swift_any_buffer_copy_checked(destination u64,source u64,metadata u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || destination == 0 || source == 0
		|| destination & 7 != 0 || source & 7 != 0 || metadata != swift_any_full_metadata() + 8 { return swift_any_failure() }
	owner := read64(source);swift_any_box_checked(owner,metadata,32)!
	unsafe { *(&u64(destination)) = owner };swift_retain(owner);return owner + 16
}
fn swift_any_buffer_copy(destination u64,source u64,metadata u64) u64 { return swift_any_buffer_copy_checked(destination,source,metadata) or { panic(err) } }
fn swift_any_box_allocate() u64 { return swift_heap_allocate(swift_any_full_metadata() + 176,48,7) }
fn swift_any_box_destroy(owner u64) {
	swift_any_destroy(owner + 16,swift_any_full_metadata() + 8);swift_heap_deallocate(owner,48,7)
}
fn swift_any_enum_get(value u64,cases u32,_metadata u64) u32 {
	if cases & 0x80000000 != 0 && unsafe { *(&u8(value + 32)) } != 0 {
		mut bits := u32(0);for i in 0 .. 4 { bits |= u32(unsafe { *(&u8(value + u64(i))) }) << (i * 8) };return bits ^ u32(0x80000000)
	}
	mut metadata := u64(0);for i in 0 .. 8 { metadata |= u64(unsafe { *(&u8(value + 24 + u64(i))) }) << (i * 8) }
	return if metadata >> 32 == 0 { u32(metadata) + u32(1) } else { u32(0) }
}
fn swift_any_enum_store(value u64,which u32,cases u32,_metadata u64) {
	if cases & 0x80000000 != 0 { unsafe { *(&u8(value + 32)) = if which & 0x80000000 != 0 { u8(1) } else { u8(0) } } }
	if which == 0 { return }
	if which & 0x80000000 != 0 {
		bits := which & u32(0x7fffffff)
		for i in 0 .. 32 { unsafe { *(&u8(value + u64(i))) = if i < 4 { u8(bits >> (i * 8)) } else { u8(0) } } }
	} else { bits := u64(which - u32(1));for i in 0 .. 8 { unsafe { *(&u8(value + 24 + u64(i))) = u8(bits >> (i * 8)) } } }
}
fn swift_any_emit(code u64,data u64) {
	full := data + 448;witness := data + 512
	unsafe { *(&u64(full)) = witness;*(&u64(full + 8)) = 0x303;*(&u64(full + 16)) = 0x80000000 }
	for i,entry in [u64(unsafe { voidptr(swift_any_buffer_copy) }),u64(unsafe { voidptr(swift_any_destroy) }),
		u64(unsafe { voidptr(swift_any_copy) }),u64(unsafe { voidptr(swift_any_assign_copy) }),
		u64(unsafe { voidptr(swift_any_take) }),u64(unsafe { voidptr(swift_any_assign_take) }),
		u64(unsafe { voidptr(swift_any_enum_get) }),u64(unsafe { voidptr(swift_any_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = entry } }
	unsafe { *(&u64(witness + 64)) = 32;*(&u64(witness + 72)) = 32 }
	write32(witness + 80,0x30007);write32(witness + 84,0x7fffffff)
	// Private registered value box; existing heap ARC invokes its destructor
	// with owner in x20, then checks that the callback deallocated the object.
	unsafe { *(&u64(data + 608)) = code + 128;*(&u64(data + 624)) = 0x400;*(&u64(data + 632)) = full + 8 }
	write32(code + 128,0xaa1403e0);write32(code + 132,0x58000070)
	write32(code + 136,0xd61f0200);write32(code + 140,0xd503201f)
	unsafe { *(&u64(code + 144)) = u64(voidptr(swift_any_box_destroy)) }
}
