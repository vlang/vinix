// SPDX-License-Identifier: GPL-2.0-or-later
// Local generic-password storage. This is a per-user, app-namespaced store,
// not Apple's data-protection service or a sandbox between same-uid apps.
module main

import os
import plist

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <unistd.h>

fn C.openat(int, &char, int, ...int) int
fn C.mkdir(&char, u32) int
fn C.fstat(int, &C.stat) int
fn C.fsync(int) int
fn C.flock(int, int) int
fn C.renameat(int, &char, int, &char) int
fn C.unlinkat(int, &char, int) int
fn C.ios_secure_zero(voidptr, usize)

const keychain_limit = 1048576

// Only the subset EOSSDK uses, plus data/attribute and one/all result shapes.
// Policy-bearing unsupported keys are never silently discarded.
fn keychain_attribute(key string) bool {
	return key in ['svce', 'acct', 'desc', 'labl', 'type', 'gena', 'pdmn', 'v_Data']
}

fn keychain_get(dictionary u64, key string) u64 {
	header := obj_header(dictionary)
	for i, object in header.keys { if string_text(object) == key { return header.items[i] } }
	return 0
}

fn keychain_number(value u64) bool {
	return objc_is_kind(value, ios_runtime.names['NSNumber']) && !obj_header(value).is_real
}

fn keychain_validate(dictionary u64, operation int) int {
	// 0=copy, 1=add, 2=update/delete query, 3=update attributes, 4=stored item.
	if dictionary == 0 || !objc_is_kind(dictionary, ios_runtime.names['NSDictionary']) { return -50 }
	header := obj_header(dictionary)
	if header.cf_raw_keys || header.cf_raw_values || header.keys.len > 32 { return -50 }
	for i, key in header.keys {
		if !objc_is_kind(key, ios_runtime.names['NSString']) { return -50 }
		name := string_text(key)
		value := header.items[i]
		if name == 'class' {
			if operation == 3 { return -50 }
			if !objc_is_kind(value, ios_runtime.names['NSString']) { return -50 }
			if string_text(value) != 'genp' { return -4 } // errSecUnimplemented
		} else if keychain_attribute(name) {
			if name in ['v_Data', 'gena'] {
				if !objc_is_kind(value, ios_runtime.names['NSData']) || data_length(value) > 65536 { return -50 }
				if name == 'v_Data' && operation in [0, 2] { return -50 }
			} else if name == 'type' {
				if !keychain_number(value) || obj_header(value).number < 0 || obj_header(value).number > 0xffffffff { return -50 }
			} else {
				if !objc_is_kind(value, ios_runtime.names['NSString']) || string_text(value).len > 4096 { return -50 }
				if name == 'pdmn' && string_text(value) !in ['ck', 'cku'] { return -4 }
			}
		} else if name == 'agrp' { return -34018 } // No shared-access-group entitlement service.
		else if name in ['sync', 'nleg'] {
			if operation in [3, 4] || !keychain_number(value) { return -50 }
			if obj_header(value).number != 0 { return -4 }
		} else if name == 'u_AuthUI' {
			if operation in [3, 4] { return -50 }
			if !objc_is_kind(value, ios_runtime.names['NSString']) { return -50 }
			if string_text(value) != 'u_AuthUIS' { return -4 }
		} else if name == 'm_Limit' {
			if operation != 0 { return -50 }
			if !objc_is_kind(value, ios_runtime.names['NSString']) || string_text(value) !in ['m_LimitOne', 'm_LimitAll'] { return -50 }
		} else if name in ['r_Data', 'r_Attributes'] {
			if operation !in [0, 1] || !keychain_number(value) { return -50 }
		} else if name in ['r_Ref', 'r_PersistentRef', 'accc', 'v_Ref', 'v_PersistentRef'] { return -4 }
		else { return -50 }
	}
	if operation != 3 && keychain_get(dictionary, 'class') == 0 { return -50 }
	if operation in [1, 4] {
		// iOS's default WhenUnlocked needs a lock-state service we do not have.
		if keychain_get(dictionary, 'pdmn') == 0 { return -4 }
	}
	return 0
}

fn keychain_copy(dictionary u64, attributes_only bool) u64 {
	copied := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	header := obj_header(dictionary)
	for i, key in header.keys {
		name := string_text(key)
		if !keychain_attribute(name) && name != 'class' { continue }
		if attributes_only && name == 'v_Data' { continue }
		value := header.items[i]
		mut clone := u64(0)
		if objc_is_kind(value, ios_runtime.names['NSData']) {
			clone = cf_data_create(0, data_pointer(value), i64(data_length(value)))
		} else if objc_is_kind(value, ios_runtime.names['NSString']) {
			text := string_text(value)
			clone = cf_string_bytes(0, u64(text.str), text.len, 0x08000100, false)
		} else {
			clone = objc_allocate(ios_runtime.names['NSNumber'])
			mut number := obj_header(clone)
			number.number = obj_header(value).number
		}
		dictionary_put(copied, key, clone)
		objc_release(clone)
	}
	return objc_autorelease(copied)
}

