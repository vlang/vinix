// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256

const max_signing_seed_text = 128

struct SigningSeed {
	bytes []u8
	file_sha256 string
}

struct SigningSeedOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
}

fn retire_signing_bytes(mut bytes []u8) {
	for i in 0 .. bytes.len { bytes[i] = 0 }
	unsafe { bytes.free() }
}

fn (seed SigningSeed) close() {
	mut bytes := unsafe { seed.bytes }
	retire_signing_bytes(mut bytes)
	unsafe { seed.file_sha256.free() }
}

fn private_signing_file(info C.stat) bool {
	return info.st_mode & 0o170000 == 0o100000 && info.st_uid == u32(C.geteuid())
		&& info.st_mode & 0o077 == 0 && info.st_nlink == 1
}

fn signing_hex(byte u8) int {
	if byte >= `0` && byte <= `9` { return int(byte - `0`) }
	if byte >= `a` && byte <= `f` { return int(byte - `a`) + 10 }
	if byte >= `A` && byte <= `F` { return int(byte - `A`) + 10 }
	return -1
}

// The private-file checks, decoded seed and exclusion digest all use this one
// bounded capture. No later pathname read can select a different signing file.
fn read_signing_seed(path string, options SigningSeedOptions) !SigningSeed {
	if path == '' || path.contains('\x00') { return error('publisher signing seed requires a valid private-file path') }
	fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('publisher signing seed must be a private ordinary file owned by this administrator') }
	defer { C.close(fd) }
	options.checkpoint('opened', path)!
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || !private_signing_file(info) {
		return error('publisher signing seed must be a private ordinary file owned by this administrator, without hard links')
	}
	if info.st_size < 64 || info.st_size > max_signing_seed_text {
		return error('publisher signing seed must contain 64 hex digits in at most 128 bytes')
	}
	expected := int(info.st_size)
	device := info.st_dev
	inode := info.st_ino
	options.checkpoint('sized', path)!
	mut bytes := []u8{len: expected + 1}
	defer { retire_signing_bytes(mut bytes) }
	mut done := 0
	for done < bytes.len {
		count := C.read(fd, unsafe { &u8(bytes.data) + done }, usize(bytes.len - done))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read publisher signing seed') }
		if count == 0 { break }
		done += int(count)
	}
	options.checkpoint('read', path)!
	mut named := C.stat{}
	if done != expected || C.fstat(fd, unsafe { &info }) != 0 || !private_signing_file(info) || info.st_size != expected
		|| C.fstatat(C.AT_FDCWD, path.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| !private_signing_file(named) || named.st_dev != device || named.st_ino != inode || named.st_size != expected {
		return error('publisher signing seed changed while reading; restore a stable private file and retry')
	}
	mut start := 0
	mut end := expected
	for start < end && bytes[start] in [u8(` `), `\t`, `\n`, `\v`, `\f`, `\r`]! { start++ }
	for end > start && bytes[end - 1] in [u8(` `), `\t`, `\n`, `\v`, `\f`, `\r`]! { end-- }
	if end - start != 64 { return error('publisher signing seed must contain exactly 32 bytes of hex') }
	for at in start .. end {
		if signing_hex(bytes[at]) < 0 { return error('publisher signing seed contains invalid hex') }
	}
	mut hash := sha256.new()
	defer { unsafe { hash.free(); free(hash) } }
	hash.write(bytes[..expected])!
	mut checksum := []u8{len: sha256.size}
	hash.checksum_into(mut checksum)
	digest := checksum.hex()
	unsafe { checksum.free() }
	mut seed := []u8{len: 32}
	for i in 0 .. seed.len { seed[i] = u8(signing_hex(bytes[start + i * 2]) * 16 + signing_hex(bytes[start + i * 2 + 1])) }
	return SigningSeed{ bytes: seed, file_sha256: digest }
}
