// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256

struct RegistrationOptions {
	flushed bool = true
	checkpoint fn (string, string) ! = mirror_no_checkpoint
}

struct RegistrationTree {
mut:
	fds [3]int = [-1, -1, -1]!
	devices [3]u64
	inodes [3]u64
	owner u32
}

fn close_registration_tree(tree RegistrationTree) {
	for fd in tree.fds { if fd >= 0 { C.close(fd) } }
}

fn registration_directory(fd int, owner u32, device u64, mode u32) !C.stat {
	info := owned_generation_directory(fd, device, owner)!
	if mode != 0 && info.st_mode & 0o7777 != mode { return error('launcher directory permissions changed') }
	return info
}

fn capture_registration_tree(generation string, flushed bool) !RegistrationTree {
	if generation.contains('\x00') { return error('invalid launcher generation path') }
	mut tree := RegistrationTree{}
	mut accepted := false
	defer { if !accepted { close_registration_tree(tree) } }
	tree.fds[0] = C.open(generation.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if tree.fds[0] < 0 { return error('launcher generation must be an ordinary directory') }
	mut root := C.stat{}
	if C.fstat(tree.fds[0], unsafe { &root }) != 0 { return error('cannot inspect launcher generation') }
	tree.owner = u32(root.st_uid)
	tree.devices[0] = u64(root.st_dev); tree.inodes[0] = u64(root.st_ino)
	registration_directory(tree.fds[0], tree.owner, tree.devices[0], if flushed { u32(0o755) } else { u32(0o700) })!
	for index, part in ['share', 'applications']! {
		next := index + 1
		tree.fds[next] = C.openat(tree.fds[index], part.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if tree.fds[next] < 0 { return error('launcher parent must be an ordinary directory: ' + part) }
		info := registration_directory(tree.fds[next], tree.owner, tree.devices[0], if flushed { u32(0o755) } else { u32(0) })!
		tree.devices[next] = u64(info.st_dev); tree.inodes[next] = u64(info.st_ino)
	}
	check_registration_tree(tree, generation, flushed)!
	accepted = true
	return tree
}

fn check_registration_tree(tree RegistrationTree, generation string, flushed bool) ! {
	for index, part in [generation, 'share', 'applications']! {
		mode := if flushed { u32(0o755) } else if index == 0 { u32(0o700) } else { u32(0) }
		info := registration_directory(tree.fds[index], tree.owner, tree.devices[0], mode)!
		mut named := C.stat{}
		parent := if index == 0 { C.AT_FDCWD } else { tree.fds[index - 1] }
		if u64(info.st_dev) != tree.devices[index] || u64(info.st_ino) != tree.inodes[index]
			|| C.fstatat(parent, part.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
			|| named.st_mode & 0o170000 != 0o040000 || named.st_dev != info.st_dev || named.st_ino != info.st_ino
			|| named.st_uid != tree.owner || (mode != 0 && named.st_mode & 0o7777 != mode) {
			return error('launcher directory identity changed: ' + part)
		}
	}
}

fn registration_file(fd int, owner u32, device u64, bytes u64) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000 || info.st_uid != owner
		|| u64(info.st_dev) != device || info.st_mode & 0o7777 != 0o644 || info.st_size < 0 || u64(info.st_size) != bytes {
		return error('launcher file type, ownership, filesystem, permissions or size changed')
	}
	return info
}

fn check_registration(generation string, p Package, options RegistrationOptions) ! {
	if !identifier(p.id) { return error('invalid launcher package identity') }
	tree := capture_registration_tree(generation, options.flushed)!
	defer { close_registration_tree(tree) }
	options.checkpoint('captured', generation)!
	name := 'vinix-' + p.id + '.desktop'
	path := generation + '/share/applications/' + name
	text := desktop_entry(p)
	defer { unsafe { name.free(); path.free(); text.free() } }
	fd := C.openat(tree.fds[2], name.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 { return error('cannot open ordinary launcher file') }
	defer { C.close(fd) }
	options.checkpoint('opened', path)!
	info := registration_file(fd, tree.owner, tree.devices[0], u64(text.len))!
	digest := hash_opened(fd, u64(text.len), path, HashReadOptions{ mode: 0o644, checkpoint: options.checkpoint })!
	bytes := text.bytes()
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { digest.free(); bytes.free(); sum.free(); hash.free(); free(hash) } }
	hash.write(bytes)!
	hash.checksum_into(mut sum)
	expected := sum.hex()
	defer { unsafe { expected.free() } }
	if digest != expected { return error('launcher contents differ from installed metadata') }
	registration_file(fd, tree.owner, tree.devices[0], u64(text.len))!
	mut named := C.stat{}
	if C.fstatat(tree.fds[2], name.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o100000 || named.st_dev != info.st_dev || named.st_ino != info.st_ino
		|| named.st_uid != tree.owner || named.st_mode & 0o7777 != 0o644 || named.st_size != info.st_size {
		return error('launcher file identity changed while reading')
	}
	check_registration_tree(tree, generation, options.flushed)!
}

fn verified_registration_with(generation string, p Package, options RegistrationOptions) bool {
	if p.kind in ['data', 'runtime']! { return true }
	check_registration(generation, p, options) or {
		message := err.msg(); unsafe { message.free(); err.free() }
		return false
	}
	return true
}
