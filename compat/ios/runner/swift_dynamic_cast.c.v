// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftDynamicCastFailure {}
fn (_ &SwiftDynamicCastFailure) msg() string { return 'iOS: unsupported or invalid Swift dynamic cast representation' }
fn (_ &SwiftDynamicCastFailure) code() int { return 1 }
struct SwiftDynamicCastForcedFailure {}
fn (_ &SwiftDynamicCastForcedFailure) msg() string { return 'iOS: unconditional Swift dynamic cast failed' }
fn (_ &SwiftDynamicCastForcedFailure) code() int { return 2 }
__global swift_dynamic_cast_failure_value = SwiftDynamicCastFailure{}
__global swift_dynamic_cast_forced_failure_value = SwiftDynamicCastForcedFailure{}
fn swift_dynamic_cast_failure() IError { return unsafe { &swift_dynamic_cast_failure_value } }

struct SwiftDynamicCastValue {
	metadata u64
	witness u64
	size u64
	alignment u64
	boxed bool
	any bool
	primitive bool
	cls u64
}
type SwiftDynamicCastCopy = fn (u64,u64,u64) u64
type SwiftDynamicCastDestroy = fn (u64,u64)

// Metadata/VWT records and callback code are immutable caller-owned spans.
// Only our canonical unconstrained Any and ObjC wrappers use special paths.
fn swift_dynamic_cast_value_checked(metadata u64) !SwiftDynamicCastValue {
	if metadata < 8 || metadata & 7 != 0 || metadata > ~u64(0) - 16 { return swift_dynamic_cast_failure() }
	kind := read64(metadata); mut any := false; mut cls := u64(0); mut primitive := false
	C.ios_objc_initialize_lock()
	if kind == 0x303 {
		any = ios_runtime.swift_error_arena != 0 && metadata == ios_runtime.swift_error_arena + u64(C.getpagesize()) + 456
	} else if kind == 0x305 {
		candidate := read64(metadata + 8)
		if (ios_runtime.swift_objc_metadata[candidate] or { u64(0) }) == metadata { cls = candidate }
	}
	page := u64(C.getpagesize())
	if ios_runtime.swift_integer_arena != 0 {
		data := ios_runtime.swift_integer_arena + page
		primitive = metadata == data + 16 || metadata == data + 648 || metadata == data + 680
	}
	primitive = primitive || (ios_runtime.swift_metadata_arena != 0 && metadata == ios_runtime.swift_metadata_arena + page + 16)
	C.ios_objc_initialize_unlock()
	if kind !in [u64(0x200),0x201,0x202,0x301,0x304]! && !any && cls == 0 { return swift_dynamic_cast_failure() }
	witness := read64(metadata - 8)
	if witness == 0 || witness & 7 != 0 || witness > ~u64(0) - 88 { return swift_dynamic_cast_failure() }
	size := read64(witness + 64); stride := read64(witness + 72); flags := read32(witness + 80)
	alignment := u64(flags & 255) + 1
	if size > 65536 || stride == 0 || stride < size || alignment & (alignment - 1) != 0
		|| stride & (alignment - 1) != 0 || flags & 0x00400000 != 0 { return swift_dynamic_cast_failure() }
	return SwiftDynamicCastValue{metadata,witness,size,alignment,flags & 0x20000 != 0,any,primitive,cls}
}
fn swift_dynamic_cast_entry(value SwiftDynamicCastValue, slot u64) !u64 {
	entry := read64(value.witness + slot * 8)
	if entry == 0 || entry & 3 != 0 { return swift_dynamic_cast_failure() }
	return entry
}
fn swift_dynamic_cast_span(address u64, value SwiftDynamicCastValue) ! {
	if address == 0 || address & (value.alignment - 1) != 0 || address > ~u64(0) - value.size { return swift_dynamic_cast_failure() }
}

