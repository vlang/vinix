// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn C.read(int, voidptr, usize) isize

struct MetadataReadOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
}

pub fn read_metadata(path string) !string {
	return read_metadata_with(path, MetadataReadOptions{})
}

// Admit and read one descriptor. Reopening a checked pathname could follow a
// substituted alias, wait on a FIFO or allocate from an unchecked new size.
fn read_metadata_with(path string, options MetadataReadOptions) !string {
	if path.contains('\x00') { return error('metadata must be a bounded regular file: ${path}') }
	fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('metadata must be a bounded regular file: ${path}') }
	defer { C.close(fd) }
	options.checkpoint('opened', path)!
	mut info := C.stat{}
	// fstat consumes this pointer synchronously; keep its scratch on the stack.
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000
		|| info.st_size < 0 || info.st_size > max_metadata {
		return error('metadata must be a bounded regular file: ${path}')
	}
	expected := int(info.st_size)
	options.checkpoint('sized', path)!
	// One extra byte detects growth without following the new file size. Every
	// read and allocation stays within the admitted size plus this sentinel.
	mut bytes := []u8{len: expected + 1}
	defer { unsafe { bytes.free() } }
	mut done := 0
	for done < bytes.len {
		count := C.read(fd, unsafe { &u8(bytes.data) + done }, usize(bytes.len - done))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read package metadata: ${path}') }
		if count == 0 { break }
		done += int(count)
	}
	options.checkpoint('read', path)!
	if done != expected || C.fstat(fd, unsafe { &info }) != 0 || info.st_size != expected {
		return error('metadata changed size while reading; restore a stable file and retry: ${path}')
	}
	return unsafe { tos(&u8(bytes.data), done).clone() }
}
