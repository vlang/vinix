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
const registration_user_folder_mode = 0o755

// Users' homes are named /home/<user>. Only /root is on persistent storage in
// every layout, so the folders themselves are kept in /root/home/<user>.
const desktop_users_directory = '/home'
const desktop_user_store_name = 'home'
const desktop_user_dirs_name = '.config/user-dirs.dirs'

struct DesktopUserFolder {
	name string
	xdg  string
}

// The folders every home starts with, and their names in XDG user-dirs.dirs.
const desktop_user_folders = [
	DesktopUserFolder{ name: 'Desktop', xdg: 'XDG_DESKTOP_DIR' },
	DesktopUserFolder{ name: 'Documents', xdg: 'XDG_DOCUMENTS_DIR' },
	DesktopUserFolder{ name: 'Downloads', xdg: 'XDG_DOWNLOAD_DIR' },
	DesktopUserFolder{ name: 'Music', xdg: 'XDG_MUSIC_DIR' },
	DesktopUserFolder{ name: 'Pictures', xdg: 'XDG_PICTURES_DIR' },
	DesktopUserFolder{ name: 'Videos', xdg: 'XDG_VIDEOS_DIR' },
]

// The home the Desktop and Files show, /home/<user>. Set once the user exists:
// see desktop_use_user_home.
__global desktop_user_home = ''

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

// Turn the display name into one portable directory component: the <user> in
// /home/<user>.
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

// The name the user's home is shown under, below `users` (/home).
fn desktop_user_home_path(users string, name string) string {
	directory := registration_directory_name(name)
	path := '${users}/${directory}'
	unsafe { directory.free() }
	return path
}

// Where the user's home is actually kept, below the persistent `home` (/root).
// It has a directory of its own so that no name, such as the desktop's source
// tree in /root/desktop, can be taken for a user's home.
fn desktop_user_storage_path(home string, name string) string {
	directory := registration_directory_name(name)
	path := '${home}/${desktop_user_store_name}/${directory}'
	unsafe { directory.free() }
	return path
}

// Make `path` a directory unless it is one already. The result says whether
// this call made it, so the caller knows there is something to make durable.
fn registration_ensure_directory(path string, mode int) ?bool {
	info := os.lstat(path) or {
		os.mkdir(path) or { return none }
		os.chmod(path, mode) or {
			os.rmdir(path) or {}
			return none
		}
		return true
	}
	if info.get_filetype() != .directory {
		return none
	}
	return false
}

// Registration is still a single-user desktop, but it has a real persistent
// home directory with the usual folders in it. Profiles created by earlier
// implementations repair what they are missing here the next time the desktop
// starts.
fn desktop_ensure_user_directory(home string, name string) bool {
	store := '${home}/${desktop_user_store_name}'
	defer { unsafe { store.free() } }
	path := desktop_user_storage_path(home, name)
	defer { unsafe { path.free() } }
	mut created := registration_ensure_directory(store, registration_user_folder_mode) or {
		return false
	}
	if registration_ensure_directory(path, registration_user_home_mode) or { return false } {
		created = true
	}
	os.chmod(path, registration_user_home_mode) or { return false }
	// A missing folder is not worth asking the user to register again for:
	// the Desktop, for one, makes its folder again whenever it is shown.
	for folder in desktop_user_folders {
		made := desktop_ensure_user_folder(home, path, folder.name) or {
			eprintln('vinix-desktop: cannot create ${path}/${folder.name}')
			false
		}
		if made {
			created = true
		}
	}
	$if vinix {
		if created {
			// Vinix's persistent /root is a separate block-backed filesystem.
			// Make a repaired directory durable even when no profile write follows.
			C.sync()
		}
	}
	return true
}

// The desktop used to keep these folders directly in /root. Move one found
// there into the user's home rather than starting it empty, so what was on the
// Desktop or in Downloads is still there.
fn desktop_ensure_user_folder(home string, user_home string, folder string) ?bool {
	path := '${user_home}/${folder}'
	defer { unsafe { path.free() } }
	if os.exists(path) || os.is_link(path) {
		if !os.is_dir(path) {
			return none
		}
		return false
	}
	previous := '${home}/${folder}'
	defer { unsafe { previous.free() } }
	if !os.is_dir(previous) || os.is_link(previous) {
		return registration_ensure_directory(path, registration_user_folder_mode)
	}
	os.rename_dir(previous, path) or {
		return registration_ensure_directory(path, registration_user_folder_mode)
	}
	return true
}

