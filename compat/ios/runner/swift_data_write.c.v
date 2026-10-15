// SPDX-License-Identifier: GPL-2.0-or-later
module main

type SwiftDataURLBridge = fn (u64) u64

fn swift_data_write_emit(code u64) {
	// Swift's throwing void entry borrows URL at x0 and Data at x2/x3;
	// options are x1. C returns one owned Error (or nil), moved into x21.
	for i, op in [u32(0xa9bf7bfd), 0x580000f0, 0xd63f0200, 0xaa0003f5, 0xa8c17bfd, 0xd65f03c0]! {
		write32(code + 1024 + u64(i * 4), op)
	}
	unsafe { *(&u64(code + 1056)) = u64(voidptr(swift_data_write)) }
	// C's indirect URL argument becomes the existing URL bridge's Self x20.
	for i, op in [u32(0xa9bf7bf4), 0xaa0003f4, 0x97ffff3e, 0xa8c17bf4, 0xd65f03c0]! {
		write32(code + 1088 + u64(i * 4), op)
	}
}

fn swift_data_write_error(url u64, path string, native i32, atomically bool) u64 {
	info := objc_allocate(ios_runtime.names['NSDictionary'])
	defer { objc_release(info) }
	mut header := obj_header(info)
	mut code := i64(518) // Non-file URL: native uses an empty userInfo.
	if native != 0 {
		errno := darwin_native_error(native)
		code = match errno {
			2 { i64(4) }
			1, 13 { i64(513) }
			17 { i64(516) }
			28, 69 { i64(640) }
			30 { i64(642) }
			else { i64(512) }
		}
		posix := owned_string('NSPOSIXErrorDomain')
		underlying := ns_error_create(posix, errno, 0)
		objc_release(posix)
		header.keys << owned_string('NSUnderlyingError')
		array_append(mut header, underlying)
		objc_release(underlying)
		header.keys << owned_string('NSURL')
		array_append(mut header, url)
		file_path := owned_string(path)
		header.keys << owned_string('NSFilePath')
		array_append(mut header, file_path)
		objc_release(file_path)
		if atomically && errno == 2 {
			variants := objc_allocate(ios_runtime.names['NSArray'])
			mut variant_header := obj_header(variants)
			folder := owned_string('Folder')
			array_append(mut variant_header, folder)
			objc_release(folder)
			header.keys << owned_string('NSUserStringVariant')
			array_append(mut header, variants)
			objc_release(variants)
		}
	}
	domain := owned_string('NSCocoaErrorDomain')
	defer { objc_release(domain) }
	return ns_error_create(domain, code, info)
}

fn swift_data_write_bytes(fd int, source SwiftStringBytes) i32 {
	mut offset := u64(0)
	for offset < source.count {
		written := C.write(fd, voidptr(source.address + offset), usize(source.count - offset))
		if written < 0 {
			errno := unsafe { *C.ios_errno_address() }
			if errno == C.EINTR { continue }
			return i32(errno)
		}
		if written == 0 { return C.EIO }
		offset += u64(written)
	}
	return 0
}

