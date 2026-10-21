// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftGenericValueFailure {}
fn (_ &SwiftGenericValueFailure) msg() string { return 'iOS: unsupported Swift generic value metadata allocation' }
fn (_ &SwiftGenericValueFailure) code() int { return 1 }
__global swift_generic_value_failure_value = SwiftGenericValueFailure{}
fn swift_generic_value_failure() IError { return unsafe { &swift_generic_value_failure_value } }
fn swift_generic_value_half(address u64) u16 { return unsafe { *(&u16(address)) } }

// Relative references are borrowed from the loaded image. Only the VWT uses
// an indirectable relative pointer; neither its entries nor argument pointees
// need to be complete (or even readable) during this allocation phase.
fn swift_generic_value_relative_checked(field u64, indirectable bool) !u64 {
	bits := read32(field)
	if bits == 0 { return swift_generic_value_failure() }
	delta := i64(i32(if indirectable { bits & ~u32(1) } else { bits }))
	if (delta < 0 && field < u64(-delta)) || (delta > 0 && field > ~u64(0) - u64(delta)) {
		return swift_generic_value_failure()
	}
	mut target := if delta < 0 { field - u64(-delta) } else { field + u64(delta) }
	if indirectable && bits & 1 != 0 {
		if target == 0 || target & 7 != 0 || target > ~u64(0) - 7 { return swift_generic_value_failure() }
		target = read64(target)
	}
	if target == 0 || target & 7 != 0 { return swift_generic_value_failure() }
	return target
}

// Ordinary C ABI: descriptor, argument vector, value pattern, extra byte size.
// This creates fresh *incomplete* metadata, with no uniquing, completion call,
// witness instantiation or claim that the resulting value layout is usable.
fn swift_generic_value_allocate_checked(descriptor u64, arguments u64, pattern u64, extra u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired
		|| ios_runtime.swift_generic_value_retired || descriptor == 0 || descriptor & 3 != 0
		|| descriptor > ~u64(0) - 44 || pattern == 0 || pattern & 3 != 0
		|| pattern > ~u64(0) - 24 || extra > 65536 { return swift_generic_value_failure() }
	flags := read32(descriptor)
	kind := flags & 31
	// Version-zero generic struct/enum contexts. Generic packs, old extra
	// arguments and newer context extensions require separate substitution.
	if kind !in [u32(17),18]! || flags & 0xff80 != 0x80 || swift_generic_value_half(descriptor + 42) != 0 {
		return swift_generic_value_failure()
	}
	params := u64(swift_generic_value_half(descriptor + 36))
	requirements := u64(swift_generic_value_half(descriptor + 38))
	keys := u64(swift_generic_value_half(descriptor + 40))
	if params > 64 || requirements > 64 || keys > 64 || keys * 8 > extra
		|| descriptor > ~u64(0) - 44 - ((params + 3) & ~u64(3)) - requirements * 12 {
		return swift_generic_value_failure()
	}
	mut counted := u64(0)
	for i in u64(0)..params {
		parameter := unsafe { *(&u8(descriptor + 44 + i)) }
		if parameter & 0x7f != 0 { return swift_generic_value_failure() }
		if parameter & 0x80 != 0 { counted++ }
	}
	requirement_base := descriptor + 44 + ((params + 3) & ~u64(3))
	for i in u64(0)..requirements {
		requirement := read32(requirement_base + i * 12)
		if requirement & ~u32(0x9f) != 0 || requirement & 31 !in [u32(0),1,2,31]!
			|| (requirement & 0x80 != 0 && requirement & 31 != 0) { return swift_generic_value_failure() }
		if requirement & 0x80 != 0 { counted++ }
	}
	if counted != keys || (keys != 0 && (arguments == 0 || arguments & 7 != 0
		|| arguments > ~u64(0) - keys * 8)) { return swift_generic_value_failure() }
	pattern_flags := read32(pattern + 8)
	metadata_kind := pattern_flags >> 21
	if pattern_flags & 0x1ffffe != 0 || metadata_kind != if kind == 17 { u32(0x200) } else { u32(0x201) } {
		return swift_generic_value_failure()
	}
	witness := swift_generic_value_relative_checked(pattern + 12,true)!
	mut prefix := u64(0)
	mut size := u64(0)
	mut source := u64(0)
	if pattern_flags & 1 != 0 {
		prefix = u64(swift_generic_value_half(pattern + 20)) * 8
		size = u64(swift_generic_value_half(pattern + 22)) * 8
		if prefix + size != extra { return swift_generic_value_failure() }
		if size != 0 {
			source = swift_generic_value_relative_checked(pattern + 16,false)!
			if source > ~u64(0) - size { return swift_generic_value_failure() }
		}
	}
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_generic_value_retired || ios_runtime.swift_concurrency_retired { return swift_generic_value_failure() }
	page := u64(C.getpagesize())
	length := (24 + extra + page - 1) & ~(page - 1)
	allocation := C.mmap(unsafe { nil },usize(length),C.PROT_READ | C.PROT_WRITE,C.MAP_PRIVATE | C.MAP_ANONYMOUS,-1,0)
	if allocation == unsafe { voidptr(-1) } { return swift_generic_value_failure() }
	base := u64(allocation)
	metadata := base + 8
	unsafe { *(&u64(base)) = witness;*(&u64(metadata)) = metadata_kind;*(&u64(metadata + 8)) = descriptor }
	if size != 0 { C.memcpy(voidptr(metadata + 16 + prefix),voidptr(source),usize(size)) }
	// Arguments overwrite overlapping partial-pattern words, as in SwiftCore.
	if keys != 0 { C.memcpy(voidptr(metadata + 16),voidptr(arguments),usize(keys * 8)) }
	ios_runtime.swift_generic_value_allocations[base] = length
	return metadata
}

fn swift_generic_value_allocate(descriptor u64, arguments u64, pattern u64, extra u64) u64 {
	return swift_generic_value_allocate_checked(descriptor,arguments,pattern,extra) or { panic(err) }
}

fn swift_generic_value_metadata_stop() {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	ios_runtime.swift_generic_value_retired = true
	// Metadata stays writable for its owning completion/cache machinery. All
	// metadata users must have drained before this shared runtime retirement.
	for base,length in ios_runtime.swift_generic_value_allocations {
		if C.munmap(voidptr(base),usize(length)) != 0 { panic('iOS: cannot retire generic value metadata') }
	}
	unsafe { ios_runtime.swift_generic_value_allocations.free() }
}
