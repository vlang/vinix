// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn C.getcwd(&char, usize) &char
fn C.realpath(&char, &char) &char

// Preserve the existing lexical absolute-path contract without the standard
// normalizer's retained cwd, split-component and builder scratch.
fn mirror_absolute_path(path string) !string {
	mut source := path
	mut owned := ''
	if !path.starts_with('/') {
		resolved := C.getcwd(unsafe { nil }, 0)
		if resolved == unsafe { nil } { return error('cannot determine offline mirror working directory') }
		cwd := unsafe { cstring_to_vstring(resolved) }
		unsafe { C.free(resolved) }
		owned = cwd + '/' + path
		unsafe { cwd.free() }
		source = owned
	}
	defer { unsafe { owned.free() } }
	mut bytes := []u8{cap: source.len + 1}
	mut starts := []int{cap: source.len / 2 + 1}
	unsafe { bytes.flags |= .noslices; starts.flags |= .noslices }
	defer { unsafe { bytes.free(); starts.free() } }
	bytes << u8(`/`)
	mut start := 0
	for end in 0 .. source.len + 1 {
		if end < source.len && source[end] != `/` { continue }
		length := end - start
		if length == 2 && source[start] == `.` && source[start + 1] == `.` {
			if starts.len > 0 { bytes.trim(starts.pop()) }
		} else if length > 0 && !(length == 1 && source[start] == `.`) {
			starts << bytes.len
			if bytes.len > 1 { bytes << u8(`/`) }
			for i in start .. end { bytes << source[i] }
		}
		start = end + 1
	}
	return bytes.bytestr()
}

fn mirror_real_path(path string) !string {
	resolved := C.realpath(path.str, unsafe { nil })
	if resolved == unsafe { nil } { return error('cannot resolve offline mirror parent') }
	defer { unsafe { C.free(resolved) } }
	return unsafe { cstring_to_vstring(resolved) }
}
