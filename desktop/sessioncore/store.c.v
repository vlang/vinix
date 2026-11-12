// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

import os

#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

fn C.fsync(int) int
fn C.mkstemp(&u8) i32

pub fn load(path string, limit int) !string {
	info := os.lstat(path)!
	if info.get_filetype() != .regular || info.size > u64(limit) {
		return error('invalid session file')
	}
	mut file := os.open(path)!
	defer { file.close() }
	// Read through a limit even if a writer replaces or grows the file.
	mut bytes := []u8{len: limit + 1}
	defer { unsafe { bytes.free() } }
	mut n := 0
	for n < bytes.len {
		mut tail := unsafe { bytes[n..] }
		read := file.read(mut tail) or {
			if n == 0 { return err }
			break
		}
		if read == 0 { break }
		n += read
	}
	if n > limit { return error('session file too large') }
	return unsafe { tos(bytes.data, n).clone() }
}

// Atomic publication preserves the last good snapshot on any pre-rename
// failure. Files are private, including notification bodies and window state.
pub fn save(path string, record string) ! {
	if record.len > 1024 * 1024 { return error('session file too large') }
	directory := os.dir(path)
	defer { unsafe { directory.free() } }
	template_name := '${directory}/.vinix-session.XXXXXX'
	defer { unsafe { template_name.free() } }
	mut template := template_name.bytes()
	unsafe { template.flags |= .noslices }
	template << u8(0)
	defer { unsafe { template.free() } }
	fd := C.mkstemp(template.data)
	if fd < 0 { return error('could not create session snapshot') }
	temporary := unsafe { tos(template.data, template.len - 1) }
	mut published := false
	defer {
		C.close(fd)
		if !published { os.rm(temporary) or {} }
	}
	mut offset := 0
	for offset < record.len {
		n := unsafe { C.write(fd, &record.str[offset], uint(record.len - offset)) }
		if n <= 0 { return error('short session write') }
		offset += int(n)
	}
	if C.fsync(fd) != 0 { return error('could not sync session state') }
	os.rename_dir(temporary, path)!
	published = true
	parent := C.open(&char(directory.str), C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC, 0)
	if parent < 0 { return error('could not open session directory') }
	defer { C.close(parent) }
	if C.fsync(parent) != 0 {
		// Vinix fsync on the file also drains the backing block device.
		if C.errno != C.EINVAL || C.fsync(fd) != 0 {
			return error('could not sync session directory')
		}
	}
}
