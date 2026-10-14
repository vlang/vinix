// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.rand
import tools.packages.signing as ed25519

fn C.renameatx_np(int, &char, int, &char, u32) int

struct KeygenOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	write fn (int, voidptr, usize) isize = atomic_write_bytes
	flush fn (int) int = atomic_flush
}

fn signing_seed_public(bytes []u8) string {
	mut private_key := ed25519.new_key_from_seed(bytes)
	defer { retire_signing_bytes(mut private_key) }
	public_key := private_key.public_key()
	defer { unsafe { public_key.free() } }
	return public_key.hex()
}

// Recovery never generates a different seed or changes an existing one.
pub fn key_public(path string) !string {
	seed := read_signing_seed(path, SigningSeedOptions{})!
	defer { seed.close() }
	return signing_seed_public(seed.bytes)
}

fn keygen_parent_matches(path string, fd int, initial C.stat) bool {
	mut opened := C.stat{}
	mut named := C.stat{}
	return C.fstat(fd, &opened) == 0 && opened.st_mode & 0o170000 == 0o040000
		&& opened.st_uid == u32(C.geteuid()) && opened.st_mode & 0o022 == 0
		&& opened.st_dev == initial.st_dev && opened.st_ino == initial.st_ino
		&& C.fstatat(C.AT_FDCWD, path.str, &named, C.AT_SYMLINK_NOFOLLOW) == 0
		&& named.st_mode & 0o170000 == 0o040000 && named.st_uid == u32(C.geteuid()) && named.st_mode & 0o022 == 0
		&& named.st_dev == initial.st_dev && named.st_ino == initial.st_ino
}

fn keygen_temporary(parent int) !(int, string) {
	for _ in 0 .. 16 {
		random := rand.bytes(16)!
		suffix := random.hex()
		unsafe { random.free() }
		name := '.package-key-' + suffix + '.tmp'
		unsafe { suffix.free() }
		fd := C.openat(parent, name.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK, 0o600)
		if fd >= 0 { return fd, name }
		collision := C.errno == C.EEXIST
		unsafe { name.free() }
		if !collision { return error('cannot create a private signing seed temporary file; check directory permissions and disk space') }
	}
	return error('cannot allocate a unique signing seed temporary file')
}

fn keygen_file_matches(parent int, name string, fd int, size int) bool {
	mut info := C.stat{}
	return atomic_name_matches(parent, name, fd) && C.fstat(fd, &info) == 0
		&& private_signing_file(info) && info.st_mode & 0o777 == 0o600 && info.st_size == size
}

fn keygen_flush(fd int, options KeygenOptions) bool {
	for {
		if options.flush(fd) == 0 { return true }
		if C.errno != C.EINTR { return false }
	}
	return false
}

fn keygen_publish(parent int, source string, destination string) int {
	$if macos {
		return C.renameatx_np(parent, source.str, parent, destination.str, C.RENAME_EXCL)
	} $else $if linux {
		return int(C.syscall(i64(C.SYS_renameat2), parent, source.str, parent, destination.str, u32(1)))
	} $else {
		return -1
	}
}

pub fn keygen(path string) !string { return keygen_with(path, KeygenOptions{}) }

// Write and flush privately, then publish a new name in the captured directory.
// Ancestors must remain controlled; same-user in-place edits are not frozen.
fn keygen_with(path string, options KeygenOptions) !string {
	if path == '' || path.contains('\x00') { return error('signing seed requires a valid new-file path') }
	split := path.last_index('/') or { -1 }
	mut end := split
	for end > 0 && path[end - 1] == `/` { end-- }
	parent := if split < 0 { '.'.clone() } else if end == 0 { '/'.clone() } else { path[..end] }
	name := if split < 0 { path.clone() } else { path[split + 1..] }
	defer { unsafe { parent.free(); name.free() } }
	if name in ['', '.', '..']! { return error('signing seed requires a valid new file name') }
	directory := C.open(parent.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if directory < 0 { return error('signing seed parent must be an ordinary directory owned by this publisher, without group/other write access') }
	defer { C.close(directory) }
	mut initial := C.stat{}
	if C.fstat(directory, &initial) != 0 || !keygen_parent_matches(parent, directory, initial) {
		return error('signing seed parent must be an ordinary directory owned by this publisher, without group/other write access')
	}
	options.checkpoint('captured', parent)!
	if !keygen_parent_matches(parent, directory, initial) { return error('signing seed parent changed; restore a stable owned directory before retrying') }
	mut existing := C.stat{}
	if C.fstatat(directory, name.str, &existing, C.AT_SYMLINK_NOFOLLOW) == 0 { return error('signing seed file already exists; use key-public to recover its public key') }
	if C.errno != C.ENOENT { return error('cannot inspect new signing seed destination') }
	fd, leaf := keygen_temporary(directory)!
	temporary := if parent == '/' { parent + leaf } else { parent + '/' + leaf }
	mut published := false
	defer {
		if !published && atomic_name_matches(directory, leaf, fd) { C.unlinkat(directory, leaf.str, 0) }
		C.close(fd)
		unsafe { leaf.free(); temporary.free() }
	}
	if C.fchmod(fd, 0o600) != 0 { return error('cannot protect signing seed temporary file') }
	options.checkpoint('created', temporary)!
	if !keygen_file_matches(directory, leaf, fd, 0) { return error('signing seed temporary file changed; inspect the private directory before retrying') }
	mut seed := rand.bytes(ed25519.seed_size)!
	defer { retire_signing_bytes(mut seed) }
	mut text := []u8{len: 65}
	defer { retire_signing_bytes(mut text) }
	hex := '0123456789abcdef'
	for i, byte in seed { text[i * 2] = hex[int(byte >> 4)]; text[i * 2 + 1] = hex[int(byte & 15)] }
	text[64] = `\n`
	mut offset := 0
	for offset < text.len {
		written := options.write(fd, unsafe { &u8(text.data) + offset }, usize(text.len - offset))
		if written < 0 && C.errno == C.EINTR { continue }
		if written <= 0 || written > text.len - offset { return error('cannot write signing seed; check storage and retry') }
		offset += int(written)
	}
	options.checkpoint('written', temporary)!
	if !keygen_file_matches(directory, leaf, fd, text.len) { return error('signing seed temporary file changed; inspect the private directory before retrying') }
	if !keygen_flush(fd, options) { return error('cannot flush signing seed before publication; check storage and retry') }
	options.checkpoint('flushed', temporary)!
	if !keygen_file_matches(directory, leaf, fd, text.len) || !keygen_parent_matches(parent, directory, initial) {
		return error('signing seed or parent changed before publication; inspect the private directory before retrying')
	}
	if keygen_publish(directory, leaf, name) != 0 { return error('cannot exclusively publish new signing seed; destination must be new and storage must support exclusive atomic rename') }
	published = true
	options.checkpoint('published', path) or { unsafe { err.free() }; return error('signing seed saved, but post-publication check failed; inspect the saved seed and storage before retrying; key-public can recover its public key') }
	if !keygen_flush(directory, options) { return error('signing seed saved, but directory flush failed; inspect the saved seed and storage before retrying; key-public can recover its public key') }
	if !keygen_parent_matches(parent, directory, initial) || !keygen_file_matches(directory, name, fd, text.len) {
		return error('signing seed saved in its captured directory, but its path changed; inspect the saved seed before retrying; key-public can recover its public key')
	}
	return signing_seed_public(seed)
}
