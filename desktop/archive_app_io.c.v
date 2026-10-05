// SPDX-License-Identifier: GPL-2.0-or-later
// Descriptor-relative walks reject symlinks in every path component.
module main

$if macos {
	#define vinix_archive_mtime_nsec(info) ((info)->st_mtimespec.tv_nsec)
} $else {
	#define vinix_archive_mtime_nsec(info) ((info)->st_mtim.tv_nsec)
}

fn C.vinix_archive_mtime_nsec(info &C.stat) i64

fn C.openat(dirfd int, path &char, flags int, mode u32) int
fn C.mkdirat(dirfd int, path &char, mode u32) int
fn C.unlinkat(dirfd int, path &char, flags int) int
fn C.fstatat(dirfd int, path &char, info &C.stat, flags int) int
fn C.fdopendir(fd int) voidptr
fn C.closedir(dir voidptr) int

fn archive_absolute_valid(path string) bool {
	if !console_valid_path(path) || path.len < 2 || path[path.len - 1] == `/` { return false }
	return archive_name_valid_path(unsafe { tos(path.str + 1, path.len - 1) })
}

fn archive_name_valid_path(path string) bool {
	mut start := 0
	for at in 0 .. path.len + 1 {
		if at == path.len || path[at] == `/` {
			length := at - start
			if length == 0 || length > 255 { return false }
			component := unsafe { tos(path.str + start, length) }
			if !archive_name_valid(component) { return false }
			start = at + 1
		}
	}
	for byte in path { if byte < 0x20 || byte == 0x7f || byte == `\\` { return false } }
	return true
}