// Physical registered ObjC ancestry only. Formal-class/isKind overrides and
// private CFError/Swift heap layouts need separate casting implementations.
fn swift_dynamic_cast_class_checked(owner u64, source u64, target u64) !bool {
	if owner == 0 || owner & 7 != 0 { return swift_dynamic_cast_failure() }
	C.ios_objc_initialize_lock(); defer { C.ios_objc_initialize_unlock() }
	mut cls := u64(0)
	if header := ios_runtime.objects[owner] {
		if header.releasing || header.destroying || header.destroyed || C.ios_ref_change(unsafe { &header.refs },0) <= 0
			|| read64(owner) != header.cls { return swift_dynamic_cast_failure() }
		cls = header.cls
	} else if owner in ios_runtime.constants { cls = read64(owner) }
	else { return swift_dynamic_cast_failure() }
	mut source_found := source == 0; mut target_found := target == 0
	for _ in 0 .. 128 {
		info := ios_runtime.classes[cls] or { return swift_dynamic_cast_failure() }
		if info.meta || (info.dynamic && !info.registered) || read64(cls + 32) & 2 != 0 || cls == cf_error_type_id()
			|| 'class' in info.methods || 'isKindOfClass:' in info.methods { return swift_dynamic_cast_failure() }
		if cls == source { source_found = true }; if cls == target { target_found = true }
		cls = info.parent
		if cls == 0 {
			if !source_found { return swift_dynamic_cast_failure() }
			return target_found
		}
	}
	return swift_dynamic_cast_failure()
}

// Dest is uninitialized and disjoint from initialized Source. Flags 1/2/4
// mean unconditional, take-on-success, destroy-on-failure. Unsupported casts
// reject before writes or consumption; they are not conditional failures.
fn swift_dynamic_cast_checked(destination u64, source u64, source_type u64, target_type u64, flags u64) !bool {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired || flags & ~u64(7) != 0 { return swift_dynamic_cast_failure() }
	declared := swift_dynamic_cast_value_checked(source_type)!; target := swift_dynamic_cast_value_checked(target_type)!
	swift_dynamic_cast_span(source,declared)!; swift_dynamic_cast_span(destination,target)!
	if declared.size != 0 && target.size != 0 && source < destination + target.size && destination < source + declared.size { return swift_dynamic_cast_failure() }
	mut value := declared
	if declared.any {
		layout := swift_any_layout(source)!
		if layout.boxed { return swift_dynamic_cast_failure() }
		value = swift_dynamic_cast_value_checked(layout.metadata)!
		if value.any || value.boxed || value.size > 24 || value.alignment > 8 { return swift_dynamic_cast_failure() }
	}
	mut matches := value.metadata == target.metadata || target.any
	if value.cls != 0 {
		matches = swift_dynamic_cast_class_checked(read64(source),value.cls,target.cls)! && (target.any || target.cls != 0)
		if !target.any && target.cls == 0 { return swift_dynamic_cast_failure() }
	} else if !matches && !(value.primitive && target.primitive) { return swift_dynamic_cast_failure() }
	if !matches {
		if flags & 1 != 0 { return unsafe { &swift_dynamic_cast_forced_failure_value } }
		if flags & 4 != 0 {
			if declared.any { swift_dynamic_cast_entry(value,1)! }
			entry := swift_dynamic_cast_entry(declared,1)!; destroy := unsafe { SwiftDynamicCastDestroy(voidptr(entry)) };destroy(source,declared.metadata)
		}
		return false
	}
	if target.any && (value.boxed || value.size > 24 || value.alignment > 8) { return swift_dynamic_cast_failure() }
	// Identity Any takes transfer the complete container, including padding.
	construction := if declared.any && target.any { declared } else { value }
	if declared.any && target.any && flags & 2 == 0 { swift_dynamic_cast_entry(value,2)! }
	entry := swift_dynamic_cast_entry(construction,if flags & 2 != 0 { u64(4) } else { u64(2) })!
	// The engine publishes the contained type before initializing its payload.
	if target.any { unsafe { *(&u64(destination + 24)) = value.metadata } }
	construct := unsafe { SwiftDynamicCastCopy(voidptr(entry)) };construct(destination,source,construction.metadata)
	return true
}
fn swift_dynamic_cast(destination u64,source u64,source_type u64,target_type u64,flags u64) bool {
	return swift_dynamic_cast_checked(destination,source,source_type,target_type,flags) or { panic(err) }
}
