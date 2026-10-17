// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

// Native calls consume these buffers synchronously. Return an independent
// string and retire libc's allocation, including in manual-free builds.
fn publisher_real_path(path string) !string {
	resolved := C.realpath(path.str, unsafe { nil })
	if resolved == unsafe { nil } { return error('cannot resolve publisher workspace parent') }
	defer { unsafe { C.free(resolved) } }
	return unsafe { cstring_to_vstring(resolved) }
}

fn publisher_entry_exists(path string) bool {
	mut info := C.stat{}
	return C.lstat(path.str, unsafe { &info }) == 0
}

fn publisher_path(path string) !string {
	if path == '' || path.len > 4096 || path.contains('\x00') {
		return error('publisher workspace requires a nonempty path of at most 4096 bytes without NUL bytes')
	}
	mut end := path.len
	for end > 1 && path[end - 1] == `/` { end-- }
	return path[..end]
}

// Resolve parent aliases once, after admitting the actual leaf without following
// it. Subsequent publisher operations use controlled physical ancestors.
fn publisher_workspace(repository string, create bool) !string {
	path := publisher_path(repository)!
	defer { unsafe { path.free() } }
	if create && !publisher_entry_exists(path) {
		target := export_target(path, 'publisher workspace')!
		defer { unsafe { target.free() } }
		if C.mkdir(target.str, 0o755) != 0 { return error('cannot create publisher workspace; check directory permissions and disk space') }
	}
	fd := capture_prepared_root(path, 'publisher workspace')!
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_uid != u32(os.geteuid()) || info.st_mode & 0o022 != 0 {
		return error('publisher workspace must be owned by this administrator and not writable by other users')
	}
	physical := publisher_real_path(path)!
	check_export_parent(physical, 'publisher workspace') or { unsafe { physical.free() }; return err }
	if !atomic_parent_matches(physical, u64(info.st_dev), u64(info.st_ino)) {
		unsafe { physical.free() }
		return error('publisher workspace changed during admission; restore a stable directory and retry')
	}
	return physical
}

// Compare directory identities instead of lexical prefixes. This also rejects
// an output reached through a parent alias into the captured source namespace,
// before creating any output parents or lock files. Keep source contents and
// publisher ancestors stable; this is not a snapshot of concurrent owner edits.
fn publisher_outside_source(source int, repository string) ! {
	path := publisher_path(repository)!
	defer { unsafe { path.free() } }
	// Preserve the filesystem meaning of alias/.. instead of cleaning it
	// lexically before the directory-identity comparison.
	mut existing := path.clone()
	if !path.starts_with('/') {
		resolved := C.getcwd(unsafe { nil }, 0)
		if resolved == unsafe { nil } { unsafe { existing.free() }; return error('cannot determine publisher working directory') }
		cwd := unsafe { cstring_to_vstring(resolved) }
		unsafe { C.free(resolved); existing.free() }
		existing = cwd + '/' + path
		unsafe { cwd.free() }
	}
	for !publisher_entry_exists(existing) {
		next := os.dir(existing)
		unsafe { existing.free() }
		existing = next
	}
	defer { unsafe { existing.free() } }
	mut directory := C.open(existing.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NONBLOCK)
	if directory < 0 { return error('cannot inspect publisher output ancestor') }
	defer { C.close(directory) }
	mut original := C.stat{}
	if C.fstat(source, unsafe { &original }) != 0 { return error('cannot inspect captured package source') }
	for {
		mut current := C.stat{}
		if C.fstat(directory, unsafe { &current }) != 0 { return error('cannot inspect publisher output ancestor') }
		if current.st_dev == original.st_dev && current.st_ino == original.st_ino {
			return error('publisher workspace must be outside the package source tree')
		}
		parent := C.openat(directory, c'..', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
		if parent < 0 { return error('cannot inspect publisher output parent') }
		mut info := C.stat{}
		if C.fstat(parent, unsafe { &info }) != 0 { C.close(parent); return error('cannot inspect publisher output parent') }
		if current.st_dev == info.st_dev && current.st_ino == info.st_ino { C.close(parent); return }
		C.close(directory)
		directory = parent
	}
}