// Returns an owned final component and a parent descriptor. The caller owns
// both on success; every failed walk closes its partial descriptor chain.
fn archive_parent(path string) (int, string) {
	if !archive_absolute_valid(path) { return -1, '' }
	mut fd := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return -1, '' }
	mut start := 1
	for at in 1 .. path.len + 1 {
		if at != path.len && path[at] != `/` { continue }
		component := unsafe { tos(path.str + start, at - start) }.clone()
		if at == path.len { return fd, component }
		next := C.openat(fd, &char(component.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
		unsafe { component.free() }
		desktop_close(fd)
		if next < 0 { return -1, '' }
		fd = next
		start = at + 1
	}
	desktop_close(fd)
	return -1, ''
}

fn archive_open_source(path string) int {
	parent, leaf := archive_parent(path)
	if parent < 0 { return -1 }
	defer {
		desktop_close(parent)
		unsafe { leaf.free() }
	}
	return C.openat(parent, &char(leaf.str), C.O_RDONLY | C.O_NONBLOCK | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
}

fn archive_new_directory(path string) (int, string) {
	parent, leaf := archive_parent(path)
	if parent < 0 { return -1, 'archive.invalid_path' }
	defer {
		desktop_close(parent)
		unsafe { leaf.free() }
	}
	if C.mkdirat(parent, &char(leaf.str), 0o700) != 0 {
		return -1, if C.errno == C.EEXIST { 'archive.exists' } else { 'archive.write_failed' }
	}
	fd := C.openat(parent, &char(leaf.str), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
	return fd, if fd < 0 { 'archive.partial' } else { '' }
}

// root is the newly created extraction directory, never an existing tree.
// Each parent remains anchored by a descriptor while its child is opened.
fn archive_extract_entry(root int, entry ArchiveEntry) int {
	mut current := C.dup(root)
	if current < 0 { return -1 }
	mut start := 0
	for at in 0 .. entry.name.len + 1 {
		if at != entry.name.len && entry.name[at] != `/` { continue }
		component := unsafe { tos(entry.name.str + start, at - start) }.clone()
		last := at == entry.name.len
		if !last || entry.directory {
			created := C.mkdirat(current, &char(component.str), 0o700)
			if created != 0 && C.errno != C.EEXIST {
				unsafe { component.free() }
				desktop_close(current)
				return -1
			}
		}
		flags := if last && !entry.directory {
			C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW | C.O_CLOEXEC | C.O_NONBLOCK
		} else {
			C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC
		}
		next := C.openat(current, &char(component.str), flags, 0o600)
		unsafe { component.free() }
		desktop_close(current)
		if next < 0 { return -1 }
		current = next
		start = at + 1
	}
	return current
}

fn archive_relative_source(root int, path string) int {
	if path.len == 0 { return C.dup(root) }
	mut current := C.dup(root)
	if current < 0 { return -1 }
	mut start := 0
	for at in 0 .. path.len + 1 {
		if at != path.len && path[at] != `/` { continue }
		component := unsafe { tos(path.str + start, at - start) }.clone()
		flags := C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC |
			if at != path.len { C.O_DIRECTORY } else { 0 }
		next := C.openat(current, &char(component.str), flags, 0)
		unsafe { component.free() }
		desktop_close(current)
		if next < 0 { return -1 }
		current = next
		start = at + 1
	}
	return current
}

fn archive_source_matches(fd int, entry ArchiveEntry) bool {
	mut info := C.stat{}
	return unsafe { C.fstat(fd, &info) } == 0 && u32(info.st_mode) & u32(C.S_IFMT) == u32(C.S_IFREG)
		&& u64(info.st_ino) == entry.inode && u64(info.st_dev) == entry.device
		&& u64(info.st_size) == entry.size && info.st_mtime == entry.mtime
		&& unsafe { C.vinix_archive_mtime_nsec(&info) } == entry.mtime_nsec
}

struct ArchiveBudget {
mut:
	used u64
}

fn archive_collect_entry(mut entries []ArchiveEntry, name string, relative string, info C.stat, mut budget ArchiveBudget) string {
	kind := u32(info.st_mode) & u32(C.S_IFMT)
	if kind != u32(C.S_IFDIR) && kind != u32(C.S_IFREG) { return 'archive.unsafe_entry' }
	if entries.len >= archive_max_entries { return 'archive.entry_limit' }
	if !archive_name_valid(name) { return 'archive.unsafe_entry' }
	_, supported := archive_tar_name_parts(name)
	if !supported { return 'archive.name_limit' }
	size := if kind == u32(C.S_IFREG) { u64(info.st_size) } else { u64(0) }
	cost := u64(512) + ((size + 511) / 512) * 512
	if size > u64(archive_max_bytes) || budget.used + cost + 1024 > u64(archive_max_bytes) {
		return 'archive.source_limit'
	}
	entries << ArchiveEntry{}
	index := entries.len - 1
	entries[index].name = name.clone()
	entries[index].source_path = relative.clone()
	entries[index].directory = kind == u32(C.S_IFDIR)
	entries[index].size = size
	entries[index].size_text = archive_size_text(size)
	entries[index].inode = u64(info.st_ino)
	entries[index].device = u64(info.st_dev)
	entries[index].mtime = info.st_mtime
	entries[index].mtime_nsec = unsafe { C.vinix_archive_mtime_nsec(&info) }
	budget.used += cost
	return ''
}

fn archive_collect_directory(fd int, basename string, relative string, depth int, mut entries []ArchiveEntry, mut budget ArchiveBudget) string {
	if depth >= archive_max_depth { return 'archive.entry_limit' }
	duplicate := C.dup(fd)
	if duplicate < 0 { return 'archive.read_failed' }
	dir := C.fdopendir(duplicate)
	if dir == unsafe { nil } {
		desktop_close(duplicate)
		return 'archive.read_failed'
	}
	defer { C.closedir(dir) }
	for {
		C.errno = 0
		raw := unsafe { C.readdir(dir) }
		if raw == unsafe { nil } {
			return if C.errno == 0 { '' } else { 'archive.read_failed' }
		}
		name := unsafe { tos(&u8(&raw.d_name[0]), int(C.strlen(&char(&raw.d_name[0])))) }
		if name == '.' || name == '..' { continue }
		if !archive_name_valid(name) || name.contains('/') { return 'archive.unsafe_entry' }
		mut info := C.stat{}
		if unsafe { C.fstatat(fd, &char(&raw.d_name[0]), &info, C.AT_SYMLINK_NOFOLLOW) } != 0 {
			return 'archive.read_failed'
		}
		child_relative := if relative.len > 0 { '${relative}/${name}' } else { name.clone() }
		child_name := '${basename}/${child_relative}'
		status := archive_collect_entry(mut entries, child_name, child_relative, info, mut budget)
		if status.len > 0 {
			unsafe {
				child_relative.free()
				child_name.free()
			}
			return status
		}
		if u32(info.st_mode) & u32(C.S_IFMT) == u32(C.S_IFDIR) {
			child := C.openat(fd, &char(&raw.d_name[0]), C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC, 0)
			if child < 0 {
				unsafe {
					child_relative.free()
					child_name.free()
				}
				return 'archive.read_failed'
			}
			nested := archive_collect_directory(child, basename, child_relative, depth + 1, mut entries, mut budget)
			desktop_close(child)
			if nested.len > 0 {
				unsafe {
					child_relative.free()
					child_name.free()
				}
				return nested
			}
		}
		unsafe {
			child_relative.free()
			child_name.free()
		}
	}
	return ''
}

// Match preferences durability on Vinix: a directory may reject fsync with
// EINVAL, while syncing the still-open file also flushes its directory entry.
fn archive_sync_parent(parent int, file int) bool {
	if desktop_preferences_fsync(parent) { return true }
	return C.errno == C.EINVAL && desktop_preferences_fsync(file)
}
