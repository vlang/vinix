// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftErrorDomainFailure {}
fn (_ &SwiftErrorDomainFailure) msg() string { return 'iOS: unsupported or inactive Swift Error domain type' }
fn (_ &SwiftErrorDomainFailure) code() int { return 1 }
__global swift_error_domain_failure_value = SwiftErrorDomainFailure{}
fn swift_error_domain_failure() IError { return unsafe { &swift_error_domain_failure_value } }

fn swift_error_domain_active() ! {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return swift_error_domain_failure()
	}
}

// Native uses the dynamic type, then a qualified type name. Value metadata
// has no dynamic subclass: Self and its witnesses are not read in this bounded
// profile. Only file-backed non-generic struct/enum descriptors and named
// nominal parents are supported. Class values, generics, private/anonymous,
// extension and imported C contexts need separate naming/dynamic-type work.
fn swift_error_domain_checked(_source u64, metadata u64) !SwiftStringWords {
	swift_error_domain_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_error_domain_active()!
	page := u64(C.getpagesize())
	if ios_runtime.swift_merge_error_metadata_arena != 0
		&& metadata == ios_runtime.swift_merge_error_metadata_arena + page + 16 {
		return swift_merge_error_domain()
	}
	if metadata & 7 != 0 || !swift_print_image_range(metadata, 16) { return swift_error_domain_failure() }
	kind := read64(metadata)
	if kind !in [u64(0x200), 0x201]! { return swift_error_domain_failure() }
	mut descriptor := read64(metadata + 8)
	// Stack-only borrowed parts; validate the entire chain before allocating
	// the returned String. Bound depth, each terminated name and total bytes.
	parts := u64(C.__builtin_alloca(32 * 16))
	mut depth := u64(0)
	mut count := u64(0)
	for {
		if depth == 32 || descriptor & 3 != 0 || !swift_print_image_range(descriptor, 12) {
			return swift_error_domain_failure()
		}
		flags := read32(descriptor)
		module_context := flags in [u32(0), 0x40]!
		if depth == 0 {
			if flags != u32(if kind == 0x200 { 0x51 } else { 0x52 }) { return swift_error_domain_failure() }
		} else if !module_context && flags !in [u32(0x50), 0x51, 0x52]! {
			return swift_error_domain_failure()
		}
		name := swift_print_image_text(swift_print_relative(descriptor + 8)!)!
		if name.len == 0 || count + u64(name.len) + u64(depth != 0) > 8192 { return swift_error_domain_failure() }
		unsafe { *(&u64(parts + depth * 16)) = u64(name.str); *(&u64(parts + depth * 16 + 8)) = u64(name.len) }
		count += u64(name.len) + u64(depth != 0)
		depth++
		if module_context {
			if read32(descriptor + 4) != 0 { return swift_error_domain_failure() }
			break
		}
		descriptor = swift_print_relative(descriptor + 4)!
	}
	bytes := u64(C.__builtin_alloca(8192))
	mut offset := u64(0)
	for depth > 0 {
		depth--
		length := read64(parts + depth * 16 + 8)
		C.memcpy(voidptr(bytes + offset), voidptr(read64(parts + depth * 16)), usize(length))
		offset += length
		if depth != 0 { unsafe { *(&u8(bytes + offset)) = `.` }; offset++ }
	}
	// Copy before returning: image names and stack scratch are borrowed. Large
	// results enter the existing String owner registry and use ordinary ARC.
	return swift_print_bytes(SwiftStringBytes{ address: bytes, count: count })
}

fn swift_error_domain(source u64, metadata u64) SwiftStringWords {
	return swift_error_domain_checked(source, metadata) or { panic(err) }
}
fn swift_error_domain_emit(code u64) {
	write32(code, 0xaa0003e1) // metadata x0 -> C x1
	write32(code + 4, 0xaa1403e0) // borrowed Self x20 -> C x0
	write32(code + 8, 0x58000050)
	write32(code + 12, 0xd61f0200)
	unsafe { *(&u64(code + 16)) = u64(voidptr(swift_error_domain)) }
}
fn swift_error_domain_entry() !u64 {
	$if !arm64 { return swift_error_domain_failure() }
	swift_error_domain_active()!
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	swift_error_domain_active()!
	return swift_error_metadata_arena() + 192
}
