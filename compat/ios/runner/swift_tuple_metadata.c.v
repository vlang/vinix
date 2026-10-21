// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftTupleMetadataFailure {}
fn (_ &SwiftTupleMetadataFailure) msg() string { return 'iOS: unsupported Swift tuple metadata layout, witnesses or lifetime' }
fn (_ &SwiftTupleMetadataFailure) code() int { return 1 }
__global swift_tuple_metadata_failure_value = SwiftTupleMetadataFailure{}
fn swift_tuple_metadata_failure() IError { return unsafe { &swift_tuple_metadata_failure_value } }

// The accepted tuples fit the three-word, eight-aligned Swift value buffer.
// Metadata, child VWTs and callback code remain immutable until quiescent stop.
// POD copies include padding; non-POD operations visit fields in source order.
fn swift_tuple_copy(destination u64, source u64, metadata u64, slot u64) u64 {
	witness := read64(metadata - 8)
	if read32(witness + 80) & 0x10000 == 0 {
		size := read64(witness + 64)
		if size != 0 { C.memcpy(voidptr(destination),voidptr(source),usize(size)) }
		return destination
	}
	for i in u64(0)..read64(metadata + 8) {
		child := read64(metadata + 24 + i * 16); offset := read64(metadata + 32 + i * 16)
		operation := unsafe { SwiftDynamicCastCopy(voidptr(read64(read64(child - 8) + slot * 8))) }
		operation(destination + offset,source + offset,child)
	}
	return destination
}
fn swift_tuple_initialize(destination u64, source u64, metadata u64) u64 { return swift_tuple_copy(destination,source,metadata,2) }
fn swift_tuple_assign(destination u64, source u64, metadata u64) u64 { return swift_tuple_copy(destination,source,metadata,3) }
fn swift_tuple_take(destination u64, source u64, metadata u64) u64 { return swift_tuple_copy(destination,source,metadata,4) }
fn swift_tuple_assign_take(destination u64, source u64, metadata u64) u64 { return swift_tuple_copy(destination,source,metadata,5) }
fn swift_tuple_destroy(value u64, metadata u64) {
	if read32(read64(metadata - 8) + 80) & 0x10000 == 0 { return }
	for i in u64(0)..read64(metadata + 8) {
		child := read64(metadata + 24 + i * 16); offset := read64(metadata + 32 + i * 16)
		operation := unsafe { SwiftDynamicCastDestroy(voidptr(read64(read64(child - 8) + 8))) }
		operation(value + offset,child)
	}
}
fn swift_tuple_extra_element(metadata u64) u64 {
	// The largest extra-inhabitant count wins; equal counts keep the first.
	mut best := u32(0); mut element := u64(0)
	for i in u64(0)..read64(metadata + 8) {
		at := metadata + 24 + i * 16; extra := read32(read64(read64(at) - 8) + 84)
		if extra > best { best = extra; element = at }
	}
	return element
}
fn swift_tuple_enum_get(value u64, cases u32, metadata u64) u32 {
	witness := read64(metadata - 8); size := read64(witness + 64); extra := read32(witness + 84)
	width := swift_optional_extra_width(size,extra,cases)
	tag := swift_enum_case_multi_read(value + size,width)
	if tag != 0 {
		high := if size < 4 { (tag - u32(1)) << u32(size * 8) } else { u32(0) }
		return (high | swift_enum_case_multi_read(value,size)) + extra + u32(1)
	}
	if extra == 0 { return 0 }
	element := swift_tuple_extra_element(metadata); child := read64(element)
	get := unsafe { SwiftSequenceTag(voidptr(read64(read64(child - 8) + 48))) }
	return get(value + read64(element + 8),extra,child)
}
fn swift_tuple_enum_store(value u64, which u32, cases u32, metadata u64) {
	witness := read64(metadata - 8); size := read64(witness + 64); extra := read32(witness + 84)
	width := swift_optional_extra_width(size,extra,cases)
	mut external := u32(0)
	if which > extra {
		bits := which - extra - u32(1)
		if size != 0 { C.memset(voidptr(value),0,usize(size)) }
		for i in u64(0)..if size < 4 { size } else { u64(4) } { unsafe { *(&u8(value + i)) = u8(bits >> u32(i * 8)) } }
		external = if size < 4 { (bits >> u32(size * 8)) + u32(1) } else { u32(1) }
	}
	for i in u32(0)..width { unsafe { *(&u8(value + size + i)) = u8(external >> (i * 8)) } }
	if which != 0 && which <= extra {
		element := swift_tuple_extra_element(metadata); child := read64(element)
		store := unsafe { SwiftOptionalStore(voidptr(read64(read64(child - 8) + 56))) }
		store(value + read64(element + 8),which,extra,child)
	}
}

fn swift_tuple_metadata_complete_locked(metadata u64) bool {
	if ios_runtime.swift_tuple_metadata_retired { return false }
	for i in u64(0)..ios_runtime.swift_tuple_metadata_count { if ios_runtime.swift_tuple_metadata_pages[i] + 8 == metadata { return true } }
	return false
}

