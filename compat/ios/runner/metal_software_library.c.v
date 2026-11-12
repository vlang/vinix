// SPDX-License-Identifier: GPL-2.0-or-later
module main

import metallib

// The index borrows the library object's immutable data. Function handles retain
// that object. Container validation does not verify or execute the LLVM IR.
struct SoftwareMetalLibrary { index metallib.Library }
fn sm_library_dispose(mut h ObjHeader) {
	if h.metal_library == unsafe { nil } { return }
	h.metal_library.index.free()
	C.free(h.metal_library)
	h.metal_library = unsafe { nil }
}
fn sm_library_error(output &u64, code i64, reason string) u64 {
	if output == unsafe { nil } { return 0 }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	domain := owned_string('MTLLibraryErrorDomain')
	info := objc_allocate(ios_runtime.names['NSDictionary'])
	key := owned_string('NSLocalizedDescription'); detail := owned_string(reason)
	dictionary_insert_copy(info, detail, key)
	object := ns_error_create(domain, code, info)
	objc_release(domain); objc_release(info); objc_release(key); objc_release(detail)
	unsafe { *output = objc_autorelease(object) }
	return 0
}
fn sm_library_data(device u64, selector &char, data u64, output &u64) u64 {
	C.ios_objc_initialize_lock()
	sm_check(device, 'VinixSoftwareMTLDevice')
	C.ios_objc_initialize_unlock()
	if dispatch_runtime == unsafe { nil } { return sm_library_error(output, 1, 'Software Metal requires live dispatch data') }
	// Bound the size before mapping a rope, which may allocate a contiguous copy.
	C.pthread_mutex_lock(dispatch_runtime.mutex)
	input := dispatch_runtime.data[data] or {
		C.pthread_mutex_unlock(dispatch_runtime.mutex)
		return sm_library_error(output, 1, 'Software Metal requires dispatch data')
	}
	size := input.size
	C.pthread_mutex_unlock(dispatch_runtime.mutex)
	if size > u64(metallib.max_library_size) { return sm_library_error(output, 1, 'Software Metal library exceeds 256 MiB') }
	if size < 88 { return sm_library_error(output, 3, 'Truncated compiled Metal library') }
	mut pointer := u64(0); mut mapped_size := u64(0)
	mapped := darwin_dispatch_data_create_map(data, &pointer, &mapped_size)
	bytes := unsafe { (&u8(pointer)).vbytes(int(mapped_size)).clone() }
	darwin_dispatch_release(mapped) // No dispatch storage or callbacks retained by the library.
	return sm_library_bytes(device, bytes, output)
}
// Takes ownership of bytes on success and failure.
fn sm_library_bytes(device u64, bytes []u8, output &u64) u64 {
	index := metallib.parse(bytes) or {
		unsafe { bytes.free() }
		return sm_library_error(output, 3, err.msg())
	}
	for function in index.functions {
		if function.kind > 2 {
			index.free(); unsafe { bytes.free() }
			return sm_library_error(output, 1, 'Software Metal supports vertex, fragment and kernel metadata only')
		}
	}
	state := unsafe { &SoftwareMetalLibrary(C.malloc(sizeof(SoftwareMetalLibrary))) }
	if state == unsafe { nil } {
		index.free(); unsafe { bytes.free() }
		return sm_library_error(output, 2, 'Cannot allocate software Metal library')
	}
	unsafe { *state = SoftwareMetalLibrary{index} }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	library := sm_new('VinixSoftwareMTLLibrary', device)
	mut h := obj_header(library)
	h.data = bytes
	h.metal_library = state
	return library // newLibrary transfers +1; success leaves NSError ** untouched.
}
fn sm_library_file(device u64, selector &char, filename u64, output &u64) u64 {
	C.ios_objc_initialize_lock()
	sm_check(device, 'VinixSoftwareMTLDevice')
	if filename == 0 || !objc_is_kind(filename, ios_runtime.names['NSString']) {
		C.ios_objc_initialize_unlock()
		return sm_library_error(output, 1, 'Software Metal library path requires NSString')
	}
	text := string_text(filename)
	if text.len == 0 || text.len > 1023 || text.contains('\x00') {
		C.ios_objc_initialize_unlock()
		return sm_library_error(output, 1, 'Invalid software Metal library path')
	}
	path := text.clone()
	C.ios_objc_initialize_unlock()
	defer { unsafe { path.free() } }
	// Nonblocking open prevents special files such as FIFOs waiting for a writer.
	fd := C.open(path.str, C.O_RDONLY | C.O_NONBLOCK)
	if fd < 0 { return sm_library_error(output, 6, 'Cannot open compiled Metal library file') }
	defer { C.close(fd) }
	mut fields := [20]u64{}
	if C.ios_stat_info(unsafe { nil }, i32(fd), 2, unsafe { &fields[0] }) != 0 { return sm_library_error(output, 2, 'Cannot stat compiled Metal library file') }
	if fields[1] & 0xf000 != 0x8000 { return sm_library_error(output, 1, 'Software Metal libraries require regular files') }
	if fields[15] > u64(metallib.max_library_size) { return sm_library_error(output, 1, 'Software Metal library exceeds 256 MiB') }
	mut bytes := []u8{len: int(fields[15])}
	mut offset := 0
	for offset < bytes.len {
		count := C.read(fd, unsafe { &bytes[offset] }, usize(bytes.len - offset))
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		if count <= 0 { unsafe { bytes.free() }; return sm_library_error(output, 3, 'Cannot read complete compiled Metal library') }
		offset += int(count)
	}
	// Reject growth after stat rather than silently accepting a prefix.
	mut extra := u8(0)
	for {
		count := C.read(fd, &extra, 1)
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		if count != 0 { unsafe { bytes.free() }; return sm_library_error(output, 3, 'Compiled Metal library changed during read') }
		break
	}
	return sm_library_bytes(device, bytes, output)
}
fn sm_library_get(object u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(object, 'VinixSoftwareMTLLibrary')
	if ctext(u64(selector)) == 'device' { return h.fields[0] }
	array := objc_allocate(ios_runtime.names['NSArray'])
	mut result := obj_header(array)
	for function in h.metal_library.index.functions { result.items << owned_string(function.name) }
	return objc_autorelease(array)
}
fn sm_library_function(library u64, selector &char, name u64) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(library, 'VinixSoftwareMTLLibrary')
	if name == 0 || !objc_is_kind(name, ios_runtime.names['NSString']) { return 0 }
	for function in h.metal_library.index.functions {
		if function.name != string_text(name) { continue }
		object := sm_new('VinixSoftwareMTLFunction', library)
		mut result := obj_header(object)
		result.fields[1] = owned_string(function.name)
		result.number = i64(function.kind) + 1
		return object
	}
	return 0
}
fn sm_function_get(object u64, selector &char) u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	h := sm_check(object, 'VinixSoftwareMTLFunction')
	return match ctext(u64(selector)) {
		'device' { obj_header(h.fields[0]).fields[0] }
		'name' { h.fields[1] }
		'functionType' { u64(h.number) }
		else { panic('iOS: unsupported software Metal function property') }
	}
}
fn sm_library_start(device u64) {
	for name in [c'VinixSoftwareMTLLibrary', c'VinixSoftwareMTLFunction']! {
		cls := objc_allocate_class(ios_runtime.names['NSObject'], name, 0)
		objc_register_class(cls)
	}
	library := ios_runtime.names['VinixSoftwareMTLLibrary']; function := ios_runtime.names['VinixSoftwareMTLFunction']
	sm_method(device, c'newLibraryWithData:error:', u64(unsafe { voidptr(sm_library_data) }), c'@32@0:8@16^@24')
	sm_method(device, c'newLibraryWithFile:error:', u64(unsafe { voidptr(sm_library_file) }), c'@32@0:8@16^@24')
	for selector in [c'device', c'functionNames']! { sm_method(library, selector, u64(unsafe { voidptr(sm_library_get) }), c'@16@0:8') }
	sm_method(library, c'newFunctionWithName:', u64(unsafe { voidptr(sm_library_function) }), c'@24@0:8@16')
	for selector in [c'device', c'name']! { sm_method(function, selector, u64(unsafe { voidptr(sm_function_get) }), c'@16@0:8') }
	sm_method(function, c'functionType', u64(unsafe { voidptr(sm_function_get) }), c'Q16@0:8')
}
