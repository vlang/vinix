// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

struct StageTarget { name string device u64 inode u64 }
struct StageDirectory { path string parent int device u64 inode u64 }

fn recovery_directory(fd int, device u64) !C.stat {
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o040000
		|| info.st_uid != u32(C.geteuid()) || u64(info.st_dev) != device {
		return error('stage recovery requires ordinary administrator-owned directories on the generation filesystem')
	}
	return info
}

fn recovery_parent(directory string) !int {
	path := directory + '/generations'
	defer { unsafe { path.free() } }
	fd := C.open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot capture generation directory for stage recovery: ${path}') }
	mut info := C.stat{}
	mut named := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o040000
		|| info.st_uid != u32(C.geteuid()) || info.st_mode & 0o022 != 0
		|| C.fstatat(C.AT_FDCWD, path.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o040000 || named.st_dev != info.st_dev || named.st_ino != info.st_ino {
		C.close(fd)
		return error('generation directory ownership, permissions or identity changed before stage recovery: ${path}')
	}
	return fd
}

fn capture_stage(parent int, name string) !StageTarget {
	mut folder := C.stat{}
	mut info := C.stat{}
	if !name.starts_with('.stage-') || name.contains('/') || name.contains('\x00')
		|| C.fstat(parent, unsafe { &folder }) != 0
		|| C.fstatat(parent, name.str, unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| info.st_mode & 0o170000 != 0o040000 || info.st_uid != u32(C.geteuid())
		|| info.st_mode & 0o022 != 0 || info.st_dev != folder.st_dev {
		return error('unsafe unpublished package stage ${name}; retain it for inspection and restore an ordinary administrator-owned directory before retrying')
	}
	return StageTarget{ name: name.clone(), device: u64(info.st_dev), inode: u64(info.st_ino) }
}

fn check_stage_name(parent int, name string, device u64, inode u64) ! {
	mut info := C.stat{}
	if C.fstatat(parent, name.str, unsafe { &info }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| info.st_mode & 0o170000 != 0o040000 || u64(info.st_dev) != device || u64(info.st_ino) != inode {
		return error('unpublished package stage directory identity changed: ${name}; retain recovery data and retry after inspection')
	}
}

// Reopen each component relative to the captured stage. Closing the preceding
// walk descriptor bounds descriptor usage independently of directory depth.
fn open_stage_path(root int, path string, device u64) !int {
	mut fd := C.openat(root, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot reopen unpublished package stage') }
	mut retained := false
	defer { if !retained { C.close(fd) } }
	if path != '' {
		parts := path.split('/')
		defer { unsafe { for part in parts { part.free() }; (&array(&parts)).free() } }
		for part in parts {
			next := C.openat(fd, part.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
			if next < 0 { return error('cannot reopen ordinary stage directory: ${path}') }
			C.close(fd); fd = next
			recovery_directory(fd, device)!
		}
	}
	retained = true
	return fd
}

fn scan_stage_tree(root int, index int, mut nodes []StageDirectory) ! {
	node := nodes[index]
	fd := open_stage_path(root, node.path, node.device)!
	info := recovery_directory(fd, node.device) or { C.close(fd); return err }
	if u64(info.st_ino) != node.inode { C.close(fd); return error('stage directory changed before recovery: ${node.path}') }
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate unpublished package stage') }
	defer { C.closedir(stream) }
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read unpublished package stage') }
			break
		}
		name := unsafe { tos(&u8(&entry.d_name[0]), int(C.strlen(&char(&entry.d_name[0])))) }
		if name in ['.', '..']! { continue }
		mut child := C.stat{}
		if C.fstatat(fd, name.str, unsafe { &child }, C.AT_SYMLINK_NOFOLLOW) != 0 { return error('cannot inspect unpublished stage entry') }
		if child.st_mode & 0o170000 != 0o040000 { continue }
		if child.st_uid != u32(C.geteuid()) || u64(child.st_dev) != node.device {
			return error('unpublished stage contains a foreign directory or filesystem; retain it for administrator inspection')
		}
		nodes << StageDirectory{ path: if node.path == '' { name.clone() } else { node.path + '/' + name },
			parent: index, device: u64(child.st_dev), inode: u64(child.st_ino) }
	}
}

// Finish enumeration before unlinking names: removal must not shift a directory
// cursor and skip entries on the target filesystem.
fn stage_leaf_names(directory int) ![]string {
	fd := C.openat(directory, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot enumerate stage directory for removal') }
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate stage directory for removal') }
	defer { C.closedir(stream) }
	mut names := []string{cap: 16}
	unsafe { names.flags |= .noslices }
	mut retained := false
	defer { if !retained { unsafe { for name in names { name.free() }; (&array(&names)).free() } } }
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read stage directory during removal') }
			break
		}
		name := unsafe { tos(&u8(&entry.d_name[0]), int(C.strlen(&char(&entry.d_name[0])))) }
		if name in ['.', '..']! { continue }
		mut child := C.stat{}
		if C.fstatat(fd, name.str, unsafe { &child }, C.AT_SYMLINK_NOFOLLOW) != 0
			|| child.st_mode & 0o170000 == 0o040000 {
			return error('stage contents changed or removal failed; retain the unpublished stage and retry recovery')
		}
		names << name
	}
	retained = true
	return names
}

fn remove_stage_directory(root int, parent int, target StageTarget, nodes []StageDirectory, index int) ! {
	node := nodes[index]
	fd := open_stage_path(root, node.path, node.device)!
	defer { C.close(fd) }
	info := recovery_directory(fd, node.device)!
	if u64(info.st_ino) != node.inode { return error('stage directory changed during recovery: ${node.path}') }
	names := stage_leaf_names(fd)!
	defer { unsafe { for name in names { name.free() }; (&array(&names)).free() } }
	for name in names {
		// unlinkat without AT_REMOVEDIR never follows a leaf alias or descends
		// into a replacement directory. Hard links only lose this stage's name.
		if C.unlinkat(fd, name.str, 0) != 0 { return error('cannot remove unpublished stage entry: ${name}') }
	}
	if index == 0 {
		check_stage_name(parent, target.name, target.device, target.inode)!
		if C.unlinkat(parent, target.name.str, C.AT_REMOVEDIR) != 0 { return error('cannot retire unpublished stage: ${target.name}') }
	} else {
		ancestor := nodes[node.parent]
		container := open_stage_path(root, ancestor.path, ancestor.device)!
		defer { C.close(container) }
		folder := recovery_directory(container, ancestor.device)!
		if u64(folder.st_ino) != ancestor.inode { return error('stage parent changed during recovery') }
		name := node.path.all_after_last('/')
		defer { unsafe { name.free() } }
		check_stage_name(container, name, node.device, node.inode)!
		if C.unlinkat(container, name.str, C.AT_REMOVEDIR) != 0 { return error('cannot remove unpublished stage directory: ${node.path}') }
	}
}

fn retire_stage(parent int, target StageTarget) ! {
	check_stage_name(parent, target.name, target.device, target.inode)!
	root := C.openat(parent, target.name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if root < 0 { return error('cannot open unpublished stage for recovery: ${target.name}') }
	defer { C.close(root) }
	info := recovery_directory(root, target.device)!
	if u64(info.st_ino) != target.inode || info.st_mode & 0o022 != 0 { return error('unpublished stage changed before recovery: ${target.name}') }
	mut nodes := []StageDirectory{cap: 16}
	unsafe { nodes.flags |= .noslices }
	defer { unsafe { for node in nodes { node.path.free() }; (&array(&nodes)).free() } }
	nodes << StageDirectory{ path: '', parent: -1, device: target.device, inode: target.inode }
	mut next := 0
	for next < nodes.len { scan_stage_tree(root, next, mut nodes)!; next++ }
	for index := nodes.len - 1; index >= 0; index-- { remove_stage_directory(root, parent, target, nodes, index)! }
}

// Validate every root before removing any abandoned stage. A partial stage
// need not have a completed state document or lease to be safely retired.
fn recover_generation_stages(directory string) ! {
	parent := recovery_parent(directory)!
	defer { C.close(parent) }
	fd := C.openat(parent, c'.', C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot enumerate generation stages') }
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate generation stages') }
	defer { C.closedir(stream) }
	mut targets := []StageTarget{cap: 16}
	unsafe { targets.flags |= .noslices }
	defer { unsafe { for target in targets { target.name.free() }; (&array(&targets)).free() } }
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read generation stages') }
			break
		}
		name := unsafe { tos(&u8(&entry.d_name[0]), int(C.strlen(&char(&entry.d_name[0])))) }
		if name.starts_with('.stage-') { targets << capture_stage(parent, name)! }
	}
	for target in targets { retire_stage(parent, target)! }
	if targets.len > 0 && C.fsync(parent) != 0 { return error('stage recovery completed, but the generation directory flush failed; inspect storage before retrying') }
}