// SwiftCC x0=request, x1=flags, x2=ordered elements, x3=labels, x4=VWT;
// x0/x1 return the canonical metadata and Complete state. No indirect result.
// Bounds: 64 unlabelled elements, inline copyable/bitwise-takable values,
// complete children, no proposed witnesses, 64 canonical tuples per lifetime.
fn swift_tuple_metadata_checked(request u64, flags u64, elements u64, labels u64, proposed u64) !SwiftAssociatedMetadata {
	state := request & ~u64(0x100)
	if request > 0x1ff || state !in [u64(0),1,0x3f,0xff]! || flags > 64 { return swift_tuple_metadata_failure() }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || ios_runtime.swift_generic_value_retired
		|| ios_runtime.swift_tuple_metadata_retired { return swift_tuple_metadata_failure() }
	// Native Void ignores element, label and proposed-witness addresses.
	if flags == 0 { return SwiftAssociatedMetadata{metadata:swift_void_full_metadata() + 8} }
	if labels != 0 || proposed != 0 || elements == 0 || elements & 7 != 0 || elements > ~u64(0) - flags * 8 { return swift_tuple_metadata_failure() }
	for i in u64(0)..ios_runtime.swift_tuple_metadata_count {
		metadata := ios_runtime.swift_tuple_metadata_pages[i] + 8
		if read64(metadata + 8) != flags { continue }
		mut same := true
		for j in u64(0)..flags { if read64(metadata + 24 + j * 16) != read64(elements + j * 8) { same = false; break } }
		if same { return SwiftAssociatedMetadata{metadata:metadata} }
	}
	if ios_runtime.swift_tuple_metadata_count == 64 { return swift_tuple_metadata_failure() }
	mut offsets := [64]u64{}; mut size := u64(0); mut mask := u64(0); mut pod := true; mut extra := u32(0)
	for i in u64(0)..flags {
		child := read64(elements + i * 8)
		swift_metadata_state_checked(0,child)!
		layout := swift_enum_tag_single_layout(child,0)!
		witness := read64(child - 8); bits := read32(witness + 80); child_mask := u64(bits & 255)
		// The existing String table also carries the legacy extra-inhabitant
		// marker. Tuple layout derives its own flags and the explicit EI count.
		if bits & ~u32(0x022b00ff) != 0 || child_mask > 7 || layout.extra > 0x7fffffff { return swift_tuple_metadata_failure() }
		size = (size + child_mask) & ~child_mask; offsets[i] = size
		if size > 24 || layout.size > 24 - size { return swift_tuple_metadata_failure() }
		size += layout.size; if child_mask > mask { mask = child_mask }; if layout.extra > extra { extra = layout.extra }
		if bits & 0x10000 != 0 { pod = false }
		// Validate all field operations now, before publishing usable metadata.
		for slot in u64(1)..8 { entry := read64(witness + slot * 8); if entry == 0 || entry & 3 != 0 { return swift_tuple_metadata_failure() } }
	}
	page := usize(C.getpagesize()); allocation := C.mmap(unsafe { nil },page,C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	if allocation == unsafe { voidptr(-1) } { return swift_tuple_metadata_failure() }
	base := u64(allocation); metadata := base + 8; witness := base + 32 + flags * 16
	unsafe { *(&u64(base)) = witness; *(&u64(metadata)) = 0x301; *(&u64(metadata + 8)) = flags }
	for i in u64(0)..flags { unsafe { *(&u64(metadata + 24 + i * 16)) = read64(elements + i * 8); *(&u64(metadata + 32 + i * 16)) = offsets[i] } }
	for i, entry in [u64(unsafe { voidptr(swift_tuple_initialize) }),u64(unsafe { voidptr(swift_tuple_destroy) }),
		u64(unsafe { voidptr(swift_tuple_initialize) }),u64(unsafe { voidptr(swift_tuple_assign) }),
		u64(unsafe { voidptr(swift_tuple_take) }),u64(unsafe { voidptr(swift_tuple_assign_take) }),
		u64(unsafe { voidptr(swift_tuple_enum_get) }),u64(unsafe { voidptr(swift_tuple_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = entry } }
	stride := (size + mask) & ~mask
	unsafe { *(&u64(witness + 64)) = size; *(&u64(witness + 72)) = if stride == 0 { u64(1) } else { stride } }
	write32(witness + 80,u32(mask) | if pod { u32(0) } else { u32(0x10000) }); write32(witness + 84,extra)
	if C.mprotect(allocation,page,C.PROT_READ) != 0 { C.munmap(allocation,page); return swift_tuple_metadata_failure() }
	ios_runtime.swift_tuple_metadata_pages[ios_runtime.swift_tuple_metadata_count] = base; ios_runtime.swift_tuple_metadata_count++
	return SwiftAssociatedMetadata{metadata:metadata}
}
fn swift_tuple_metadata(request u64, flags u64, elements u64, labels u64, proposed u64) SwiftAssociatedMetadata {
	return swift_tuple_metadata_checked(request,flags,elements,labels,proposed) or { panic(err) }
}
fn swift_tuple_metadata_stop() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ios_runtime.swift_tuple_metadata_retired = true
	// Shutdown has joined users and destroyed values before retiring metadata.
	for i in u64(0)..ios_runtime.swift_tuple_metadata_count {
		if C.munmap(voidptr(ios_runtime.swift_tuple_metadata_pages[i]),usize(C.getpagesize())) != 0 { panic('iOS: cannot retire tuple metadata') }
		ios_runtime.swift_tuple_metadata_pages[i] = 0
	}
	ios_runtime.swift_tuple_metadata_count = 0
}
