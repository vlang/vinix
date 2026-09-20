// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Persistent user-registration record and per-user home-directory setup.
module main

import crypto.scrypt
import encoding.hex
import io.util
import os

const desktop_user_record_name = '.vinix-user'
const desktop_user_record_max_bytes = 1024
const registration_salt_bytes = 16
const registration_hash_bytes = u64(32)
const registration_scrypt_n = u64(16_384)
const registration_scrypt_r = u32(8)
const registration_scrypt_p = u32(1)
const registration_user_home_mode = 0o700

fn registration_zero_and_free(mut value []u8) {
	for i in 0 .. value.len {
		value[i] = 0
	}
	if value.cap > 0 {
		unsafe { value.free() }
	}
	value = []u8{}
}

fn registration_valid_name(name string) bool {
	if name.len == 0 || name.len > registration_max_name {
		return false
	}
	mut visible := false
	for i in 0 .. name.len {
		ch := name[i]
		if ch < 0x20 || ch >= 0x7f {
			return false
		}
		if ch != ` ` {
			visible = true
		}
	}
	return visible
}

fn desktop_user_record_path(home string) string {
	return '${home}/${desktop_user_record_name}'
}

// The system image is disposable while /root is the persistent desktop volume.
// Turn the display name into one portable directory component under that volume.
fn registration_directory_name(name string) string {
	mut bytes := []u8{cap: name.len}
	mut separator := false
	for i in 0 .. name.len {
		ch := name[i]
		if (ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) {
			if separator && bytes.len > 0 {
				bytes << `-`
			}
			bytes << ch
			separator = false
		} else if ch >= `A` && ch <= `Z` {
			if separator && bytes.len > 0 {
				bytes << `-`
			}
			bytes << ch + 32
			separator = false
		} else if bytes.len > 0 {
			separator = true
		}
	}
	if bytes.len == 0 {
		unsafe { bytes.free() }
		return 'user'.clone()
	}
	result := bytes.bytestr()
	unsafe { bytes.free() }
	return result
}

fn desktop_user_home_path(home string, name string) string {
	directory := registration_directory_name(name)
	path := '${home}/${directory}'
	unsafe { directory.free() }
	return path
}

// Registration is still a single-user desktop, but it has a real persistent
// home directory. Profiles created by the first implementation repair their
// missing directory here the next time the desktop starts.
fn desktop_ensure_user_directory(home string, name string) bool {
	path := desktop_user_home_path(home, name)
	defer { unsafe { path.free() } }
	info := os.lstat(path) or {
		os.mkdir(path) or { return false }
		os.chmod(path, registration_user_home_mode) or {
			os.rmdir(path) or {}
			return false
		}
		$if vinix {
			// Vinix's persistent /root is a separate block-backed filesystem.
			// Make a repaired directory durable even when no profile write follows.
			C.sync()
		}
		return true
	}
	if info.get_filetype() != .directory {
		return false
	}
	os.chmod(path, registration_user_home_mode) or { return false }
	return true
}

// A valid profile is the registration marker. Keep enough information for a
// later login screen to verify the password without ever storing it directly.
fn desktop_load_user_name(home string) ?string {
	if home == '' {
		return none
	}
	path := desktop_user_record_path(home)
	defer { unsafe { path.free() } }
	info := os.lstat(path) or { return none }
	if info.get_filetype() != .regular || info.size == 0
		|| info.size > u64(desktop_user_record_max_bytes) || info.mode & 0o077 != 0 {
		return none
	}
	record := os.read_file(path) or { return none }
	if record.len == 0 || record.len > desktop_user_record_max_bytes {
		unsafe { record.free() }
		return none
	}
	clean := record.trim_space()
	unsafe { record.free() }
	lines := clean.split_into_lines()
	defer {
		unsafe {
			lines.free()
			clean.free()
		}
	}
	if lines.len != 8 || lines[0] != 'version=1' || !lines[1].starts_with('name=')
		|| lines[2] != 'kdf=scrypt' || lines[3] != 'n=16384' || lines[4] != 'r=8'
		|| lines[5] != 'p=1' || !lines[6].starts_with('salt=')
		|| !lines[7].starts_with('hash=') {
		return none
	}
	name_bytes := hex.decode(lines[1][5..]) or { return none }
	defer { unsafe { name_bytes.free() } }
	name := name_bytes.bytestr()
	if !registration_valid_name(name) {
		unsafe { name.free() }
		return none
	}
	salt := hex.decode(lines[6][5..]) or {
		unsafe { name.free() }
		return none
	}
	defer { unsafe { salt.free() } }
	digest := hex.decode(lines[7][5..]) or {
		unsafe { name.free() }
		return none
	}
	defer { unsafe { digest.free() } }
	if salt.len != registration_salt_bytes || digest.len != int(registration_hash_bytes) {
		unsafe { name.free() }
		return none
	}
	return name
}

fn desktop_user_registered(home string) bool {
	name := desktop_load_user_name(home) or { return false }
	ok := desktop_ensure_user_directory(home, name)
	unsafe { name.free() }
	return ok
}

fn registration_random_bytes(count int) ?[]u8 {
	mut file := os.open('/dev/urandom') or { return none }
	defer { file.close() }
	mut bytes := []u8{len: count}
	mut offset := 0
	for offset < bytes.len {
		read := file.read(mut bytes[offset..]) or {
			registration_zero_and_free(mut bytes)
			return none
		}
		if read <= 0 {
			registration_zero_and_free(mut bytes)
			return none
		}
		offset += read
	}
	return bytes
}

fn desktop_save_user(home string, name string, password []u8) bool {
	if home == '' || !os.is_dir(home) || !registration_valid_name(name) || password.len == 0 {
		return false
	}
	if !desktop_ensure_user_directory(home, name) {
		return false
	}
	mut salt := registration_random_bytes(registration_salt_bytes) or { return false }
	mut digest := scrypt.scrypt(password, salt, registration_scrypt_n, registration_scrypt_r,
		registration_scrypt_p, registration_hash_bytes) or {
		registration_zero_and_free(mut salt)
		return false
	}
	name_bytes := name.bytes()
	name_hex := hex.encode(name_bytes)
	unsafe { name_bytes.free() }
	salt_hex := hex.encode(salt)
	hash_hex := hex.encode(digest)
	registration_zero_and_free(mut salt)
	registration_zero_and_free(mut digest)

	record := 'version=1\nname=${name_hex}\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=${salt_hex}\nhash=${hash_hex}\n'
	path := desktop_user_record_path(home)
	defer { unsafe { path.free() } }
	mut file, temporary := util.temp_file(path: home, pattern: '${desktop_user_record_name}.*') or {
		return false
	}
	mut published := false
	defer {
		file.close()
		if !published {
			os.rm(temporary) or {}
		}
		unsafe { temporary.free() }
	}
	os.chmod(temporary, 0o600) or { return false }
	file.set_unbuffered()
	file.write_string(record) or { return false }
	if !desktop_preferences_fsync(file.fd) {
		return false
	}
	os.rename_dir(temporary, path) or { return false }
	published = true
	if !desktop_preferences_sync_directory(home, file.fd) {
		os.rm(path) or {}
		return false
	}
	return true
}
