// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

struct DurabilityOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	flush fn (int) int = durability_flush
}

fn durability_flush(fd int) int { return C.fsync(fd) }

fn durability_matches(fd int, path string, initial C.stat, directory bool) bool {
	mut opened := C.stat{}
	mut named := C.stat{}
	kind := if directory { u32(0o040000) } else { u32(0o100000) }
	return C.fstat(fd, &opened) == 0 && opened.st_mode & 0o170000 == kind
		&& opened.st_dev == initial.st_dev && opened.st_ino == initial.st_ino
		&& (directory || opened.st_size == initial.st_size)
		&& C.fstatat(C.AT_FDCWD, path.str, &named, C.AT_SYMLINK_NOFOLLOW) == 0
		&& named.st_mode & 0o170000 == kind && named.st_dev == initial.st_dev && named.st_ino == initial.st_ino
		&& (directory || named.st_size == initial.st_size)
}

pub fn sync_file(path string) ! { sync_path_with(path, false, DurabilityOptions{})! }
pub fn sync_directory(path string) ! { sync_path_with(path, true, DurabilityOptions{})! }

// Capture before flushing. Never reopen an admitted name or follow its
// replacement; callers still need controlled ancestors and package locks.
fn sync_path_with(path string, directory bool, options DurabilityOptions) ! {
	label := if directory { 'directory' } else { 'file' }
	if path == '' || path.contains('\x00') { return error('package ${label} durability requires a valid path') }
	// A trailing slash makes O_NOFOLLOW apply after a directory alias. Remove
	// trailing separators while preserving root, then protect the actual leaf.
	mut end := path.len
	if directory { for end > 1 && path[end - 1] == `/` { end-- } }
	name := path[..end]
	defer { unsafe { name.free() } }
	flags := C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK | if directory { C.O_DIRECTORY } else { 0 }
	fd := C.open(name.str, flags)
	if fd < 0 { return error('cannot open ordinary package ${label} for durability: ${path}') }
	defer { C.close(fd) }
	mut initial := C.stat{}
	kind := if directory { u32(0o040000) } else { u32(0o100000) }
	if C.fstat(fd, &initial) != 0 || initial.st_mode & 0o170000 != kind || (!directory && initial.st_size < 0) {
		return error('package durability requires an ordinary ${label}: ${path}')
	}
	options.checkpoint('captured', name)!
	if !durability_matches(fd, name, initial, directory) { return error('package ${label} changed while flushing; inspect storage/state before retrying: ${path}') }
	for {
		if options.flush(fd) == 0 { break }
		if C.errno == C.EINTR { continue }
		return error('cannot flush captured package ${label}; inspect storage/state before retrying: ${path}')
	}
	options.checkpoint('flushed', name)!
	if !durability_matches(fd, name, initial, directory) { return error('package ${label} changed while flushing; inspect storage/state before retrying: ${path}') }
}
