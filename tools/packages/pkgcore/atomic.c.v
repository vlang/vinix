// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.rand

fn C.renameat(int, &char, int, &char) int

struct AtomicWriteOptions {
	exclusive bool
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	write fn (int, voidptr, usize) isize = atomic_write_bytes
	flush fn (int) int = atomic_flush
}

fn atomic_write_bytes(fd int, data voidptr, count usize) isize { return C.write(fd, data, count) }
fn atomic_flush(fd int) int { return C.fsync(fd) }

fn create_atomic_file(parent int) !(int, string) {
	for _ in 0 .. 16 {
		random := rand.bytes(16)!
		suffix := random.hex()
		unsafe { random.free() }
		name := '.package-' + suffix + '.tmp'
		unsafe { suffix.free() }
		fd := C.openat(parent, name.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK, 0o600)
		if fd >= 0 { return fd, name }
		collision := C.errno == C.EEXIST
		unsafe { name.free() }
		if !collision { return error('cannot create a private package metadata temporary file; check directory permissions and disk space') }
	}
	return error('cannot allocate a unique package metadata temporary file')
}

fn atomic_name_matches(parent int, name string, fd int) bool {
	mut opened := C.stat{}
	mut named := C.stat{}
	return C.fstat(fd, unsafe { &opened }) == 0 && C.fstatat(parent, name.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) == 0
		&& named.st_mode & 0o170000 == 0o100000 && opened.st_dev == named.st_dev && opened.st_ino == named.st_ino
}

fn check_atomic_temporary(parent int, name string, fd int, expected int) ! {
	mut info := C.stat{}
	if !atomic_name_matches(parent, name, fd) || C.fstat(fd, unsafe { &info }) != 0
		|| info.st_mode & 0o170000 != 0o100000 || info.st_nlink != 1 || info.st_size != expected {
		return error('package metadata temporary file changed; restore a stable directory and retry')
	}
}

fn atomic_parent_matches(path string, device u64, inode u64) bool {
	mut named := C.stat{}
	return C.fstatat(C.AT_FDCWD, path.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) == 0
		&& named.st_mode & 0o170000 == 0o040000 && u64(named.st_dev) == device && u64(named.st_ino) == inode
}

pub fn atomic_write(path string, text string) ! {
	atomic_write_with(path, text, AtomicWriteOptions{})!
}

// Save only to a new name, including when another writer creates it after
// preflight. Publication and flushing use the same captured parent descriptor.
pub fn atomic_write_new(path string, text string) ! {
	atomic_write_with(path, text, AtomicWriteOptions{ exclusive: true })!
}

fn atomic_publish_new(parent int, source string, destination string) int {
	$if macos {
		return C.renameatx_np(parent, source.str, parent, destination.str, C.RENAME_EXCL)
	} $else $if linux {
		return int(C.syscall(i64(C.SYS_renameat2), parent, source.str, parent, destination.str, u32(1)))
	} $else { return -1 }
}

fn atomic_new_file_matches(parent int, name string, fd int, size int) bool {
	mut info := C.stat{}
	return atomic_name_matches(parent, name, fd) && C.fstat(fd, unsafe { &info }) == 0 && info.st_nlink == 1
		&& info.st_mode & 0o7777 == 0o644 && info.st_size == size
}

// Capture the parent once. Creation, publication, cleanup and directory flush
// use that descriptor; neither a stale .new alias nor a reopened path is used.
fn atomic_write_with(path string, text string, options AtomicWriteOptions) ! {
	if path == '' || path.contains('\x00') { return error('package metadata requires a valid file path') }
	if text.len > max_metadata { return error('package metadata exceeds its size limit') }
	split := path.last_index('/') or { -1 }
	mut end := split
	for end > 0 && path[end - 1] == `/` { end-- }
	parent := if split < 0 { '.'.clone() } else if end == 0 { '/'.clone() } else { path[..end] }
	name := if split < 0 { path.clone() } else { path[split + 1..] }
	defer { unsafe { parent.free(); name.free() } }
	if name in ['', '.', '..']! { return error('package metadata requires a valid file name') }
	directory := C.open(parent.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if directory < 0 { return error('cannot open ordinary package metadata parent directory') }
	defer { C.close(directory) }
	mut info := C.stat{}
	// Native stat calls consume scratch synchronously; keep it on the stack.
	if C.fstat(directory, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o040000 {
		return error('cannot inspect package metadata parent directory')
	}
	device := u64(info.st_dev)
	inode := u64(info.st_ino)
	if options.exclusive {
		mut existing := C.stat{}
		if C.fstatat(directory, name.str, unsafe { &existing }, C.AT_SYMLINK_NOFOLLOW) == 0 { return error('package metadata destination already exists; choose a new file name') }
		if C.errno != C.ENOENT { return error('cannot inspect new package metadata destination') }
	}
	fd, leaf := create_atomic_file(directory)!
	temporary := if parent == '/' { parent + leaf } else { parent + '/' + leaf }
	mut published := false
	defer {
		// A replaced name belongs to the replacer. Never follow or delete it.
		if !published && atomic_name_matches(directory, leaf, fd) { C.unlinkat(directory, leaf.str, 0) }
		C.close(fd)
		unsafe { leaf.free(); temporary.free() }
	}
	options.checkpoint('created', temporary)!
	check_atomic_temporary(directory, leaf, fd, 0)!
	mut offset := 0
	for offset < text.len {
		written := options.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		if written < 0 && C.errno == C.EINTR { continue }
		if written <= 0 || written > text.len - offset { return error('cannot write package metadata; check disk space') }
		offset += int(written)
	}
	options.checkpoint('written', temporary)!
	check_atomic_temporary(directory, leaf, fd, text.len)!
	if C.fchmod(fd, 0o644) != 0 || options.flush(fd) != 0 { return error('cannot flush package metadata before publication; check storage and retry') }
	options.checkpoint('flushed', temporary)!
	check_atomic_temporary(directory, leaf, fd, text.len)!
	if options.exclusive && !atomic_new_file_matches(directory, leaf, fd, text.len) { return error('new package metadata temporary file changed before publication') }
	if !atomic_parent_matches(parent, device, inode) { return error('package metadata parent path changed before publication; restore it and retry') }
	// renameat replaces a leaf directory symlink itself. os.rename may instead
	// move the temporary inside the referenced directory.
	if options.exclusive {
		if atomic_publish_new(directory, leaf, name) != 0 { return error('cannot exclusively publish package metadata; destination must be new and storage must support exclusive atomic rename') }
	} else if C.renameat(directory, leaf.str, directory, name.str) != 0 { return error('cannot atomically replace package metadata; check its destination and storage') }
	published = true
	options.checkpoint('published', temporary) or {
		cause := err.msg()
		message := 'package metadata saved, but post-publication check failed; inspect state before retrying: ' + cause
		unsafe { cause.free(); err.free() }
		return error(message)
	}
	if options.flush(directory) != 0 { return error('package metadata saved, but directory flush failed; inspect state and check storage before retrying') }
	if !atomic_parent_matches(parent, device, inode) { return error('package metadata saved in its captured directory, but parent path changed; inspect state before retrying') }
	if options.exclusive && !atomic_new_file_matches(directory, name, fd, text.len) { return error('package metadata saved, but its final file changed; inspect the saved file before retrying') }
}
