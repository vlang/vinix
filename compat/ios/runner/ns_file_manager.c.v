// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Installed Foundation measures a 32-byte NSObject subclass. Its private ivars
// stay opaque; directory operations use native POSIX paths without a sidecar.
fn ns_file_manager_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if info.name == 'NSFileManager' { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic file manager superclass chain')
}

fn ns_file_manager_default() u64 {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.file_manager == 0 {
		ios_runtime.file_manager = objc_allocate(ios_runtime.names['NSFileManager'])
		// The runtime owns this one reference until all callers stop at teardown.
	}
	return ios_runtime.file_manager
}

fn ns_file_manager_path(object u64) string {
	if object == 0 { return '' }
	if !objc_is_kind(object, ios_runtime.names['NSString']) { panic('iOS: file manager path requires NSString') }
	path := string_text(object)
	if path.len > 1023 || path.contains('\x00') { panic('iOS: file manager path exceeds the bounded POSIX profile') }
	return path
}

fn ns_file_manager_mode(attributes u64) u32 {
	if attributes == 0 { return 0o777 }
	if !objc_is_kind(attributes, ios_runtime.names['NSDictionary']) { panic('iOS: directory attributes require NSDictionary') }
	header := obj_header(attributes)
	if header.cf_raw_keys || header.cf_raw_values { panic('iOS: directory attributes require owning object callbacks') }
	mut mode := u32(0o777)
	for i, key in header.keys {
		if !objc_is_kind(key, ios_runtime.names['NSString']) || string_text(key) != 'NSFilePosixPermissions' {
			panic('iOS: only POSIX directory permission attributes are implemented')
		}
		value := header.items[i]
		if !objc_is_kind(value, ios_runtime.names['NSNumber']) { panic('iOS: directory permissions require NSNumber') }
		number := obj_header(value)
		if number.is_real || number.number < 0 || u64(number.number) > 0o7777 { panic('iOS: directory permissions exceed POSIX mode bits') }
		mode = u32(number.number)
	}
	return mode
}

fn ns_file_manager_directory(path &char, output &u8) i32 {
	mut fields := [20]u64{}
	result := C.ios_stat_info(path, -1, 0, unsafe { &fields[0] })
	// Foundation leaves isDirectory unchanged on failure, including dangling links.
	if result == 0 && output != unsafe { nil } { unsafe { *output = u8(fields[1] & 0xf000 == 0x4000) } }
	return result
}

fn ns_file_manager_error(output u64, path string, native i32) {
	if output == 0 { return }
	code := i64(darwin_native_error(native))
	posix_domain := owned_string('NSPOSIXErrorDomain')
	underlying := ns_error_create(posix_domain, code, 0)
	objc_release(posix_domain)
	info := objc_allocate(ios_runtime.names['NSDictionary'])
	mut header := obj_header(info)
	header.keys << owned_string('NSFilePath')
	path_object := owned_string(path)
	array_append(mut header, path_object)
	objc_release(path_object)
	header.keys << owned_string('NSUnderlyingError')
	array_append(mut header, underlying)
	objc_release(underlying)
	domain := owned_string('NSCocoaErrorDomain')
	error_object := ns_error_create(domain, if code == 2 { i64(4) } else if code == 17 { i64(516) } else if code == 13 { i64(513) } else { i64(512) }, info)
	objc_release(domain)
	objc_release(info)
	unsafe { *(&u64(output)) = objc_autorelease(error_object) }
}

fn ns_file_manager_mkdir(path &char, mode u32, explicit bool) i32 {
	result := C.ios_mkdir(path, mode)
	if result != 0 || !explicit { return result }
	// An explicit permission attribute overrides umask on each created directory.
	return i32(C.chmod(path, mode))
}

