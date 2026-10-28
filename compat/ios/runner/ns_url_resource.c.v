// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <sys/xattr.h>
}
fn C.setxattr(&char, &char, voidptr, usize, u32, int) int
fn C.removexattr(&char, &char, int) int
fn C.getxattr(&char, &char, voidptr, usize, u32, int) i64
#include <sys/statvfs.h>
struct C.statvfs {
	f_bsize usize
	f_frsize usize
	f_blocks u64
	f_bavail u64
}
fn C.statvfs(&char, &C.statvfs) int

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
	if result == 0 { ns_url_resource_clear(url, 2); return true }
	native := unsafe { *C.ios_errno_address() }
	if !flag {
		$if macos { if native == C.ENOATTR { ns_url_resource_clear(url, 2); return true } }
		$if linux { if native == C.ENODATA { ns_url_resource_clear(url, 2); return true } }
	}
	ns_url_resource_error(error_output, url, path, native)
	return false
}

fn ns_url_resource_index(key u64) int {
	if key == 0 || !objc_is_kind(key, ios_runtime.names['NSString']) { panic('iOS: URL resource key requires NSString') }
	return match string_text(key) {
		'NSURLCreationDateKey' { 0 }
		'NSURLFileSizeKey' { 1 }
		'NSURLIsExcludedFromBackupKey' { 2 }
		'NSURLIsRegularFileKey' { 3 }
		'NSURLVolumeAvailableCapacityForImportantUsageKey' { 4 }
		'NSURLVolumeAvailableCapacityKey' { 5 }
		'NSURLVolumeTotalCapacityKey' { 6 }
		else { -2 }
	}
}

fn ns_url_resource_clear(url u64, index int) {
	mut retired := [7]u64{}
	C.ios_objc_initialize_lock()
	mut header := obj_header(url)
	if header.url_resource_generation == ~u64(0) { panic('iOS: URL resource cache generation overflow') }
	header.url_resource_generation++
	for i in 0 .. 7 {
		if index >= 0 && i != index { continue }
		retired[i] = header.url_resource_values[i]
		header.url_resource_values[i] = 0
		header.url_resource_mask &= ~u8(1 << i)
	}
	C.ios_objc_initialize_unlock()
	for value in retired { objc_release(value) }
}

fn ns_url_resource_dispose(mut header ObjHeader) {
	// Allocation-owned state must also retire after object_setClass.
	retired := header.url_resource_values
	header.url_resource_values = [7]u64{}
	header.url_resource_mask = 0
	for value in retired { objc_release(value) }
}

fn ns_url_resource_read_error(output u64, url u64, path string, native int) {
	if output == 0 { return }
	code := darwin_native_error(native)
	posix_domain := owned_string('NSPOSIXErrorDomain')
	underlying := ns_error_create(posix_domain, code, 0)
	objc_release(posix_domain)
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
	cocoa_code := if code in [2, 20] { 260 } else if code in [1, 13] { 257 } else { 256 }
	error_object := ns_error_create(domain, cocoa_code, info)
	objc_release(domain)
	objc_release(info)
	unsafe { *(&u64(output)) = objc_autorelease(error_object) }
}