// Make `users`/<user> (/home/<user>) a link to the home kept in `target`. The
// link is checked at every start because /home may be in RAM. Anything else
// already using the name is left alone, and none is returned.
fn desktop_link_user_home(users string, name string, target string) ?string {
	registration_ensure_directory(users, registration_user_folder_mode) or { return none }
	path := desktop_user_home_path(users, name)
	if os.is_link(path) {
		current := os.readlink(path) or { '' }
		same := current == target
		unsafe { current.free() }
		if same {
			return path
		}
		os.rm(path) or {}
	}
	os.symlink(target, path) or {
		unsafe { path.free() }
		return none
	}
	return path
}

// Programs run with HOME=/root, so tell those that follow XDG user-dirs, such
// as Firefox and Chromium for their downloads, where the user's folders are.
// A file that is already there is the user's, and is kept.
fn desktop_write_user_dirs(home string, user_home string) bool {
	path := '${home}/${desktop_user_dirs_name}'
	defer { unsafe { path.free() } }
	if os.exists(path) || os.is_link(path) {
		return true
	}
	config := os.dir(path)
	defer { unsafe { config.free() } }
	registration_ensure_directory(config, registration_user_folder_mode) or { return false }
	mut lines := []string{cap: desktop_user_folders.len + 1}
	defer { unsafe { lines.free() } }
	lines << '# Written by the Vinix desktop when the user was set up.'
	for folder in desktop_user_folders {
		lines << '${folder.xdg}="${user_home}/${folder.name}"'
	}
	lines << ''
	data := lines.join('\n')
	defer { unsafe { data.free() } }
	temporary := '${path}.new'
	defer { unsafe { temporary.free() } }
	os.write_file(temporary, data) or { return false }
	os.rename(temporary, path) or {
		os.rm(temporary) or {}
		return false
	}
	return true
}

// Set up the home the desktop shows for the registered user: its folders, the
// /home/<user> link to them and XDG user-dirs. Without the link the folders are
// still used where they are kept; without a user, `home` is.
fn desktop_prepare_user_home(home string, users string) string {
	name := desktop_load_user_name(home) or { return home.clone() }
	defer { unsafe { name.free() } }
	storage := desktop_user_storage_path(home, name)
	if !desktop_ensure_user_directory(home, name) {
		eprintln('vinix-desktop: cannot prepare ${storage}')
		unsafe { storage.free() }
		return home.clone()
	}
	user_home := desktop_link_user_home(users, name, storage) or {
		eprintln('vinix-desktop: cannot make the home in ${users}; using ${storage}')
		storage
	}
	if user_home != storage {
		unsafe { storage.free() }
	}
	if !desktop_write_user_dirs(home, user_home) {
		eprintln('vinix-desktop: cannot write ${home}/${desktop_user_dirs_name}')
	}
	return user_home
}

// The home as desktop_prepare_user_home left it, for an application process:
// the desktop has already set it up, so this only looks.
fn desktop_find_user_home(home string, users string) string {
	name := desktop_load_user_name(home) or { return home.clone() }
	defer { unsafe { name.free() } }
	storage := desktop_user_storage_path(home, name)
	link := desktop_user_home_path(users, name)
	if os.is_link(link) {
		target := os.readlink(link) or { '' }
		linked := target == storage
		unsafe { target.free() }
		if linked {
			unsafe { storage.free() }
			return link
		}
	}
	unsafe { link.free() }
	if os.is_dir(storage) {
		return storage
	}
	unsafe { storage.free() }
	return home.clone()
}

// Point the Desktop surface and the Files sidebar at `home`, which they own
// from now on.
fn desktop_use_user_home(home string) {
	desktop_user_home = home
	desktop_directory = '${home}/Desktop'
	files_locations = files_locations_in(home)
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
	if !desktop_write_all(file.fd, record.str, u64(record.len)) {
		return false
	}
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
