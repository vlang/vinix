// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

struct CachePartial {
	fd int
	device u64
	inode u64
	bytes u64
}

struct CachePromotionOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	flush fn (int) int = atomic_flush
}

fn open_cache_partial(parent int, name string, path string) !CachePartial {
	if name == '' || name.contains('\x00') { return error('partial download requires a valid regular-file path') }
	fd := C.openat(parent, name.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot open ordinary partial download: ${path}') }
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || info.st_mode & 0o170000 != 0o100000 || info.st_size < 0 || info.st_nlink != 1 {
		C.close(fd)
		return error('partial download must be an ordinary regular file without hard links; inspect retained data before retrying: ${path}')
	}
	return CachePartial{ fd: fd, device: u64(info.st_dev), inode: u64(info.st_ino), bytes: u64(info.st_size) }
}

fn check_cache_partial(parent int, name string, partial CachePartial) ! {
	mut opened := C.stat{}
	mut named := C.stat{}
	if C.fstat(partial.fd, &opened) != 0 || opened.st_mode & 0o170000 != 0o100000
		|| opened.st_nlink != 1 || opened.st_size < 0 || u64(opened.st_size) != partial.bytes
		|| C.fstatat(parent, name.str, &named, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o100000 || u64(named.st_dev) != partial.device || u64(named.st_ino) != partial.inode {
		return error('partial download changed before cache publication; inspect retained data and retry')
	}
}

fn validate_download_partial(path string) ! {
	partial := open_cache_partial(C.AT_FDCWD, path, path)!
	defer { C.close(partial.fd) }
	check_cache_partial(C.AT_FDCWD, path, partial)!
}

fn promote_cached_payload(directory string, payload Payload) ! {
	promote_cached_payload_with(directory, payload, CachePromotionOptions{})!
}

fn flush_cache_descriptor(fd int, flush fn (int) int) bool {
	for {
		if flush(fd) == 0 { return true }
		if C.errno != C.EINTR { return false }
	}
	return false
}

// Capture the object directory and partial once. A complete retained download
// bypasses transport, so it must independently satisfy output link/identity
// rules before chmod, flushing or atomic publication.
fn promote_cached_payload_with(directory string, payload Payload, options CachePromotionOptions) ! {
	if !digest_valid(payload.sha256) { return error('invalid cached payload identity') }
	parent := directory + '/objects'
	name := payload.sha256 + '.part'
	path := parent + '/' + name
	defer { unsafe { parent.free(); name.free(); path.free() } }
	fd := C.open(parent.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot open ordinary package object directory') }
	defer { C.close(fd) }
	mut info := C.stat{}
	if C.fstat(fd, &info) != 0 || info.st_mode & 0o170000 != 0o040000 { return error('cannot inspect package object directory') }
	device := u64(info.st_dev)
	inode := u64(info.st_ino)
	partial := open_cache_partial(fd, name, path)!
	defer { C.close(partial.fd) }
	options.checkpoint('opened', path)!
	check_cache_partial(fd, name, partial)!
	if partial.bytes != payload.bytes { return error('partial download size differs from authenticated length') }
	digest := hash_opened(partial.fd, payload.bytes, path, HashReadOptions{})!
	defer { unsafe { digest.free() } }
	if digest != payload.sha256 { return error('partial download checksum differs from authenticated payload') }
	check_cache_partial(fd, name, partial)!
	if !atomic_parent_matches(parent, device, inode) { return error('package object directory changed before cache publication') }
	if C.fchmod(partial.fd, 0o444) != 0 { return error('cannot set captured cached payload permissions') }
	if !flush_cache_descriptor(partial.fd, options.flush) {
		return error('cannot flush captured cached payload; inspect retained partial data and check storage before retrying')
	}
	check_cache_partial(fd, name, partial)!
	if !atomic_parent_matches(parent, device, inode) { return error('package object directory changed before cache publication') }
	// renameat replaces a directory symlink itself instead of moving inside it.
	if C.renameat(fd, name.str, fd, payload.sha256.str) != 0 { return error('cannot atomically publish verified cached payload; check storage and retry') }
	if !flush_cache_descriptor(fd, options.flush) { return error('cached payload saved, but object directory flush failed; inspect cache and check storage before retrying') }
	if !atomic_parent_matches(parent, device, inode) { return error('cached payload saved in its captured directory, but object directory path changed; inspect cache before retrying') }
}
