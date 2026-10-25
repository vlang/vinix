// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftClassUpdateFailure {}
fn (_ &SwiftClassUpdateFailure) msg() string { return 'iOS: unsupported Swift class layout, registration or lifetime' }
fn (_ &SwiftClassUpdateFailure) code() int { return 1 }
__global swift_class_update_failure_value = SwiftClassUpdateFailure{}
fn swift_class_update_failure() IError { return unsafe { &swift_class_update_failure_value } }

fn swift_class_assign64(address u64, value u64) {
	if read64(address) != value { unsafe { *(&u64(address)) = value } }
}
fn swift_class_assign32(address u64, value u32) {
	if read32(address) != value { write32(address, value) }
}

// Swift 5's static-vtable layout algorithm, for already registered, nongeneric
// formal root classes using SwiftObject. Initializing a root template can fill
// its implicit superclass and normalize the Swift class bit. Superclass type
// resolution, resilient/generic metadata and image registration remain separate.
// Both offset vectors and exported Objective-C offset cells are pointer-sized.
fn swift_class_layout_checked(metadata u64, algorithm u64, count u64, types u64, offsets u64, initialize bool) !SwiftAssociatedMetadata {
	if algorithm != 0x100 || count > 64 || metadata == 0 || metadata & 7 != 0
		|| metadata > ~u64(0) - 1048576 || (count != 0 && (types == 0 || types & 7 != 0
		|| types > ~u64(0) - count * 8 || offsets != metadata + 80)) {
		return swift_class_update_failure()
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_generic_metadata_retired || ios_runtime.swift_generic_value_retired {
		return swift_class_update_failure()
	}
	// Unknown pointers must fail before any borrowed class storage is read.
	mut info := ios_runtime.classes[metadata] or { return swift_class_update_failure() }
	if info.meta || info.dynamic || info.initializing || (!info.swift_layout_complete
		&& (info.initialized || info.instances != 0)) { return swift_class_update_failure() }
	meta := ios_runtime.classes[read64(metadata)] or { return swift_class_update_failure() }
	parent := ios_runtime.classes[info.parent] or { return swift_class_update_failure() }
	superclass := read64(metadata + 8)
	bits := read64(metadata + 32) & 7
	if !meta.meta || parent.meta || parent.parent != 0 || parent.size != 16
		|| parent.name != '_TtCs12_SwiftObject'
		|| (superclass != info.parent && !(initialize && !info.swift_layout_complete && superclass == 0))
		|| (bits != 2 && !(initialize && !info.swift_layout_complete && bits == 1)) || read32(metadata + 40) != 2
		|| read32(metadata + 44) != 0 { return swift_class_update_failure() }
	ro := read64(metadata + 32) & ~u64(7)
	descriptor := read64(metadata + 64)
	if ro == 0 || ro > ~u64(0) - 72 || descriptor == 0 || descriptor & 3 != 0
		|| descriptor > ~u64(0) - 44 { return swift_class_update_failure() }
	// Unique descriptors and an existing static vtable do not change field
	// layout. Older class templates reserve a third negative metadata word.
	// The updater requires a normalized class. Neither entry point invokes a
	// singleton completion callback or registers an unrecognized image class.
	address_point := u64(read32(metadata + 60))
	if read32(descriptor) & ~u32(0x80000040) != 0x10010 || read32(descriptor + 20) != 0
		|| read32(descriptor + 36) != count || (count != 0 && read32(descriptor + 40) != 10)
		|| address_point !in [u64(16), 24]! || u64(read32(descriptor + 24)) * 8 != address_point
		|| read32(metadata + 56) < address_point + 80 + count * 8 || read32(metadata + 56) > 1048576
		|| u64(read32(descriptor + 28)) * 8 + address_point != read32(metadata + 56)
		|| read32(descriptor + 32) < count || read32(descriptor + 32) > read32(descriptor + 28)
		|| read32(ro) & ~u32(0x40) != 0x80 || read32(ro + 4) < 16 || read32(ro + 4) > 1048576 {
		return swift_class_update_failure()
	}
	list := read64(ro + 48)
	if info.ivars.len != int(count) || (info.swift_ivar_list != 0 && list != info.swift_ivar_list)
		|| (list == 0 && count != 0) || (list != 0 && (list & 7 != 0
		|| list > ~u64(0) - 8 - count * 32 || read32(list) != 32 || read32(list + 4) != count)) {
		return swift_class_update_failure()
	}
	mut positions := [64]u64{}
	mut sizes := [64]u64{}
	mut alignments := [64]u32{}
	mut ivars := [64]u64{}
	mut size := u64(read32(ro + 4))
	mut mask := u64(7)
	mut copy_list := false
	for i in u64(0) .. count {
		layout := read64(types + i * 8)
		if layout == 0 || layout & 7 != 0 || layout > ~u64(0) - 24 { return swift_class_update_failure() }
		field_size := read64(layout)
		stride := read64(layout + 8)
		flags := read32(layout + 16)
		field_mask := u64(flags & 255)
		if field_size > 1048576 || stride == 0 || stride < field_size || stride & field_mask != 0
			|| (field_mask + 1) & field_mask != 0 || flags & ~u32(0x023b00ff) != 0
			|| read32(layout + 20) > 0x7fffffff { return swift_class_update_failure() }
		if field_size != 0 || read64(offsets + i * 8) != 0 {
			size = (size + field_mask) & ~field_mask
			positions[int(i)] = size
			size += field_size
			if field_mask > mask { mask = field_mask }
		}
		if size > 1048576 { return swift_class_update_failure() }
		sizes[int(i)] = field_size
		mut alignment := u32(0)
		for u64(1) << alignment < field_mask + 1 { alignment++ }
		alignments[int(i)] = alignment
		entry := list + 8 + i * 32
		cell := read64(entry)
		name := read64(entry + 8)
		if (cell != 0 && (cell & 7 != 0 || cell > ~u64(0) - 8)) || name == 0 { return swift_class_update_failure() }
		mut found := u64(0)
		for _, ivar in info.ivars {
			if C.strcmp(ivar.name.str, &char(name)) == 0 { found = u64(ivar); break }
		}
		if found == 0 { return swift_class_update_failure() }
		for j in u64(0) .. i { if ivars[int(j)] == found { return swift_class_update_failure() } }
		ivars[int(i)] = found
		if read32(entry + 28) != field_size { copy_list = true }
		if info.swift_layout_complete && (read64(offsets + i * 8) != positions[int(i)]
			|| (cell != 0 && read64(cell) != positions[int(i)]) || read32(entry + 28) != field_size) {
			return swift_class_update_failure()
		}
	}
	if info.swift_layout_complete && (read32(metadata + 48) != size || read32(metadata + 52) != mask
		|| read32(ro + 8) != size || info.size != size) { return swift_class_update_failure() }
	// Validate the entire request before any writes or publication. Swift keeps
	// the original ivar table when all sizes match, even if its type encodings
	// or alignment fields differ. Only changed-size entries lose their encoding.
	mut result_list := list
	if copy_list {
		if info.swift_ivar_list != 0 { return swift_class_update_failure() }
		result_list = u64(C.malloc(usize(8 + count * 32)))
		if result_list == 0 { return swift_class_update_failure() }
		C.memcpy(voidptr(result_list), voidptr(list), usize(8 + count * 32))
	}
	if initialize {
		swift_class_assign64(metadata + 8, info.parent)
		swift_class_assign64(metadata + 32, ro | 2)
	}
	for i in u64(0) .. count {
		entry := result_list + 8 + i * 32
		cell := read64(entry)
		swift_class_assign64(offsets + i * 8, positions[int(i)])
		if cell != 0 { swift_class_assign64(cell, positions[int(i)]) }
		mut ivar := unsafe { &ObjIvar(ivars[int(i)]) }
		ivar.offset = i64(positions[int(i)])
		ivar.size = sizes[int(i)]
		if read32(entry + 28) != sizes[int(i)] {
			swift_class_assign64(entry + 16, 0)
			write32(entry + 24, alignments[int(i)])
			write32(entry + 28, u32(sizes[int(i)]))
			unsafe { ivar.types.free() }
			ivar.types = ''
		}
	}
	swift_class_assign32(metadata + 48, u32(size))
	swift_class_assign32(metadata + 52, u32(mask))
	swift_class_assign32(ro + 8, u32(size))
	if copy_list {
		info.swift_ivar_list = result_list
		swift_class_assign64(ro + 48, result_list)
	}
	info.size = u32(size)
	info.swift_layout_complete = true
	// MetadataDependency uses x0/x1. No dependency: state is immaterial when
	// metadata is nil; return zero for both registers deterministically.
	return SwiftAssociatedMetadata{}
}

fn swift_class_update_checked(metadata u64, algorithm u64, count u64, types u64, offsets u64) !SwiftAssociatedMetadata {
	return swift_class_layout_checked(metadata, algorithm, count, types, offsets, false)
}

fn swift_class_update(metadata u64, algorithm u64, count u64, types u64, offsets u64) SwiftAssociatedMetadata {
	return swift_class_update_checked(metadata, algorithm, count, types, offsets) or { panic(err) }
}

fn swift_class_initialize_checked(metadata u64, algorithm u64, count u64, types u64, offsets u64) !SwiftAssociatedMetadata {
	return swift_class_layout_checked(metadata, algorithm, count, types, offsets, true)
}

fn swift_class_initialize(metadata u64, algorithm u64, count u64, types u64, offsets u64) SwiftAssociatedMetadata {
	return swift_class_initialize_checked(metadata, algorithm, count, types, offsets) or { panic(err) }
}
