// SPDX-License-Identifier: GPL-2.0-or-later
module main

struct SwiftErrorValue {
	value u64
	metadata u64
	witness u64
}

// Objective-C reference values have a one-word Swift layout. Copies retain
// before publication; assignments publish before releasing the old owner,
// whose dealloc can reenter the runtime. Takes leave source uninitialized.
fn swift_objc_value_copy(destination u64, source u64, _metadata u64) u64 {
	owner := swift_error_retain(read64(source))
	unsafe { *(&u64(destination)) = owner }
	return destination
}
fn swift_objc_value_destroy(value u64, _metadata u64) { swift_error_release(read64(value)) }
fn swift_objc_value_assign_copy(destination u64, source u64, _metadata u64) u64 {
	owner := swift_error_retain(read64(source))
	previous := read64(destination)
	unsafe { *(&u64(destination)) = owner }
	swift_error_release(previous)
	return destination
}
fn swift_objc_value_take(destination u64, source u64, _metadata u64) u64 {
	unsafe { *(&u64(destination)) = read64(source) }
	return destination
}
fn swift_objc_value_assign_take(destination u64, source u64, _metadata u64) u64 {
	previous := read64(destination)
	unsafe { *(&u64(destination)) = read64(source) }
	swift_error_release(previous)
	return destination
}

fn swift_cf_error_domain(owner u64) SwiftStringWords {
	text := string_text(cf_error_domain(owner))
	// Copy the domain into owned Swift storage. The returned String may outlive
	// the error and its NSString; a large borrowed literal would dangle here.
	words := unsafe { &SwiftStringWords(C.__builtin_alloca(16)) }
	unsafe { *words = swift_interpolation_init(i64(text.len), 0) }
	swift_string_append_bytes(u64(words), u64(text.str), u64(text.len))
	return unsafe { *words }
}
fn swift_cf_error_info(owner u64) u64 {
	if read64(owner) != cf_error_type_id() { panic('iOS: unsupported Swift CFError witness owner') }
	info := obj_header(owner).fields[1]
	// CFErrorCopyUserInfo produces an owned dictionary, including for no keys.
	return if info != 0 { objc_retain(info) } else { objc_allocate(ios_runtime.names['NSDictionary']) }
}