fn ns_file_manager_create(path_object u64, intermediate bool, attributes u64, error_output u64) bool {
	path := ns_file_manager_path(path_object)
	mode := ns_file_manager_mode(attributes)
	explicit := attributes != 0 && obj_header(attributes).keys.len != 0
	mut buffer := [1024]u8{}
	unsafe { C.memcpy(&buffer[0], path.str, usize(path.len)) }
	if !intermediate || path.len == 0 {
		if ns_file_manager_mkdir(unsafe { &char(&buffer[0]) }, mode, explicit) == 0 { return true }
		native := unsafe { *C.ios_errno_address() }
		ns_file_manager_error(error_output, path, native)
		return false
	}
	// Each missing parent receives the supplied permissions, as measured natively.
	// Existing directories (including symlink targets) preserve their permissions.
	for end in 1 .. path.len + 1 {
		if end != path.len && buffer[end] != `/` { continue }
		if buffer[end - 1] == `/` { continue }
		saved := buffer[end]; buffer[end] = 0
		if ns_file_manager_mkdir(unsafe { &char(&buffer[0]) }, mode, explicit) != 0 {
			mut native := unsafe { *C.ios_errno_address() }
			mut directory := u8(0)
			if native == C.EEXIST {
				stat_result := ns_file_manager_directory(unsafe { &char(&buffer[0]) }, unsafe { &directory })
				if stat_result != 0 {
					native = unsafe { *C.ios_errno_address() }
					if native == C.ENOENT { native = C.EIO }
				} else if directory == 0 && end != path.len { native = C.ENOTDIR }
			}
			if directory == 0 {
				ns_file_manager_error(error_output, unsafe { tos(&buffer[0], end) }, native)
				return false
			}
		}
		buffer[end] = saved
	}
	return true
}

fn ns_file_manager_types(name string, meta bool, selector string) ?string {
	if name != 'NSFileManager' { return none }
	if meta { if selector == 'defaultManager' { return '@16@0:8' }; return none }
	return match selector {
		'init', 'delegate' { '@16@0:8' }
		'setDelegate:' { 'v24@0:8@16' }
		'fileExistsAtPath:', 'isReadableFileAtPath:', 'isWritableFileAtPath:', 'isExecutableFileAtPath:' { 'B24@0:8@16' }
		'fileExistsAtPath:isDirectory:' { 'B32@0:8@16^B24' }
		'createDirectoryAtPath:withIntermediateDirectories:attributes:error:',
		'createDirectoryAtURL:withIntermediateDirectories:attributes:error:' { 'B44@0:8@16B24@28^@36' }
		else { return none }
	}
}

fn ns_file_manager_selector(object u64, selector string) bool {
	meta := object in ios_runtime.classes
	if !ns_file_manager_family(if meta { object } else { read64(object) }) { return false }
	if selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { return false }
	return ns_file_manager_types('NSFileManager', meta, selector) != none
}

fn ns_file_manager_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	meta := object in ios_runtime.classes
	if !ns_file_manager_family(if meta { object } else { read64(object) }) { return false }
	if !meta && selector in ['copy', 'copyWithZone:', 'mutableCopy', 'mutableCopyWithZone:']! { panic('iOS: file manager copies are not implemented') }
	if ns_file_manager_types('NSFileManager', meta, selector) == none { return false }
	if meta { frame.x[0] = ns_file_manager_default(); return true }
	match selector {
		'init' {}
		'delegate' { frame.x[0] = 0 }
		'setDelegate:' { if frame.x[2] != 0 { panic('iOS: file manager delegate callbacks are not implemented') } }
		'fileExistsAtPath:', 'fileExistsAtPath:isDirectory:', 'isReadableFileAtPath:', 'isWritableFileAtPath:', 'isExecutableFileAtPath:' {
			path := ns_file_manager_path(frame.x[2])
			mut buffer := [1024]u8{}
			unsafe { C.memcpy(&buffer[0], path.str, usize(path.len)) }
			if selector.starts_with('fileExists') {
				output := if selector == 'fileExistsAtPath:isDirectory:' { frame.x[3] } else { u64(0) }
				frame.x[0] = u64(ns_file_manager_directory(unsafe { &char(&buffer[0]) }, unsafe { &u8(output) }) == 0)
			} else {
				mode := if selector.starts_with('isReadable') { C.R_OK } else if selector.starts_with('isWritable') { C.W_OK } else { C.X_OK }
				frame.x[0] = u64(C.access(unsafe { &char(&buffer[0]) }, mode) == 0)
			}
		}
		else {
			mut path := frame.x[2]
			if selector.starts_with('createDirectoryAtURL:') {
				if path == 0 || !objc_is_kind(path, ios_runtime.names['NSURL']) || obj_header(path).number == 1 { panic('iOS: directory creation requires a file NSURL') }
				path = obj_header(path).fields[0]
			}
			frame.x[0] = u64(ns_file_manager_create(path, frame.x[3] != 0, frame.x[4], frame.x[5]))
		}
	}
	return true
}
