// SPDX-License-Identifier: GPL-2.0-or-later
// All untrusted names are single components relative to anchored descriptors.
module main

#include <stdio.h>

$if macos {
	#define vinix_trash_rename(a,b,c,d) renameatx_np(a,b,c,d,RENAME_EXCL)
} $else {
	#include <sys/syscall.h>
	#define vinix_trash_rename(a,b,c,d) syscall(SYS_renameat2,a,b,c,d,1)
}

fn C.vinix_trash_rename(old_directory int, old_name &char, new_directory int, new_name &char) int

fn files_trash_identity(info C.stat, device u64, inode u64) bool {
	return u64(info.st_dev) == device && u64(info.st_ino) == inode
}

fn files_trash_private_directory(fd int) bool {
	mut info := C.stat{}
	return unsafe { C.fstat(fd, &info) } == 0 && u32(info.st_mode) & u32(C.S_IFMT) == u32(C.S_IFDIR)
		&& u32(info.st_uid) == C.getuid() && u32(info.st_mode) & 0o077 == 0
}

fn (mut trash FilesTrash) ensure_store() string {
	if trash.home_fd < 0 { return 'files.trash.unavailable' }
	if trash.store_fd < 0 {
		if C.mkdirat(trash.home_fd, c'.vinix-trash', 0o700) != 0 && C.errno != C.EEXIST {
			return 'files.trash.unavailable'
		}
		trash.store_fd = C.openat(trash.home_fd, c'.vinix-trash', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
		if trash.store_fd < 0 { return 'files.trash.unavailable' }
	}
	mut info := C.stat{}
	mut current := C.stat{}
	if !files_trash_private_directory(trash.store_fd)
		|| unsafe { C.fstat(trash.store_fd, &info) } != 0
		|| unsafe { C.fstatat(trash.home_fd, c'.vinix-trash', &current, C.AT_SYMLINK_NOFOLLOW) } != 0
		|| !files_trash_identity(current, u64(info.st_dev), u64(info.st_ino)) {
		return 'files.trash.unavailable'
	}
	return 'files.trash.ready'
}

fn files_trash_lock(directory int) int {
	if directory < 0 { return -1 }
	fd := C.openat(directory, c'.lock', C.O_CREAT | C.O_RDWR | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC, 0o600)
	if fd < 0 { return -1 }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| u32(info.st_uid) != C.getuid() || u32(info.st_mode) & 0o077 != 0 {
		desktop_close(fd)
		return -1
	}
	if C.flock(fd, C.LOCK_EX | C.LOCK_NB) != 0 {
		desktop_close(fd)
		return -2
	}
	return fd
}

// The returned leaf is owned and NUL-terminated. A symlink in any parent is
// refused; a leaf link can be moved/unlinked without following its target.
fn files_trash_parent(home int, path string) (int, string) {
	if home < 0 || !files_trash_relative_valid(path) { return -1, '' }
	mut parent := C.openat(home, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	if parent < 0 { return -1, '' }
	mut start := 0
	for at, ch in path {
		if ch != `/` { continue }
		part := unsafe { tos(path.str + start, at - start) }.clone()
		next := C.openat(parent, &char(part.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
		unsafe { part.free() }
		desktop_close(parent)
		if next < 0 { return -1, '' }
		parent = next
		start = at + 1
	}
	return parent, unsafe { tos(path.str + start, path.len - start) }.clone()
}

fn files_trash_bucket_name(name string) bool {
	if !name.starts_with('item.') || name.len > 80 { return false }
	for ch in unsafe { tos(name.str + 5, name.len - 5) } {
		if (ch < `0` || ch > `9`) && ch != `.` { return false }
	}
	return name.len > 5
}

fn files_trash_bucket_complete(directory int) bool {
	fd := C.openat(directory, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	if fd < 0 { return false }
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } {
		desktop_close(fd)
		return false
	}
	defer { C.closedir(stream) }
	mut count := 0
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } { return C.errno == 0 && count == 2 }
		name := unsafe { tos2(&u8(&entry.d_name[0])) }
		if name == '.' || name == '..' { continue }
		if name != 'info' && name != 'item' { return false }
		count++
		if count > 2 { return false }
	}
	return false
}

fn files_trash_read_metadata(directory int) ?FilesTrashEntry {
	fd := C.openat(directory, c'info', C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	if fd < 0 { return none }
	defer { desktop_close(fd) }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| info.st_size < 20 || info.st_size > files_trash_path_limit + 100 {
		return none
	}
	mut buffer := []u8{len: int(info.st_size)}
	defer { unsafe { buffer.free() } }
	mut at := 0
	mut interrupted := 0
	for at < int(info.st_size) {
		n := desktop_read(fd, unsafe { &u8(buffer.data) + at }, u64(int(info.st_size) - at))
		if n < 0 && C.errno == C.EINTR && interrupted < 8 {
			interrupted++
			continue
		}
		if n <= 0 { return none }
		at += int(n)
	}
	mut after := C.stat{}
	if unsafe { C.fstat(fd, &after) } != 0 || after.st_size != info.st_size || after.st_mtime != info.st_mtime
		|| unsafe { C.vinix_reminders_mtime_nsec(&after) } != unsafe { C.vinix_reminders_mtime_nsec(&info) } {
		return none
	}
	mut result := files_trash_parse(unsafe { tos(buffer.data, at) }) or { return none }
	mut payload := C.stat{}
	if unsafe { C.fstatat(directory, c'item', &payload, C.AT_SYMLINK_NOFOLLOW) } != 0
		|| !files_trash_identity(payload, result.device, result.inode) || u32(payload.st_mode) != result.mode {
		unsafe { result.path.free() }
		return none
	}
	return result
}

fn (mut trash FilesTrash) scan_locked() {
	trash.clear_rows()
	trash.damaged = false
	if trash.entries.cap == 0 {
		trash.entries = []FilesTrashEntry{cap: files_trash_limit}
		trash.entries.flags |= .noslices
	}
	fd := C.openat(trash.store_fd, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	if fd < 0 {
		trash.damaged = true
		return
	}
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } {
		desktop_close(fd)
		trash.damaged = true
		return
	}
	defer { C.closedir(stream) }
	mut visited := 0
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { trash.damaged = true }
			break
		}
		name := unsafe { tos2(&u8(&entry.d_name[0])) }
		if name == '.' || name == '..' || name == '.lock' { continue }
		visited++
		if visited > files_trash_limit {
			trash.damaged = true
			break
		}
		if trash.entries.len >= files_trash_limit || !files_trash_bucket_name(name) {
			trash.damaged = true
			continue
		}
		bucket := name.clone()
		child := C.openat(trash.store_fd, &char(bucket.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
		if child < 0 {
			unsafe { bucket.free() }
			trash.damaged = true
			continue
		}
		mut info := C.stat{}
		if !files_trash_private_directory(child) || unsafe { C.fstat(child, &info) } != 0 || !files_trash_bucket_complete(child) {
			desktop_close(child)
			unsafe { bucket.free() }
			trash.damaged = true
			continue
		}
		mut row := files_trash_read_metadata(child) or {
			desktop_close(child)
			unsafe { bucket.free() }
			trash.damaged = true
			continue
		}
		desktop_close(child)
		number := trash.entries.len.str()
		action := '${files_trash_row_prefix}${number}'
		unsafe { number.free() }
		// Append an inline constructor so V3 transfers these owned strings.
		trash.entries << FilesTrashEntry{
			bucket:        bucket
			path:          row.path
			action:        action
			bucket_device: u64(info.st_dev)
			bucket_inode:  u64(info.st_ino)
			device:        row.device
			inode:         row.inode
			mode:          row.mode
		}
	}
}

fn files_trash_remove_bucket(store int, name string, info C.stat) bool {
	mut current := C.stat{}
	return unsafe { C.fstatat(store, &char(name.str), &current, C.AT_SYMLINK_NOFOLLOW) } == 0
		&& files_trash_identity(current, u64(info.st_dev), u64(info.st_ino))
		&& C.unlinkat(store, &char(name.str), C.AT_REMOVEDIR) == 0
}

fn (mut trash FilesTrash) move_locked(parent int, leaf string, relative string, info C.stat, sync_file int) string {
	pid := C.getpid().str()
	mut name := ''
	mut bucket := -1
	defer {
		unsafe {
			pid.free()
			name.free()
		}
		if bucket >= 0 { desktop_close(bucket) }
	}
	// A reopened process/window may start its sequence at zero. Since the
	// catalog is bounded, this also finds a free name after 256 collisions.
	for _ in 0 .. files_trash_limit + 1 {
		trash.sequence++
		number := trash.sequence.str()
		unsafe { name.free() }
		name = 'item.${pid}.${number}'
		unsafe { number.free() }
		if C.mkdirat(trash.store_fd, &char(name.str), 0o700) == 0 {
			bucket = C.openat(trash.store_fd, &char(name.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
			break
		}
		if C.errno != C.EEXIST { return 'files.trash.failed' }
	}
	if bucket < 0 { return 'files.trash.failed' }
	mut bucket_info := C.stat{}
	if unsafe { C.fstat(bucket, &bucket_info) } != 0 || !files_trash_private_directory(bucket) {
		return 'files.trash.failed'
	}
	mut moved := false
	mut metadata_info := C.stat{}
	mut metadata_known := false
	defer {
		if !moved {
			if metadata_known { reminders_remove_owned(bucket, 'info', metadata_info) }
			files_trash_remove_bucket(trash.store_fd, name, bucket_info)
		}
	}
	metadata := files_trash_metadata(info, relative)
	defer { unsafe { metadata.free() } }
	fd := C.openat(bucket, c'info', C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK, 0o600)
	if fd < 0 { return 'files.trash.failed' }
	metadata_known = unsafe { C.fstat(fd, &metadata_info) } == 0
	written := metadata_known && desktop_write_all(fd, metadata.str, u64(metadata.len)) && desktop_preferences_fsync(fd)
	synced := written && reminders_sync_directory(bucket, fd)
		&& reminders_sync_directory(trash.store_fd, fd)
	closed := desktop_close(fd) == 0
	if !written || !synced || !closed { return 'files.trash.failed' }
	if C.vinix_trash_rename(parent, &char(leaf.str), bucket, c'item') != 0 {
		return if C.errno == C.EXDEV { 'files.trash.cross_device' } else { 'files.trash.failed' }
	}
	moved = true
	mut payload := C.stat{}
	if unsafe { C.fstatat(bucket, c'item', &payload, C.AT_SYMLINK_NOFOLLOW) } != 0
		|| !files_trash_identity(payload, u64(info.st_dev), u64(info.st_ino)) || u32(payload.st_mode) != u32(info.st_mode) {
		return 'files.trash.changed_moved'
	}
	return if reminders_sync_directory(bucket, sync_file) && reminders_sync_directory(parent, sync_file)
		&& reminders_sync_directory(trash.store_fd, sync_file) {
		'files.trash.moved'
	} else {
		'files.trash.unsynced'
	}
}

fn files_trash_checked_bucket(store int, entry &FilesTrashEntry) int {
	fd := C.openat(store, &char(entry.bucket.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if fd < 0 { return -1 }
	mut info := C.stat{}
	if !files_trash_private_directory(fd) || unsafe { C.fstat(fd, &info) } != 0
		|| !files_trash_identity(info, entry.bucket_device, entry.bucket_inode) || !files_trash_bucket_complete(fd) {
		desktop_close(fd)
		return -1
	}
	row := files_trash_read_metadata(fd) or {
		desktop_close(fd)
		return -1
	}
	same := row.path == entry.path && row.device == entry.device && row.inode == entry.inode && row.mode == entry.mode
	unsafe { row.path.free() }
	if !same {
		desktop_close(fd)
		return -1
	}
	return fd
}

fn files_trash_cleanup_bucket(store int, bucket int, entry &FilesTrashEntry) bool {
	mut info := C.stat{}
	if unsafe { C.fstat(bucket, &info) } != 0 { return false }
	if C.unlinkat(bucket, c'info', 0) != 0 { return false }
	return files_trash_remove_bucket(store, entry.bucket, info)
}

fn files_trash_restore_locked(store int, home int, entry &FilesTrashEntry, sync_file int) string {
	bucket := files_trash_checked_bucket(store, entry)
	if bucket < 0 { return 'files.trash.changed' }
	defer { desktop_close(bucket) }
	parent, leaf := files_trash_parent(home, entry.path)
	if parent < 0 { return 'files.trash.parent_missing' }
	defer {
		desktop_close(parent)
		unsafe { leaf.free() }
	}
	if C.vinix_trash_rename(bucket, c'item', parent, &char(leaf.str)) != 0 {
		return if C.errno == C.EEXIST || C.errno == C.ENOTEMPTY {
			'files.trash.conflict'
		} else if C.errno == C.EXDEV {
			'files.trash.cross_device'
		} else {
			'files.trash.failed'
		}
	}
	clean := files_trash_cleanup_bucket(store, bucket, entry)
	synced := reminders_sync_directory(parent, sync_file) && reminders_sync_directory(store, sync_file)
	return if clean && synced { 'files.trash.restored' } else { 'files.trash.unsynced' }
}

fn files_trash_directory_empty(directory int) bool {
	fd := C.openat(directory, c'item', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if fd < 0 { return false }
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } {
		desktop_close(fd)
		return false
	}
	defer { C.closedir(stream) }
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } { return C.errno == 0 }
		name := unsafe { tos2(&u8(&entry.d_name[0])) }
		if name != '.' && name != '..' { return false }
	}
	return false
}

fn files_trash_empty_check(store int, entry &FilesTrashEntry) string {
	bucket := files_trash_checked_bucket(store, entry)
	if bucket < 0 { return 'files.trash.changed' }
	defer { desktop_close(bucket) }
	if entry.mode & u32(C.S_IFMT) == u32(C.S_IFDIR) && !files_trash_directory_empty(bucket) {
		return 'files.trash.nonempty'
	}
	return 'files.trash.ready'
}

fn files_trash_catalog_matches(store int, entries []FilesTrashEntry) bool {
	fd := C.openat(store, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	if fd < 0 { return false }
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } {
		desktop_close(fd)
		return false
	}
	defer { C.closedir(stream) }
	mut count := 0
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } { return C.errno == 0 && count == entries.len }
		name := unsafe { tos2(&u8(&entry.d_name[0])) }
		if name == '.' || name == '..' || name == '.lock' { continue }
		count++
		if count > entries.len { return false }
		mut found := false
		for row in entries {
			if row.bucket == name {
				found = true
				break
			}
		}
		if !found { return false }
	}
	return false
}

fn files_trash_empty_one(store int, entry &FilesTrashEntry) bool {
	bucket := files_trash_checked_bucket(store, entry)
	if bucket < 0 { return false }
	defer { desktop_close(bucket) }
	flags := if entry.mode & u32(C.S_IFMT) == u32(C.S_IFDIR) { C.AT_REMOVEDIR } else { 0 }
	// unlinkat never follows a leaf link; rmdir refuses a directory that grew.
	if C.unlinkat(bucket, c'item', flags) != 0 { return false }
	return files_trash_cleanup_bucket(store, bucket, entry)
}
