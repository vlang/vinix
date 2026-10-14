// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import os

struct HashReadOptions {
	exact bool
	bytes u64
	checkpoint fn (string, string) ! = mirror_no_checkpoint
}

pub fn hash_file(path string) !string {
	return hash_file_with(path, HashReadOptions{})
}

pub fn verified_file(path string, payload Payload) bool {
	return verified_file_with(path, payload, HashReadOptions{})
}

fn verified_file_with(path string, payload Payload, options HashReadOptions) bool {
	digest := hash_file_with(path, HashReadOptions{ ...options, exact: true, bytes: payload.bytes }) or {
		message := err.msg()
		unsafe { message.free(); err.free() }
		return false
	}
	valid := digest == payload.sha256
	unsafe { digest.free() }
	return valid
}

// Capture type, size and contents through one descriptor. Verification admits
// the signed length before hashing; generic publishing hashes the captured size.
fn hash_file_with(path string, options HashReadOptions) !string {
	if path.contains('\x00') { return error('payload must be a regular file: ${path}') }
	fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot open regular payload file: ${path}') }
	defer { C.close(fd) }
	options.checkpoint('opened', path)!
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || info.st_mode & 0o170000 != 0o100000 || info.st_size < 0 {
		return error('payload must be a regular file: ${path}')
	}
	expected := u64(info.st_size)
	if options.exact && expected != options.bytes {
		return error('payload size differs from authenticated length: ${path}')
	}
	device := u64(info.st_dev)
	inode := u64(info.st_ino)
	options.checkpoint('sized', path)!
	mut hash := sha256.new()
	mut buffer := []u8{len: 64 * 1024}
	defer {
		unsafe { buffer.free(); hash.free(); free(hash) }
	}
	mut done := u64(0)
	for done < expected {
		remaining := expected - done
		amount := if remaining < u64(buffer.len) { int(remaining) } else { buffer.len }
		count := C.read(fd, buffer.data, usize(amount))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read payload: ${path}') }
		if count == 0 { return error('payload changed size while hashing: ${path}') }
		hash.write(buffer[..int(count)])!
		done += u64(count)
		options.checkpoint('block', path)!
	}
	// Do not follow a growing file to EOF. Read at most its admitted length plus
	// one sentinel, then recheck both the descriptor and its named identity.
	for {
		count := C.read(fd, buffer.data, 1)
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read payload: ${path}') }
		if count != 0 { return error('payload changed size while hashing: ${path}') }
		break
	}
	options.checkpoint('read', path)!
	if C.fstat(fd, &info) != 0 || info.st_size < 0 || u64(info.st_size) != expected {
		return error('payload changed size while hashing: ${path}')
	}
	named := os.lstat(path) or { return error('payload path changed while hashing: ${path}') }
	if named.mode & 0o170000 != 0o100000 || named.dev != device || named.inode != inode || named.size != expected {
		return error('payload path changed while hashing: ${path}')
	}
	mut digest := []u8{len: sha256.size}
	hash.checksum_into(mut digest)
	result := digest.hex()
	unsafe { digest.free() }
	return result
}