// Shared sealed value witnesses and a concrete, working CFError: Error table.
// It includes all four requirements, with indirect self in x20. Conformance
// discovery and arbitrary NSError subclasses remain separate runtime features;
// generic boxes carry their supplied Error table instead of this CFError table.
fn swift_error_metadata_arena() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.swift_error_arena != 0 { return ios_runtime.swift_error_arena }
	$if !arm64 { panic('iOS: Swift error witnesses require ARM64') }
	page := u64(C.getpagesize())
	allocation := C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { panic('iOS: cannot allocate Swift error metadata') }
	code := u64(allocation)
	data := code + page
	witness := data + 32
	table := data + 160
	conformance := data + 208
	protocol := data + 240
	module := data + 320
	class_slot := data + 352
	for i, target in [u64(unsafe { voidptr(swift_objc_value_copy) }),
		u64(unsafe { voidptr(swift_objc_value_destroy) }), u64(unsafe { voidptr(swift_objc_value_copy) }),
		u64(unsafe { voidptr(swift_objc_value_assign_copy) }), u64(unsafe { voidptr(swift_objc_value_take) }),
		u64(unsafe { voidptr(swift_objc_value_assign_take) }), u64(unsafe { voidptr(swift_array_enum_get) }),
		u64(unsafe { voidptr(swift_array_enum_store) })]! { unsafe { *(&u64(witness + u64(i * 8))) = target } }
	unsafe { *(&u64(witness + 64)) = 8; *(&u64(witness + 72)) = 8 }
	write32(witness + 80, 0x10007) // Alignment 8, non-POD, inline, bitwise-takable.
	write32(witness + 84, 0x7fffffff)
	unsafe { *(&u64(table)) = conformance; *(&u64(class_slot)) = cf_error_type_id() }
	swift_protocol_relative(conformance, protocol)
	swift_protocol_relative(conformance + 4, class_slot)
	swift_protocol_relative(conformance + 8, table)
	write32(conformance + 12, 0x18) // Indirect ObjC class reference, concrete conformance.
	write32(protocol, 0x70043) // Unique Swift protocol, special Error protocol.
	swift_protocol_relative(protocol + 4, module)
	swift_protocol_relative(protocol + 8, data + 344)
	write32(protocol + 16, 4)
	for i, target in [u64(unsafe { voidptr(swift_cf_error_domain) }),
		u64(unsafe { voidptr(cf_error_code) }), u64(unsafe { voidptr(swift_cf_error_info) }),
		u64(unsafe { voidptr(objc_retain) })]! {
		entry := code + u64(i * 32)
		// x20 points at the borrowed CFError reference value, not at its object.
		write32(entry, 0xf9400280) // ldr x0,[x20]
		write32(entry + 4, 0x58000070)
		write32(entry + 8, 0xd61f0200)
		write32(entry + 12, 0xd503201f)
		unsafe { *(&u64(entry + 16)) = target; *(&u64(table + 8 + u64(i * 8))) = entry }
		// Signature discriminators match the installed public Error descriptor;
		// Vinix's ARM64 entries use ordinary pointers without authentication.
		flags := [u32(0x6e080013), 0xeed60013, 0x84f80013, 0x12850011]!
		write32(protocol + 24 + u64(i * 8), flags[i])
	}
	swift_protocol_relative(module + 8, data + 336)
	C.memcpy(unsafe { voidptr(data + 336) }, c'Swift', 6)
	C.memcpy(unsafe { voidptr(data + 344) }, c'Error', 6)
	// Special one-word Error existential: protocol count one and Error flag.
	unsafe {
		*(&u64(data + 384)) = witness
		*(&u64(data + 392)) = 0x303
		*(&u64(data + 400)) = 0x181000001
		*(&u64(data + 408)) = protocol
	}
	swift_any_emit(code,data)
	swift_error_code_emit(code + 160)
	swift_error_domain_emit(code + 192)
	swift_error_user_info_emit(code + 224)
	swift_error_self_emit(code, data, protocol)
	swift_result_nominal_emit(code, data, protocol)
	C.__builtin___clear_cache(allocation, unsafe { voidptr(code + 656) })
	if C.mprotect(allocation, usize(page), C.PROT_READ | C.PROT_EXEC) != 0
		|| C.mprotect(unsafe { voidptr(data) }, usize(page), C.PROT_READ) != 0 {
		C.munmap(allocation, usize(page * 2))
		panic('iOS: cannot seal Swift error metadata')
	}
	ios_runtime.swift_error_arena = code
	return code
}

fn swift_objc_metadata_checked(cls u64) !u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	info := ios_runtime.classes[cls] or { return error('iOS: Swift metadata requires a registered ObjC class') }
	if info.meta || (info.dynamic && !info.registered) { return error('iOS: invalid Swift ObjC class metadata') }
	// Swift-compiled class metadata is already the type metadata address point.
	if read64(cls + 32) & 2 != 0 { return cls }
	if metadata := ios_runtime.swift_objc_metadata[cls] { return metadata }
	page := usize(C.getpagesize())
	witness := swift_error_metadata_arena() + u64(page) + 32
	allocation := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	if allocation == unsafe { voidptr(-1) } { return error('iOS: cannot allocate Swift ObjC wrapper metadata') }
	metadata := u64(allocation) + 8
	unsafe { *(&u64(metadata - 8)) = witness; *(&u64(metadata)) = 0x305; *(&u64(metadata + 8)) = cls }
	if C.mprotect(allocation, page, C.PROT_READ) != 0 {
		C.munmap(allocation, page)
		return error('iOS: cannot seal Swift ObjC wrapper metadata')
	}
	ios_runtime.swift_objc_metadata[cls] = metadata
	return metadata
}
fn swift_objc_metadata(cls u64) u64 {
	if cls == 0 { return 0 }
	return swift_objc_metadata_checked(cls) or { panic(err) }
}