// All temporary files live beside the destination. Exclusive creation makes
// concurrent writers independent; rename publishes only a complete byte span.
fn swift_data_write_file(path string, source SwiftStringBytes, options u64) i32 {
	mut destination := [1024]u8{}
	unsafe { C.memcpy(&destination[0], path.str, usize(path.len)) }
	target := unsafe { &char(&destination[0]) }
	mut fields := [20]u64{}
	exists := C.ios_stat_info(target, -1, if options == 1 { i32(1) } else { i32(0) }, unsafe { &fields[0] }) == 0
	symlink := exists && fields[1] & 0xf000 == 0xa000
	if options != 2 && exists && fields[1] & 0xf000 != 0x8000 && !(options == 1 && symlink) {
		return if fields[1] & 0xf000 == 0x4000 { i32(C.EISDIR) } else { i32(C.EINVAL) }
	}
	if options != 1 {
		flags := C.O_WRONLY | C.O_CREAT | if options == 2 { C.O_EXCL } else { C.O_TRUNC }
		fd := C.open(target, flags, int(0o666))
		if fd < 0 { return i32(unsafe { *C.ios_errno_address() }) }
		result := swift_data_write_bytes(fd, source)
		closed := C.close(fd)
		if result != 0 { return result }
		return if closed == 0 { i32(0) } else { i32(unsafe { *C.ios_errno_address() }) }
	}
	mut parent_end := 0
	for i, byte in path { if byte == `/` { parent_end = i + 1 } }
	mut temporary := [1080]u8{}
	unsafe { C.memcpy(&temporary[0], path.str, usize(parent_end)) }
	mut fd := -1
	for _ in 0 .. 16 {
		mut random := [16]u8{}
		if C.getentropy(unsafe { &random[0] }, 16) != 0 {
			return i32(unsafe { *C.ios_errno_address() })
		}
		unsafe { C.memcpy(&temporary[parent_end], c'.vinix-data-', 12) }
		for i, byte in random {
			temporary[parent_end + 12 + i * 2] = '0123456789abcdef'[byte >> 4]
			temporary[parent_end + 13 + i * 2] = '0123456789abcdef'[byte & 15]
		}
		fd = C.open(unsafe { &char(&temporary[0]) }, C.O_WRONLY | C.O_CREAT | C.O_EXCL, int(0o666))
		if fd >= 0 { break }
		errno := unsafe { *C.ios_errno_address() }
		if errno != C.EEXIST { return i32(errno) }
	}
	if fd < 0 { return C.EEXIST }
	mut published := false
	defer { if !published { C.unlink(unsafe { &char(&temporary[0]) }) } }
	mut result := swift_data_write_bytes(fd, source)
	if result == 0 && exists && !symlink && C.fchmod(fd, u32(fields[1] & 0o7777)) != 0 {
		result = i32(unsafe { *C.ios_errno_address() })
	}
	closed := C.close(fd)
	if result != 0 { return result }
	if closed != 0 { return i32(unsafe { *C.ios_errno_address() }) }
	if C.rename(unsafe { &char(&temporary[0]) }, target) != 0 {
		return i32(unsafe { *C.ios_errno_address() })
	}
	published = true
	return 0
}

fn swift_data_write_checked(value u64, options u64, first u64, second u64) !u64 {
	if ios_runtime == unsafe { nil } || ios_runtime.swift_concurrency_retired {
		return error('iOS: Swift Data write outside runtime lifetime')
	}
	if options > 2 { return error('iOS: unsupported NSData writing options') }
	scratch := u64(C.__builtin_alloca(16))
	source := swift_data_bytes_checked(first, second, scratch)!
	// Caller owns readable URL and witness spans, as with the public URL bridge.
	// Guest witnesses may reenter; never hold the runtime lock across the bridge.
	bridge := unsafe { SwiftDataURLBridge(voidptr(swift_foundation_arena() + 1088)) }
	url := bridge(value)
	defer { objc_release(url) }
	C.ios_objc_initialize_lock()
	live := url in ios_runtime.objects && read64(url) == ios_runtime.names['NSURL']
	C.ios_objc_initialize_unlock()
	if !live { return error('iOS: Swift Data write requires built-in NSURL') }
	if obj_header(url).number == 1 { return swift_data_write_error(url, '', 0, false) }
	path := ns_file_manager_path(obj_header(url).fields[0])
	result := swift_data_write_file(path, source, options)
	return if result == 0 {
		u64(0)
	} else {
		swift_data_write_error(url, path, result, options == 1)
	}
}

fn swift_data_write(value u64, options u64, first u64, second u64) u64 {
	return swift_data_write_checked(value, options, first, second) or { panic(err) }
}