// Return an owned value, or an errno. A successful nil is meaningful: some
// properties are unavailable on a directory or on a filesystem without btime.
fn ns_url_resource_read(path &char, index int) (u64, int) {
	if index == 2 {
		mut n := i64(-1)
		$if macos {
			n = C.getxattr(path, c'com.apple.metadata:com_apple_backup_excludeItem', unsafe { nil }, 0, 0, 0)
		} $else $if linux {
			n = C.syscall(C.SYS_getxattr, path, c'user.com.apple.metadata:com_apple_backup_excludeItem', unsafe { nil }, 0)
		}
		// Foundation treats every nonempty payload as exclusion, including
		// plain text and unrelated/invalid plist values. A size query bounds
		// memory and avoids racing the attribute between length and data reads.
		excluded := n > 0
		if n < 0 {
			native := unsafe { *C.ios_errno_address() }
			$if macos { if native !in [C.ENOATTR, C.ENOENT, C.ENOTDIR] { return 0, native } }
			$if linux { if native !in [C.ENODATA, C.ENOENT, C.ENOTDIR] { return 0, native } }
		}
		return objc_retain(framework_object(if excluded { '_kCFBooleanTrue' } else { '_kCFBooleanFalse' })), 0
	}
	mut fields := [20]u64{}
	if C.ios_stat_info(path, -1, 1, unsafe { &fields[0] }) != 0 { return 0, unsafe { *C.ios_errno_address() } }
	kind := fields[1] & 0xf000
	if index == 0 {
		$if macos { return cf_date_create(0, f64(i64(fields[13])) - 978307200.0 + f64(fields[14]) / 1e9), 0 }
		// Vinix's current stat ABI does not expose a birth timestamp.
		return 0, 0
	}
	if index == 1 { return if kind in [u64(0x8000), 0xa000] { cookie_integer(i64(fields[15])) } else { u64(0) }, 0 }
	if index == 3 { return objc_retain(framework_object(if kind == 0x8000 { '_kCFBooleanTrue' } else { '_kCFBooleanFalse' })), 0 }
	mut filesystem := C.statvfs{}
	mut volume_path := path
	mut parent := [1024]u8{}
	if kind == 0xa000 {
		// statvfs follows links; ask for the link's containing filesystem even
		// for a dangling link or a target on another mounted filesystem.
		text := unsafe { path.vstring() }
		mut end := text.len - 1
		for end > 0 && text[end] != `/` { end-- }
		if end == 0 { parent[0] = `/` } else { unsafe { C.memcpy(&parent[0], path, usize(end)) } }
		volume_path = unsafe { &char(&parent[0]) }
	}
	if C.statvfs(volume_path, &filesystem) != 0 { return 0, unsafe { *C.ios_errno_address() } }
	unit := if filesystem.f_frsize != 0 { u64(filesystem.f_frsize) } else { u64(filesystem.f_bsize) }
	blocks := if index == 6 { filesystem.f_blocks } else { filesystem.f_bavail }
	if unit != 0 && blocks > u64(0x7fffffffffffffff) / unit { return 0, C.EOVERFLOW }
	// No reclaimable/purgeable storage policy exists in Vinix; important usage
	// has the same genuinely available bytes as ordinary usage.
	return cookie_integer(i64(blocks * unit)), 0
}

fn ns_url_get_resource(url u64, output u64, key u64, error_output u64) bool {
	if output == 0 { panic('iOS: URL resource value output is required') }
	index := ns_url_resource_index(key)
	objc_retain(url)
	defer { objc_release(url) }
	if index < 0 || obj_header(url).number == 1 { unsafe { *(&u64(output)) = 0 }; return true }
	mut path_buffer := [1024]u8{}
	C.ios_objc_initialize_lock()
	mut header := obj_header(url)
	bit := u8(1 << index)
	if header.url_resource_mask & bit != 0 {
		value := objc_retain(header.url_resource_values[index])
		C.ios_objc_initialize_unlock()
		unsafe { *(&u64(output)) = objc_autorelease(value) }
		return true
	}
	generation := header.url_resource_generation
	path := ns_file_manager_path(header.fields[0])
	unsafe { C.memcpy(&path_buffer[0], path.str, usize(path.len)) }
	C.ios_objc_initialize_unlock()
	value, native := ns_url_resource_read(unsafe { &char(&path_buffer[0]) }, index)
	if native != 0 {
		ns_url_resource_read_error(error_output, url, unsafe { (&char(&path_buffer[0])).vstring() }, native)
		return false
	}
	// Constructors may reenter and invalidate the cache. Never hold the state
	// lock across allocation callbacks, error construction, or releases.
	C.ios_objc_initialize_lock()
	mut result := value
	mut discarded := false
	if header.url_resource_generation == generation {
		if header.url_resource_mask & bit != 0 {
			result = objc_retain(header.url_resource_values[index])
			discarded = true
		} else {
			header.url_resource_values[index] = objc_retain(value)
			header.url_resource_mask |= bit
		}
	}
	C.ios_objc_initialize_unlock()
	if discarded { objc_release(value) }
	unsafe { *(&u64(output)) = objc_autorelease(result) }
	return true
}