fn swift_error_value_checked(owner u64, scratch &u64, output &SwiftErrorValue) ! {
	if owner == 0 || output == unsafe { nil } || u64(output) & 7 != 0
		|| u64(output) > ~u64(0)-24 { return error('iOS: invalid Swift error extraction buffers') }
	if swift_error_allocation_project_checked(owner,output)! { return }
	if scratch == unsafe { nil } || u64(scratch) & 7 != 0 { return error('iOS: invalid Swift error extraction scratch') }
	C.ios_objc_initialize_lock()
	header := ios_runtime.objects[owner] or {
		C.ios_objc_initialize_unlock()
		return error('iOS: Swift error extraction requires a live runtime owner')
	}
	valid := header.cls == cf_error_type_id() && C.ios_ref_change(unsafe { &header.refs }, 0) > 0
	C.ios_objc_initialize_unlock()
	if !valid { return error('iOS: Swift error extraction supports CFError; native boxes and other NSError classes are not implemented') }
	metadata := swift_objc_metadata(header.cls)
	witness := swift_error_metadata_arena() + u64(C.getpagesize()) + 160
	// Scratch and metadata borrow the owner; no ARC operation is performed.
	unsafe { *scratch = owner; *output = SwiftErrorValue{ value: u64(scratch), metadata: metadata, witness: witness } }
}
fn swift_error_value(owner u64, scratch &u64, output &SwiftErrorValue) {
	swift_error_value_checked(owner, scratch, output) or { panic(err) }
}

fn swift_error_value_symbol(symbol string) ?u64 {
	return match symbol {
		'_$ss5ErrorWS' { swift_error_self_table_checked() or { return none } }
		'_$ss5ErrorPsE9_userInfoyXlSgvg' { swift_error_user_info_entry() or { return none } }
		'_$ss5ErrorPsE7_domainSSvg' { swift_error_domain_entry() or { return none } }
		'_$ss5ErrorPsE5_codeSivg' { swift_error_code_entry() or { return none } }
		'_$ss5ErrorPsE19_getEmbeddedNSErroryXlSgyF' { u64(unsafe { voidptr(swift_error_embedded) }) }
		'__swift_stdlib_bridgeErrorToNSError' { u64(unsafe { voidptr(swift_error_bridge) }) }
		'_$sypN' { swift_any_full_metadata() }
		'_swift_getErrorValue' { u64(unsafe { voidptr(swift_error_value) }) }
		'_swift_getObjCClassMetadata' { u64(unsafe { voidptr(swift_objc_metadata) }) }
		'_$ss5ErrorMp' { swift_error_metadata_arena() + u64(C.getpagesize()) + 240 }
		'_$ss5ErrorP7_domainSSvgTq' { swift_error_metadata_arena() + u64(C.getpagesize()) + 264 }
		'_$ss5ErrorP5_codeSivgTq' { swift_error_metadata_arena() + u64(C.getpagesize()) + 272 }
		'_$ss5ErrorP9_userInfoyXlSgvgTq' { swift_error_metadata_arena() + u64(C.getpagesize()) + 280 }
		'_$ss5ErrorP19_getEmbeddedNSErroryXlSgyFTq' { swift_error_metadata_arena() + u64(C.getpagesize()) + 288 }
		else { return none }
	}
}

fn swift_error_metadata_stop() {
	if ios_runtime.swift_objc_metadata.len != 0 && ios_runtime.live != 0 {
		panic('iOS: Swift ObjC metadata owners still live at shutdown')
	}
	page := usize(C.getpagesize())
	for _, metadata in ios_runtime.swift_objc_metadata {
		if C.munmap(unsafe { voidptr(metadata - 8) }, page) != 0 { panic('iOS: cannot retire Swift ObjC metadata') }
	}
	unsafe { ios_runtime.swift_objc_metadata.free() }
	if ios_runtime.swift_error_arena != 0 {
		if C.munmap(unsafe { voidptr(ios_runtime.swift_error_arena) }, page * 2) != 0 { panic('iOS: cannot retire Swift error witnesses') }
		ios_runtime.swift_error_arena = 0
	}
}
