// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <sys/xattr.h>
}
fn C.setxattr(&char, &char, voidptr, usize, u32, int) int
fn C.removexattr(&char, &char, int) int

// Foundation's binary plist string "com.apple.backupd", measured on disk.
// Linux requires the user namespace; the payload and follow-symlink behavior
// are identical. Store it on the file, so fresh NSURL objects see the change.
const ns_url_backup_data = [u8(0x62), 0x70, 0x6c, 0x69, 0x73, 0x74, 0x30, 0x30,
	0x5f, 0x10, 0x11, 0x63, 0x6f, 0x6d, 0x2e, 0x61, 0x70, 0x70, 0x6c, 0x65,
	0x2e, 0x62, 0x61, 0x63, 0x6b, 0x75, 0x70, 0x64, 0x08, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x1c]!

fn ns_url_backup_bool(value u64) bool {
	if value == 0 { return false }
	if objc_is_kind(value, ios_runtime.names['NSNumber']) {
		header := obj_header(value)
		return if header.is_real { header.real_number != 0 } else { header.number != 0 }
	}
	if objc_is_kind(value, ios_runtime.names['NSString']) {
		text := string_text(value)
		mut start := 0
		for start < text.len && text[start].is_space() { start++ }
		if start == text.len { return false }
		if text[start] in [`Y`, `y`, `T`, `t`] { return true }
		if text[start] in [`+`, `-`] { start++ }
		for start < text.len && text[start] == `0` { start++ }
		return start < text.len && text[start] >= `1` && text[start] <= `9`
	}
	panic('iOS: URL backup flag requires a boolean value')
}

fn ns_url_resource_error(output u64, url u64, path string, native int) {
	if output == 0 { return }
	underlying_domain := owned_string('NSOSStatusErrorDomain')
	underlying := ns_error_create(underlying_domain, 100000 + darwin_native_error(native), 0)
	objc_release(underlying_domain)
	info := objc_allocate(ios_runtime.names['NSDictionary'])
	mut header := obj_header(info)
	header.keys << owned_string('NSURL')
	array_append(mut header, url)
	header.keys << owned_string('NSFilePath')
	path_object := owned_string(path)
	array_append(mut header, path_object)
	objc_release(path_object)
	header.keys << owned_string('NSUnderlyingError')
	array_append(mut header, underlying)
	objc_release(underlying)
	domain := owned_string('NSCocoaErrorDomain')
	error_object := ns_error_create(domain, 512, info)
	objc_release(domain)
	objc_release(info)
	unsafe { *(&u64(output)) = objc_autorelease(error_object) }
}

fn ns_url_set_resource(url u64, value u64, key u64, error_output u64) bool {
	// Native Foundation ignores HTTP URLs, unknown keys and read-only keys.
	if obj_header(url).number == 1 { return true }
	if key == 0 || !objc_is_kind(key, ios_runtime.names['NSString']) {
		panic('iOS: URL resource key requires NSString')
	}
	if string_text(key) != 'NSURLIsExcludedFromBackupKey' { return true }
	flag := ns_url_backup_bool(value)
	path := ns_file_manager_path(obj_header(url).fields[0])
	mut buffer := [1024]u8{}
	unsafe { C.memcpy(&buffer[0], path.str, usize(path.len)) }
	mut result := -1
	$if macos {
		name := c'com.apple.metadata:com_apple_backup_excludeItem'
		result = if flag {
			C.setxattr(unsafe { &char(&buffer[0]) }, name, unsafe { &ns_url_backup_data[0] }, usize(ns_url_backup_data.len), 0, 0)
		} else { C.removexattr(unsafe { &char(&buffer[0]) }, name, 0) }
	} $else $if linux {
		name := c'user.com.apple.metadata:com_apple_backup_excludeItem'
		result = if flag {
			int(C.syscall(C.SYS_setxattr, unsafe { &buffer[0] }, name, unsafe { &ns_url_backup_data[0] }, ns_url_backup_data.len, 0))
		} else { int(C.syscall(C.SYS_removexattr, unsafe { &buffer[0] }, name)) }
	} $else { panic('iOS: URL resource filesystem is unsupported') }
	if result == 0 { return true }
	native := unsafe { *C.ios_errno_address() }
	if !flag {
		$if macos { if native == C.ENOATTR { return true } }
		$if linux { if native == C.ENODATA { return true } }
	}
	ns_url_resource_error(error_output, url, path, native)
	return false
}
