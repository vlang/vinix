// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Capture the input namespace before creating publisher output. Parent aliases
// retain their usual path semantics; O_NOFOLLOW protects the trimmed leaf.
fn capture_prepared_root(path string, label string) !int {
	if path == '' || path.contains('\x00') {
		return error('${label} prepared root requires a nonempty path without NUL bytes')
	}
	mut end := path.len
	for end > 1 && path[end - 1] == `/` { end-- }
	name := path[..end]
	defer { unsafe { name.free() } }
	fd := C.open(name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('${label} prepared root must be an ordinary directory: ${path}') }
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || info.st_mode & 0o170000 != 0o040000 {
		C.close(fd)
		return error('${label} prepared root must be an ordinary directory: ${path}')
	}
	return fd
}
