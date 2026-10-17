// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn C.mkdir(&char, u32) int

// mkdir-p for POSIX package paths. Keep one terminated prefix buffer rather
// than retaining split components, concatenations and realpath scratch. Parent
// aliases and dot components retain their filesystem meaning. Callers still
// admit the final directory's ownership, mode and no-follow identity separately.
fn make_package_directories(path string, mode u32) ! {
	if path == '' || path.contains('\x00') { return error('package directory creation requires a nonempty path without NUL bytes') }
	mut info := C.stat{}
	if C.fstatat(C.AT_FDCWD, path.str, unsafe { &info }, 0) == 0 {
		if info.st_mode & 0o170000 == 0o040000 { return }
		return error('package parent must be a directory: ' + path)
	}
	mut prefix := []u8{len: path.len + 1}
	defer { unsafe { prefix.free() } }
	for i, byte in path { prefix[i] = byte }
	for end in 1 .. path.len + 1 {
		if end < path.len && prefix[end] != `/` { continue }
		if prefix[end - 1] == `/` { continue }
		separator := prefix[end]; prefix[end] = 0
		if C.mkdir(unsafe { &char(prefix.data) }, mode) != 0 {
			if C.errno != C.EEXIST { return error('cannot create package directory; check permissions and disk space: ' + path) }
			if C.fstatat(C.AT_FDCWD, unsafe { &char(prefix.data) }, unsafe { &info }, 0) != 0 || info.st_mode & 0o170000 != 0o040000 {
				return error('package parent must be a directory: ' + path)
			}
		}
		prefix[end] = separator
	}
}
