// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

fn C.fstatat(int, &char, &C.stat, int) int
fn C.unlinkat(int, &char, int) int

// The package reader lock prevents reinstall/activation/collection while we
// establish that no admitted process can still be using this removed app.
fn check_purge_generations(directory string, architecture string, id string) ! {
	current := read_state(directory, architecture)!
	defer { if current.generation > 0 { close_decoded_state(current) } }
	if current.packages.any(it.package.id == id) { return error('remove the application before purging its data') }
	parent := directory + '/generations'
	defer { unsafe { parent.free() } }
	if os.is_link(parent) { return error('package generations must be an ordinary directory') }
	if !os.exists(parent) {
		if current.generation != 0 { return error('package generations are unavailable') }
		return
	}
	names := os.ls(parent)!
	defer { unsafe { for name in names { name.free() }; (&array(&names)).free() } }
	for name in names {
		if !numeric_generation_name(name) { continue }
		number := generation_number(name)!
		state := read_generation_state(directory, architecture, number)!
		contains := state.packages.any(it.package.id == id)
		close_decoded_state(state)
		if !contains { continue }
		path := parent + '/' + name
		check_purge_generation(path, id, number) or { unsafe { path.free() }; return err }
		unsafe { path.free() }
	}
}

fn check_purge_generation(path string, id string, number u64) ! {
	lease := open_collection_generation(path)!
	defer { close_collection_lease(lease) }
	if C.flock(lease.lease, C.LOCK_EX | C.LOCK_NB) != 0 {
		if C.errno == C.EAGAIN || C.errno == C.EWOULDBLOCK {
			return error('cannot purge ${id}: generation ${number} is still in use; stop applications using that generation and retry')
		}
		return error('cannot check application generation before purging data')
	}
}

fn purge_directory_info(fd int, uid u32, private_parent bool) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || u32(info.st_mode) & 0o170000 != 0o040000 || info.st_uid != uid
		|| (private_parent && u32(info.st_mode) & 0o022 != 0) {
		return error('personal application data must use directories owned by the calling account; parent directories must not be writable by other accounts')
	}
	return info
}

fn purge_same_entry(parent int, name &char, original C.stat) ! {
	mut current := C.stat{}
	if C.fstatat(parent, name, &current, C.AT_SYMLINK_NOFOLLOW) != 0
		|| current.st_dev != original.st_dev || current.st_ino != original.st_ino
		|| u32(current.st_mode) & 0o170000 != u32(original.st_mode) & 0o170000 {
		return error('personal application data changed during purge; retry after stopping other file operations')
	}
}

// Stream names instead of allocating a tree or opening special files. Each
// lookup/unlink is relative to an already captured directory, never a symlink.
fn purge_contents(fd int, uid u32, device u64, depth int) ! {
	if depth > 64 { return error('personal application data exceeds the purge directory depth limit (64)') }
	duplicate := C.dup(fd)
	if duplicate < 0 { return error('cannot retain personal data directory') }
	stream := C.fdopendir(duplicate)
	if stream == unsafe { nil } { C.close(duplicate); return error('cannot enumerate personal data directory') }
	defer { C.closedir(stream) }
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read personal data directory') }
			break
		}
		name := unsafe { &entry.d_name[0] }
		if unsafe { C.strcmp(name, c'.') == 0 || C.strcmp(name, c'..') == 0 } { continue }
		mut info := C.stat{}
		if C.fstatat(fd, name, &info, C.AT_SYMLINK_NOFOLLOW) != 0 { return error('cannot inspect personal data entry') }
		if u32(info.st_mode) & 0o170000 == 0o040000 {
			purge_child(fd, name, info, uid, device, depth + 1)!
		} else {
			purge_same_entry(fd, name, info)!
			if C.unlinkat(fd, name, 0) != 0 { return error('cannot remove personal data entry') }
		}
	}
}

fn purge_child(parent int, name &char, original C.stat, uid u32, device u64, depth int) ! {
	child := C.openat(parent, name, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if child < 0 { return error('cannot open personal data directory without following links') }
	defer { C.close(child) }
	captured := purge_directory_info(child, uid, false)!
	if u64(captured.st_dev) != device { return error('personal data purge cannot cross filesystem boundaries') }
	if captured.st_dev != original.st_dev || captured.st_ino != original.st_ino { return error('personal data directory changed before purge') }
	purge_contents(child, uid, device, depth)!
	purge_same_entry(parent, name, captured)!
	if C.unlinkat(parent, name, C.AT_REMOVEDIR) != 0 { return error('cannot remove personal data directory') }
}

// Return an owned descriptor to an ordinary, caller-owned account home.
// Launch, inventory and deletion share this no-follow traversal.
fn personal_data_home(home string, uid u32) !int {
	if !home.starts_with('/') || !printable(home, 4096) || home == '/' {
		return error('personal application data requires an absolute ordinary account home')
	}
	mut directory := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC)
	if directory < 0 { return error('cannot capture the account home') }
	mut retained := false
	defer { if !retained { C.close(directory) } }
	parts := home.split('/')
	defer { unsafe { for part in parts { part.free() }; (&array(&parts)).free() } }
	for index, part in parts {
		if index == 0 { continue }
		if index == parts.len - 1 && part == '' { continue }
		if part in ['', '.', '..'] { return error('account home must use ordinary absolute path components') }
		next := C.openat(directory, part.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if next < 0 { return error('account home must be an ordinary directory at every component') }
		C.close(directory); directory = next
	}
	purge_directory_info(directory, uid, true)!
	retained = true
	return directory
}

// Returns an owned descriptor, or -1 when a read-only caller has no data parent.
fn personal_data_parent(home string, uid u32) !int {
	return personal_data_parent_mode(home, uid, false)
}

fn personal_data_parent_mode(home string, uid u32, create bool) !int {
	mut directory := personal_data_home(home, uid)!
	mut retained := false
	defer { if !retained { C.close(directory) } }
	for part in ['.local', 'share', 'vinix-apps']! {
		next := personal_data_child(directory, part, uid, create)!
		if next < 0 { return -1 }
		C.close(directory); directory = next
	}
	retained = true
	return directory
}

fn purge_personal_data(home string, id string, uid u32) !bool {
	if !identifier(id) { return error('purge-data requires a valid application ID') }
	directory := personal_data_parent(home, uid)!
	if directory < 0 { return false }
	defer { C.close(directory) }
	parent := purge_directory_info(directory, uid, true)!
	data := C.openat(directory, id.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if data < 0 {
		if C.errno == C.ENOENT { return false }
		return error('application data directory must be an ordinary directory; symlinks and special files cannot be purged')
	}
	defer { C.close(data) }
	info := purge_directory_info(data, uid, true)!
	if info.st_dev != parent.st_dev { return error('application data directory is on another filesystem') }
	purge_contents(data, uid, u64(info.st_dev), 0)!
	purge_same_entry(directory, id.str, info)!
	if C.unlinkat(directory, id.str, C.AT_REMOVEDIR) != 0 { return error('cannot remove application data directory') }
	return true
}

pub fn (service Service) purge_data(id string) ! {
	if service.root != '' || !identifier(id) || os.geteuid() == 0 || C.getegid() == 0 {
		return error('purge-data requires an application ID and an ordinary user session')
	}
	directory := service.directory()!
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	check_purge_generations(directory, config.architecture, id)!
	purge_personal_data(os.home_dir(), id, u32(os.geteuid()))!
}
