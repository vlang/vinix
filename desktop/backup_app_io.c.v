// SPDX-License-Identifier: GPL-2.0-or-later
// Descriptor-relative operations keep every traversed component anchored.
module main

#if defined(__APPLE__)
#define vinix_backup_mtime_nsec(info) ((info)->st_mtimespec.tv_nsec)
#else
#define vinix_backup_mtime_nsec(info) ((info)->st_mtim.tv_nsec)
#endif

fn C.vinix_backup_mtime_nsec(info &C.stat) i64

fn C.openat(directory int, path &char, flags int, mode u32) int
fn C.mkdirat(directory int, path &char, mode u32) int
fn C.fstatat(directory int, path &char, info &C.stat, flags int) int
fn C.fdopendir(fd int) voidptr
fn C.dirfd(directory voidptr) int
fn C.dup(fd int) int
fn C.unlinkat(directory int, path &char, flags int) int

const backup_path_limit = 4096
const backup_depth_limit = 64
const backup_entry_limit = u64(100000)
const backup_chunk_bytes = 64 * 1024
const backup_total_limit = u64(256) * 1024 * 1024 * 1024
const backup_file_limit = u64(64) * 1024 * 1024 * 1024
const backup_marker = 'VINIX BACKUP COMPLETE 1\n'

fn backup_valid_path(path string) bool {
	if path.len < 2 || path.len > backup_path_limit || path[0] != `/` || path.ends_with('/') { return false }
	mut start := 1
	for at in 1 .. path.len + 1 {
		if at == path.len || path[at] == `/` {
			part := unsafe { tos(path.str + start, at - start) }
			if part.len == 0 || part == '.' || part == '..' { return false }
			start = at + 1
		} else if path[at] < 0x20 || path[at] == 0x7f { return false }
	}
	return true
}

fn backup_join(directory string, name string) string {
	return if directory.len == 0 { name.clone() } else { '${directory}/${name}' }
}

fn backup_overlaps(first string, second string) bool {
	if first == second { return true }
	if first.len < second.len { return second.starts_with(first) && second[first.len] == `/` }
	return first.starts_with(second) && first[second.len] == `/`
}

// All components, including intermediate directories, refuse symbolic links.
// Paths from editable fields must be cloned before this POSIX boundary.
fn backup_open_directory(path string) int {
	return backup_open_directory_avoiding(path, -1)
}

fn backup_open_directory_avoiding(path string, forbidden int) int {
	return backup_open_directory_avoiding_roots(path, [forbidden, -1, -1, -1]!)
}

fn backup_open_directory_avoiding_roots(path string, forbidden [4]int) int {
	if !backup_valid_path(path) { return -1 }
	mut fd := C.open(c'/', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
	if fd < 0 { return -1 }
	for root in forbidden {
		if root >= 0 && backup_same_directory(fd, root) { desktop_close(fd) return -1 }
	}
	mut start := 1
	for at in 1 .. path.len + 1 {
		if at != path.len && path[at] != `/` { continue }
		part := unsafe { tos(path.str + start, at - start) }.clone()
		next := C.openat(fd, &char(part.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW, 0)
		unsafe { part.free() }
		desktop_close(fd)
		if next < 0 { return -1 }
		fd = next
		for root in forbidden {
			if root >= 0 && backup_same_directory(fd, root) { desktop_close(fd) return -1 }
		}
		start = at + 1
	}
	return fd
}

fn backup_same_directory(first int, second int) bool {
	mut a := C.stat{}
	mut b := C.stat{}
	return unsafe { C.fstat(first, &a) } == 0 && unsafe { C.fstat(second, &b) } == 0
		&& a.st_dev == b.st_dev && a.st_ino == b.st_ino
}

fn backup_new_file(directory int, name string) int {
	return C.openat(directory, &char(name.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL |
		C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, u32(0o600))
}

fn backup_read_marker(directory int) bool {
	manifest := C.openat(directory, c'manifest.txt', C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	if manifest < 0 { return false }
	mut manifest_info := C.stat{}
	mut header := [16]u8{}
	valid_manifest := unsafe { C.fstat(manifest, &manifest_info) } == 0
		&& u32(manifest_info.st_mode) & u32(C.S_IFMT) == u32(C.S_IFREG)
		&& manifest_info.st_size >= 15 && manifest_info.st_size <= 512 * 1024 * 1024
		&& desktop_read(manifest, unsafe { &header[0] }, 15) == 15
		&& unsafe { tos(&header[0], 15) } == 'VINIX BACKUP 1\n'
	desktop_close(manifest)
	if !valid_manifest { return false }
	fd := C.openat(directory, c'complete', C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC, 0)
	if fd < 0 { return false }
	defer { desktop_close(fd) }
	mut info := C.stat{}
	if unsafe { C.fstat(fd, &info) } != 0 || u32(info.st_mode) & u32(C.S_IFMT) != u32(C.S_IFREG)
		|| info.st_size != backup_marker.len { return false }
	mut buffer := [32]u8{}
	n := desktop_read(fd, unsafe { &buffer[0] }, u64(backup_marker.len))
	return n == backup_marker.len && unsafe { tos(&buffer[0], backup_marker.len) } == backup_marker
}

fn backup_safe_name(name string) bool {
	if name.len == 0 || name == '.' || name == '..' { return false }
	for byte in name { if byte < 0x20 || byte == 0x7f || byte == `/` { return false } }
	return true
}

fn backup_manifest_row(fd int, kind string, path string, size u64) bool {
	size_text := size.str()
	record := '${kind}\t${size_text}\t${path}\n'
	defer { unsafe { size_text.free() record.free() } }
	return desktop_write_all(fd, record.str, u64(record.len))
}