fn keychain_matches(item u64, query u64) bool {
	header := obj_header(query)
	for i, key in header.keys {
		name := string_text(key)
		if keychain_attribute(name) && !object_equal(keychain_get(item, name), header.items[i]) { return false }
	}
	return true
}

fn keychain_same_identity(a u64, b u64) bool {
	for name in ['svce', 'acct']! {
		x := keychain_get(a, name)
		y := keychain_get(b, name)
		// Omitted service/account have the same identity as an empty string.
		if string_text(x) != string_text(y) { return false }
	}
	return true
}

fn keychain_private_fd(fd int, directory bool) bool {
	mut info := C.stat{}
	if fd < 0 || C.fstat(fd, &info) != 0 || info.st_uid != C.getuid() { return false }
	kind := if directory { C.S_IFDIR } else { C.S_IFREG }
	mode := if directory { 0o700 } else { 0o600 }
	return int(info.st_mode) & C.S_IFMT == kind && int(info.st_mode) & 0o7777 == mode
		&& (directory || info.st_nlink == 1)
}

fn keychain_directory() ?int {
	mut identifier := os.file_name(ios_runtime.bundle)
	defer { unsafe { identifier.free() } }
	info_path := os.join_path(ios_runtime.bundle, 'Info.plist')
	defer { unsafe { info_path.free() } }
	if os.is_file(info_path) {
		bytes := os.read_bytes(info_path) or { return none }
		defer { unsafe { bytes.free() } }
		info := plist.parse(bytes) or { return none }
		defer { info.free() }
		identity := info.fields['CFBundleIdentifier'] or { return none }
		if identity.kind != .string { return none }
		unsafe { identifier.free() }
		identifier = identity.text.clone()
	}
	if identifier == '' || identifier.len > 255 || identifier in ['.', '..'] { return none }
	for c in identifier {
		if !((c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c in [u8(`.`), `-`, `_`]) { return none }
	}
	configured := os.getenv('VINIX_IOS_KEYCHAIN')
	defer { unsafe { configured.free() } }
	mut root := configured.clone()
	if root == '' {
		documents := os.getenv('VINIX_IOS_DOCUMENTS')
		defer { unsafe { documents.free() } }
		bundle_parent := os.dir(ios_runtime.bundle)
		defer { unsafe { bundle_parent.free() } }
		directory := if documents != '' { documents.clone() } else { os.join_path(bundle_parent, 'Documents') }
		defer { unsafe { directory.free() } }
		parent := os.join_path(directory, 'Library')
		defer { unsafe { parent.free() } }
		os.mkdir_all(parent) or { return none }
		root = os.join_path(parent, 'Keychains')
	}
	defer { unsafe { root.free() } }
	if C.mkdir(&char(root.str), 0o700) != 0 && C.errno != C.EEXIST { return none }
	parent_fd := C.open(&char(root.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	defer { if parent_fd >= 0 { C.close(parent_fd) } }
	if !keychain_private_fd(parent_fd, true) { return none }
	// mkdirat keeps the application directory relative to the verified parent.
	if C.mkdirat(parent_fd, &char(identifier.str), 0o700) != 0 && C.errno != C.EEXIST { return none }
	fd := C.openat(parent_fd, &char(identifier.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if !keychain_private_fd(fd, true) { if fd >= 0 { C.close(fd) }; return none }
	return fd
}

fn C.mkdirat(int, &char, u32) int

fn keychain_read(fd int, bytes &u8, length int) bool {
	mut offset := 0
	for offset < length {
		count := C.read(fd, unsafe { bytes + offset }, usize(length - offset))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return false }
		offset += int(count)
	}
	return true
}

fn keychain_write(fd int, bytes []u8) bool {
	mut offset := 0
	for offset < bytes.len {
		count := C.write(fd, unsafe { &u8(bytes.data) + offset }, usize(bytes.len - offset))
		if count < 0 && C.errno == C.EINTR { continue }
		if count <= 0 { return false }
		offset += int(count)
	}
	return C.fsync(fd) == 0
}

fn keychain_replace(directory int, name &char, bytes []u8) bool {
	// All callers hold the stable lock file. Remove only the private temporary
	// name, never open a preexisting temporary or follow a symlink.
	C.unlinkat(directory, c'items.tmp', 0)
	fd := C.openat(directory, c'items.tmp', C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return false }
	defer { C.close(fd); C.unlinkat(directory, c'items.tmp', 0) }
	if !keychain_private_fd(fd, false) || !keychain_write(fd, bytes) { return false }
	return C.renameat(directory, c'items.tmp', directory, name) == 0 && C.fsync(directory) == 0
}

fn keychain_key(directory int, key &u8) bool {
	fd := C.openat(directory, c'key', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if fd >= 0 {
		defer { C.close(fd) }
		mut info := C.stat{}
		return keychain_private_fd(fd, false) && C.fstat(fd, &info) == 0 && info.st_size == 64 && keychain_read(fd, key, 64)
	}
	if C.errno != C.ENOENT { return false }
	// A missing key for an existing store is damage, not a new empty keychain.
	stored := C.openat(directory, c'items', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if stored >= 0 { C.close(stored); return false }
	if C.errno != C.ENOENT || sec_random_copy(0, 64, key) != 0 { return false }
	return keychain_replace(directory, c'key', unsafe { key.vbytes(64) })
}

fn keychain_load(directory int, key []u8) ?u64 {
	fd := C.openat(directory, c'items', C.O_RDONLY | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK)
	if fd < 0 {
		if C.errno == C.ENOENT { return objc_autorelease(objc_allocate(ios_runtime.names['NSArray'])) }
		return none
	}
	defer { C.close(fd) }
	mut info := C.stat{}
	if !keychain_private_fd(fd, false) || C.fstat(fd, &info) != 0 || info.st_size < 72 || info.st_size > keychain_limit { return none }
	mut bytes := []u8{len: int(info.st_size)}
	defer { unsafe { bytes.free() } }
	if !keychain_read(fd, bytes.data, bytes.len) || C.memcmp(bytes.data, c'VNXKCH01', 8) != 0 || (bytes.len - 56) % 16 != 0 { return none }
	mut tag := [32]u8{}
	cc_hmac(2, unsafe { &u8(key.data) + 32 }, 32, bytes.data, u64(bytes.len - 32), unsafe { &tag[0] })
	mut difference := u8(0)
	for i in 0 .. 32 { difference |= tag[i] ^ bytes[bytes.len - 32 + i] }
	if difference != 0 { return none }
	// Authenticate before decrypting; require strict padding independently of
	// CommonCrypto's legacy one-byte unpadding behavior.
	mut plain := []u8{len: bytes.len - 56}
	defer { C.ios_secure_zero(plain.data, usize(plain.len)); unsafe { plain.free() } }
	mut moved := u64(0)
	if cc_crypt(1, 0, 0, key.data, 32, unsafe { &u8(bytes.data) + 8 }, unsafe { &u8(bytes.data) + 24 }, u64(plain.len), plain.data, u64(plain.len), &moved) != 0 { return none }
	padding := int(plain.last())
	if padding < 1 || padding > 16 || padding > plain.len { return none }
	for i in plain.len - padding .. plain.len { if plain[i] != padding { return none } }
	input := unsafe { plain.data.vbytes(plain.len - padding) }
	value := plist.parse(input) or { return none }
	defer { value.free() }
	if value.kind != .array || value.values.len > 256 { return none }
	items := plist_object(value)
	for item in obj_header(items).items { if keychain_validate(item, 4) != 0 { return none } }
	return items
}

fn keychain_save(directory int, key []u8, items u64) bool {
	value := object_plist(items, 0) or { return false }
	defer { value.free() }
	text := plist.encode_xml(value) or { return false }
	defer { C.ios_secure_zero(text.str, usize(text.len)); unsafe { text.free() } }
	length := text.len - text.len % 16 + 16
	if length + 56 > keychain_limit { return false }
	mut bytes := []u8{len: length + 56}
	defer { unsafe { bytes.free() } }
	unsafe { C.memcpy(bytes.data, c'VNXKCH01', 8) }
	if sec_random_copy(0, 16, unsafe { &u8(bytes.data) + 8 }) != 0 { return false }
	mut moved := u64(0)
	if cc_crypt(0, 0, 1, key.data, 32, unsafe { &u8(bytes.data) + 8 }, text.str, u64(text.len), unsafe { &u8(bytes.data) + 24 }, u64(length), &moved) != 0 || moved != u64(length) { return false }
	cc_hmac(2, unsafe { &u8(key.data) + 32 }, 32, bytes.data, u64(bytes.len - 32), unsafe { &u8(bytes.data) + bytes.len - 32 })
	return keychain_replace(directory, c'items', bytes)
}

fn keychain_result(item u64, query u64) u64 {
	data_flag := keychain_get(query, 'r_Data')
	attributes_flag := keychain_get(query, 'r_Attributes')
	data := data_flag != 0 && obj_header(data_flag).number != 0
	attributes := attributes_flag != 0 && obj_header(attributes_flag).number != 0
	if attributes {
		copied := keychain_copy(item, !data)
		objc_set_class(copied, ios_runtime.names['NSDictionary'])
		return objc_retain(copied)
	}
	if data {
		value := keychain_get(item, 'v_Data')
		return if value != 0 { cf_data_create(0, data_pointer(value), i64(data_length(value))) } else { cf_data_create(0, 0, 0) }
	}
	return 0
}

fn keychain_operation(query u64, changes u64, result &u64, operation int) int {
	if result != unsafe { nil } { unsafe { *result = 0 } }
	pool := objc_pool_push()
	defer { objc_pool_pop(pool) }
	status := keychain_validate(query, if operation == 0 { 0 } else if operation == 1 { 1 } else { 2 })
	if status != 0 { return status }
	if operation == 2 {
		valid := keychain_validate(changes, 3)
		if valid != 0 { return valid }
	}
	directory := keychain_directory() or { return -25291 } // errSecNotAvailable
	defer { C.close(directory) }
	lock_fd := C.openat(directory, c'lock', C.O_RDWR | C.O_CREAT | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600)
	if lock_fd < 0 { return -25291 }
	defer { C.close(lock_fd) }
	if !keychain_private_fd(lock_fd, false) { return -25291 }
	for C.flock(lock_fd, C.LOCK_EX) != 0 { if C.errno != C.EINTR { return -25291 } }
	defer { C.flock(lock_fd, C.LOCK_UN) }
	mut key_bytes := [64]u8{}
	key := unsafe { (&key_bytes[0]).vbytes(64) }
	defer { C.ios_secure_zero(unsafe { &key_bytes[0] }, 64) }
	if !keychain_key(directory, unsafe { &key_bytes[0] }) { return -25291 }
	items := keychain_load(directory, key) or { return -26275 } // errSecDecode; never reset corrupt data.
	mut header := obj_header(items)
	if operation == 1 {
		for item in header.items { if keychain_same_identity(item, query) { return -25299 } }
		if header.items.len >= 256 { return -34 } // errSecDiskFull
		item := keychain_copy(query, false)
		for name in ['_kSecAttrService', '_kSecAttrAccount']! {
			attribute := read64(security_constant(name) or { panic('iOS: missing keychain identity constant') })
			if cf_dictionary_value(item, attribute) == 0 { dictionary_put(item, attribute, make_string(c'')) }
		}
		array_append(mut header, item)
		if !keychain_save(directory, key, items) { return -36 } // errSecIO
		if result != unsafe { nil } { unsafe { *result = keychain_result(item, query) } }
		return 0
	}
	mut matched := 0
	mut returned := u64(0)
	all_value := keychain_get(query, 'm_Limit')
	all := operation == 0 && all_value != 0 && string_text(all_value) == 'm_LimitAll'
	if all { returned = objc_allocate(ios_runtime.names['NSArray']) }
	mut transferred := false
	defer { if !transferred { objc_release(returned) } }
	mut index := 0
	for index < header.items.len {
		item := header.items[index]
		if !keychain_matches(item, query) { index++; continue }
		matched++
		if operation == 0 {
			if result != unsafe { nil } {
				value := keychain_result(item, query)
				if all && value != 0 { mut array := obj_header(returned); array_append(mut array, value); objc_release(value) }
				else if !all { returned = value }
			}
			if !all { break }
		} else if operation == 2 {
			copied := keychain_copy(item, false)
			updates := obj_header(changes)
			for i, key_object in updates.keys { dictionary_put(copied, key_object, updates.items[i]) }
			// All changes are staged in memory; any collision aborts the entire
			// operation before replacing the persistent file.
			for j, other in header.items { if j != index && keychain_same_identity(copied, other) { return -25299 } }
			objc_store_strong(unsafe { &header.items[index] }, copied)
		} else { collection_remove(mut header, index); continue }
		index++
	}
	if matched == 0 { return -25300 }
	if operation != 0 && !keychain_save(directory, key, items) { return -36 }
	if operation == 0 && result != unsafe { nil } {
		// No return flag means no object, even when matchLimitAll is selected.
		if all && obj_header(returned).items.len == 0 { objc_release(returned); returned = 0 }
		unsafe { *result = returned }
		transferred = true
	}
	return 0
}

fn sec_item_copy(query u64, result &u64) int { return keychain_operation(query, 0, result, 0) }
fn sec_item_add(query u64, result &u64) int { return keychain_operation(query, 0, result, 1) }
fn sec_item_update(query u64, changes u64) int { return keychain_operation(query, changes, unsafe { nil }, 2) }
fn sec_item_delete(query u64) int { return keychain_operation(query, 0, unsafe { nil }, 3) }
