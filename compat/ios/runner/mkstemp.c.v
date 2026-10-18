// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn tempfile_open(path &char) i32 {
	$if linux {
		// Keep the supported Darwin filename profile within NAME_MAX bytes,
		// even when the backing filesystem admits larger directory entries.
		mut component := 0
		mut offset := usize(0)
		unsafe {
			for path[offset] != 0 {
				if path[offset] == char(47) { component = 0 } else { component++ }
				if component > 255 { darwin_set_errno(C.ENAMETOOLONG); return -1 }
				offset++
			}
		}
	}
	previous := unsafe { *C.ios_errno_address() }
	flags := C.O_RDWR | C.O_CREAT | C.O_EXCL
	result := i32(C.open(path, flags, 0o600))
	$if linux {
		if result >= 0 || unsafe { *C.ios_errno_address() } != C.ENOENT { return result }
		// Like readlink_native, resolve a parent that the kernel's absolute
		// symlink lookup loses. Open relative to its descriptor so O_EXCL
		// still protects the final component, including dangling symlinks.
		mut parent := [4096]u8{}
		mut resolved := [4096]u8{}
		mut slash := -1
		mut length := 0
		unsafe {
			for length < parent.len - 1 && path[length] != 0 {
				parent[length] = u8(path[length])
				if path[length] == char(47) { slash = length }
				length++
			}
			if slash < 0 || path[length] != 0 { return result }
			parent[if slash == 0 { 1 } else { slash }] = 0
			if C.realpath(&char(&parent[0]), &char(&resolved[0])) == nil { return -1 }
			fd := C.open(&char(&resolved[0]), C.O_PATH | C.O_DIRECTORY | C.O_CLOEXEC, 0)
			if fd < 0 { return -1 }
			retried := i32(C.openat(fd, &path[slash + 1], flags, 0o600))
			native_error := *C.ios_errno_address()
			C.close(fd)
			darwin_set_errno(if retried >= 0 { previous } else { native_error })
			return retried
		}
	}
	return result
}

fn darwin_mkstemp(path &char) i32 {
	if path == unsafe { nil } { darwin_set_errno(14); return -1 }
	length := darwin_strlen(path)
	if length == 0 { darwin_set_errno(22); return -1 }
	// Darwin's MAXPATHLEN is 1024, including the terminator. Validate before
	// changing the template; the saved random suffix fits on the stack.
	if length >= 1024 { darwin_set_errno(63); return -1 }
	// The current Vinix VFS can lose entries when creators run concurrently.
	// Serialize adapter calls with the gate already held across fork, keeping
	// a child from inheriting a lock owned by another disappearing thread.
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	mut start := length
	unsafe { for start > 0 && path[start - 1] == char(88) { start-- } }
	// Darwin accepts zero or more trailing Xs; musl requires six. Only that
	// trailing run is replaced. An empty run makes one exclusive-open attempt.
	if start == length { return i32(darwin_file_result(tempfile_open(path))) }
	count := length - start
	mut original := [1024]u8{}
	alphabet := c'0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
	unsafe {
		for i in usize(0) .. count {
			value := u8(alphabet[darwin_random_uniform(62)])
			path[start + i] = char(value)
			original[i] = value
		}
	}
	for {
		result := tempfile_open(path)
		if result >= 0 { return result }
		native_error := unsafe { *C.ios_errno_address() }
		if native_error != C.EEXIST { darwin_set_errno(darwin_native_error(native_error)); return -1 }
		// Enumerate from a fresh random starting point. This visits every
		// candidate once, including short BSD templates, without shared state.
		unsafe {
			mut i := start
			for i < length {
				value := u8(path[i])
				path[i] = match value {
					57 { char(65) }
					90 { char(97) }
					122 { char(48) }
					else { char(value + 1) }
				}
				if u8(path[i]) != original[i - start] { break }
				i++
			}
			if i == length { darwin_set_errno(17); return -1 }
		}
	}
	return -1
}
