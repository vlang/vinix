// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded personal Trash. Rows own their strings; frame labels borrow them.
module main

const files_trash_limit = 256
const files_trash_path_limit = 4096
const files_trash_store = '.vinix-trash'
const files_trash_row_prefix = 'files.trash.row.'

struct FilesTrashEntry {
mut:
	bucket        string
	path          string // relative to the trusted user's home
	action        string
	bucket_device u64
	bucket_inode  u64
	device        u64
	inode         u64
	mode          u32
}

struct FilesTrash {
mut:
	home         string
	home_alias   string
	home_fd      int = -1
	store_fd     int = -1
	entries      []FilesTrashEntry
	selected     int = -1
	page         int
	visible_rows int = 1
	sequence     u64
	damaged      bool
	confirming   bool
	status       string = 'files.trash.ready' // borrowed translation key
}

fn files_trash_new(home string) FilesTrash {
	mut trash := FilesTrash{ home: reminders_canonical_home(home), home_alias: home.clone() }
	if trash.home.len == 0 || trash.home == '/' {
		trash.status = 'files.trash.unavailable'
		return trash
	}
	trash.home_fd = C.open(&char(trash.home.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	if trash.home_fd < 0 { trash.status = 'files.trash.unavailable' }
	return trash
}

fn files_trash_relative_valid(path string) bool {
	if path.len == 0 || path.len > files_trash_path_limit || path[0] == `/`
		|| !notes_valid_text(path, files_trash_path_limit, false) {
		return false
	}
	mut start := 0
	for at in 0 .. path.len + 1 {
		if at != path.len && path[at] != `/` { continue }
		part := unsafe { tos(path.str + start, at - start) }
		if part.len == 0 || part.len > 255 || part == '.' || part == '..' { return false }
		// App records and the Trash itself are not ordinary user documents.
		if start == 0 && part.starts_with('.vinix-') { return false }
		start = at + 1
	}
	return true
}

fn (trash &FilesTrash) relative(path string) string {
	for home in [trash.home, trash.home_alias]! {
		if home.len > 0 && path.len > home.len + 1 && path.starts_with(home) && path[home.len] == `/` {
			candidate := unsafe { tos(path.str + home.len + 1, path.len - home.len - 1) }
			if files_trash_relative_valid(candidate) { return candidate.clone() }
		}
	}
	return ''
}

fn files_trash_name(path string) string {
	mut start := 0
	for at, ch in path { if ch == `/` { start = at + 1 } }
	return unsafe { tos(path.str + start, path.len - start) }
}

fn (mut trash FilesTrash) clear_rows() {
	for entry in trash.entries {
		unsafe {
			entry.bucket.free()
			entry.path.free()
			entry.action.free()
		}
	}
	trash.entries.clear()
	trash.selected = -1
	trash.confirming = false
}

fn (mut trash FilesTrash) close() {
	trash.clear_rows()
	unsafe {
		trash.entries.free()
		trash.home.free()
		trash.home_alias.free()
	}
	trash.entries = []FilesTrashEntry{}
	trash.home = ''
	trash.home_alias = ''
	if trash.store_fd >= 0 { desktop_close(trash.store_fd) }
	if trash.home_fd >= 0 { desktop_close(trash.home_fd) }
	trash.store_fd = -1
	trash.home_fd = -1
}

fn files_trash_kind_allowed(mode u32) bool {
	kind := mode & u32(C.S_IFMT)
	return kind == u32(C.S_IFREG) || kind == u32(C.S_IFDIR) || kind == u32(C.S_IFLNK)
}

fn files_trash_metadata(info C.stat, relative string) string {
	device := u64(info.st_dev).str()
	inode := u64(info.st_ino).str()
	mode := u32(info.st_mode).str()
	defer {
		unsafe {
			device.free()
			inode.free()
			mode.free()
		}
	}
	return 'VINIX TRASH 1\n${device}\t${inode}\t${mode}\n${relative}\n'
}

fn files_trash_parse(record string) ?FilesTrashEntry {
	if !record.starts_with('VINIX TRASH 1\n') || !record.ends_with('\n') { return none }
	mut at := 14
	mut numbers := [3]u64{}
	for index in 0 .. 3 {
		start := at
		for at < record.len && record[at] >= `0` && record[at] <= `9` { at++ }
		if at >= record.len || record[at] != (if index == 2 { `\n` } else { `\t` }) { return none }
		numbers[index] = notes_number(unsafe { tos(record.str + start, at - start) }) or { return none }
		at++
	}
	if at >= record.len - 1 { return none }
	path := unsafe { tos(record.str + at, record.len - at - 1) }
	if numbers[2] > u64(~u32(0)) || !files_trash_kind_allowed(u32(numbers[2]))
		|| !files_trash_relative_valid(path) {
		return none
	}
	return FilesTrashEntry{ path: path.clone(), device: numbers[0], inode: numbers[1], mode: u32(numbers[2]) }
}

fn (mut trash FilesTrash) reload() {
	trash.status = trash.ensure_store()
	if trash.status != 'files.trash.ready' { return }
	lock_fd := files_trash_lock(trash.store_fd)
	if lock_fd < 0 {
		trash.status = if lock_fd == -2 { 'files.trash.busy' } else { 'files.trash.unavailable' }
		return
	}
	defer { desktop_close(lock_fd) }
	trash.scan_locked()
	trash.status = if trash.damaged { 'files.trash.damaged' } else { 'files.trash.ready' }
}

fn (mut trash FilesTrash) move(path string) bool {
	trash.confirming = false
	relative := trash.relative(path)
	defer { unsafe { relative.free() } }
	if relative.len == 0 {
		trash.status = 'files.trash.unsafe'
		return false
	}
	trash.status = trash.ensure_store()
	if trash.status != 'files.trash.ready' { return false }
	lock_fd := files_trash_lock(trash.store_fd)
	if lock_fd < 0 {
		trash.status = if lock_fd == -2 { 'files.trash.busy' } else { 'files.trash.unavailable' }
		return false
	}
	defer { desktop_close(lock_fd) }
	trash.scan_locked()
	if trash.damaged {
		trash.status = 'files.trash.damaged'
		return false
	}
	if trash.entries.len >= files_trash_limit {
		trash.status = 'files.trash.unavailable'
		return false
	}
	parent, leaf := files_trash_parent(trash.home_fd, relative)
	defer {
		if parent >= 0 { desktop_close(parent) }
		unsafe { leaf.free() }
	}
	if parent < 0 {
		trash.status = 'files.trash.unsafe'
		return false
	}
	mut info := C.stat{}
	if unsafe { C.fstatat(parent, &char(leaf.str), &info, C.AT_SYMLINK_NOFOLLOW) } != 0
		|| !files_trash_kind_allowed(u32(info.st_mode)) {
		trash.status = 'files.trash.unsafe'
		return false
	}
	trash.status = trash.move_locked(parent, leaf, relative, info, lock_fd)
	succeeded := trash.status in ['files.trash.moved', 'files.trash.unsynced',
		'files.trash.changed_moved']
	if succeeded { trash.scan_locked() }
	return succeeded
}

fn (mut trash FilesTrash) restore() {
	trash.confirming = false
	if trash.selected < 0 || trash.selected >= trash.entries.len {
		trash.status = 'files.trash.select'
		return
	}
	trash.status = trash.ensure_store()
	if trash.status != 'files.trash.ready' { return }
	lock_fd := files_trash_lock(trash.store_fd)
	if lock_fd < 0 {
		trash.status = if lock_fd == -2 { 'files.trash.busy' } else { 'files.trash.unavailable' }
		return
	}
	defer { desktop_close(lock_fd) }
	trash.status = files_trash_restore_locked(trash.store_fd, trash.home_fd, &trash.entries[trash.selected], lock_fd)
	if trash.status in ['files.trash.restored', 'files.trash.unsynced'] { trash.scan_locked() }
}

fn (mut trash FilesTrash) empty_confirmed() {
	if !trash.confirming { return }
	trash.confirming = false
	trash.status = trash.ensure_store()
	if trash.status != 'files.trash.ready' { return }
	lock_fd := files_trash_lock(trash.store_fd)
	if lock_fd < 0 {
		trash.status = if lock_fd == -2 { 'files.trash.busy' } else { 'files.trash.unavailable' }
		return
	}
	defer { desktop_close(lock_fd) }
	if trash.damaged {
		trash.status = 'files.trash.damaged'
		return
	}
	// Confirm precisely the catalog the user saw. New arrivals in another
	// window require a fresh review rather than joining an earlier approval.
	if !files_trash_catalog_matches(trash.store_fd, trash.entries) {
		trash.scan_locked()
		trash.status = if trash.damaged { 'files.trash.damaged' } else { 'files.trash.changed' }
		return
	}
	// Preflight every item before deleting anything. Never recursively walk a
	// directory that a concurrent writer could move outside the Trash.
	for index in 0 .. trash.entries.len {
		status := files_trash_empty_check(trash.store_fd, &trash.entries[index])
		if status != 'files.trash.ready' {
			trash.status = status
			return
		}
	}
	for index in 0 .. trash.entries.len {
		if !files_trash_empty_one(trash.store_fd, &trash.entries[index]) {
			trash.scan_locked()
			trash.status = 'files.trash.partial'
			return
		}
	}
	trash.scan_locked()
	trash.status = if trash.damaged || trash.entries.len > 0 {
		'files.trash.partial'
	} else if !reminders_sync_directory(trash.store_fd, lock_fd) {
		'files.trash.empty_unsynced'
	} else {
		'files.trash.emptied'
	}
}
