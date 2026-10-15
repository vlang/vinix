// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

struct InstalledTree { fd int owner u32 device u64 }

// Readers can be ordinary accounts. The administrator-owned state directory,
// rather than the reader's UID, supplies the ownership required below it.
fn installed_tree(directory string, generation u64, id string) !InstalledTree {
	if generation == 0 || !identifier(id) { return error('invalid installed package identity') }
	mut fd := C.open(directory.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('cannot capture ordinary package state directory') }
	mut retained := false
	defer { if !retained { C.close(fd) } }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o040000 || info.st_mode & 0o022 != 0 {
		return error('package state must be an ordinary directory without write access for other accounts')
	}
	owner := u32(info.st_uid)
	mut device := u64(info.st_dev)
	number := generation.str()
	defer { unsafe { number.free() } }
	for index, part in ['generations', number, 'apps', id]! {
		next := C.openat(fd, part.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
		if next < 0 { return error('installed package parent must be an ordinary directory: ${part}') }
		if index == 0 {
			mut folder := C.stat{}
			if C.fstat(next, unsafe { &folder }) != 0 { C.close(next); return error('cannot inspect generation filesystem') }
			device = u64(folder.st_dev)
		}
		captured := owned_generation_directory(next, device, owner) or { C.close(next); return err }
		mut named := C.stat{}
		if captured.st_mode & 0o022 != 0 || (index > 0 && captured.st_mode & 0o7777 != 0o755)
			|| C.fstatat(fd, part.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
			|| named.st_mode & 0o170000 != 0o040000 || named.st_dev != captured.st_dev || named.st_ino != captured.st_ino {
			C.close(next)
			return error('installed directory ownership, identity or permissions changed: ${part}')
		}
		C.close(fd); fd = next
	}
	retained = true
	return InstalledTree{ fd: fd, owner: owner, device: device }
}

fn scan_installed_namespace(tree InstalledTree, relative string, expected map[string]u32, remaining int, mut pending []string) !int {
	fd := open_owned_generation_path(tree.fd, relative, tree.device, tree.owner)!
	info := owned_generation_directory(fd, tree.device, tree.owner) or { C.close(fd); return err }
	if info.st_mode & 0o7777 != 0o755 { C.close(fd); return error('installed directory permissions changed: ${relative}') }
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate installed package directory') }
	defer { C.closedir(stream) }
	mut count := 0
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read installed package directory') }
			break
		}
		name := unsafe { tos(&u8(&entry.d_name[0]), int(C.strlen(&char(&entry.d_name[0])))) }
		if name in ['.', '..']! { continue }
		path := if relative == '' { name.clone() } else { relative + '/' + name }
		defer { unsafe { path.free() } }
		if path !in expected || count >= remaining { return error('undeclared installed entry: ${path}') }
		count++
		mut child := C.stat{}
		if C.fstatat(fd, name.str, unsafe { &child }, C.AT_SYMLINK_NOFOLLOW) != 0 || child.st_uid != tree.owner
			|| u64(child.st_dev) != tree.device { return error('installed entry ownership or filesystem changed: ${path}') }
		mode := expected[path]
		if mode == 0 {
			if child.st_mode & 0o170000 != 0o040000 || child.st_mode & 0o7777 != 0o755 {
				return error('installed directory type or permissions changed: ${path}')
			}
			pending << path
		} else if child.st_mode & 0o170000 != 0o100000 || child.st_nlink != 1 || child.st_mode & 0o7777 != mode {
			return error('installed file type, links or permissions changed: ${path}')
		}
	}
	return count
}

fn check_installed_namespace(directory string, generation u64, p Package) ! {
	tree := installed_tree(directory, generation, p.id)!
	defer { C.close(tree.fd) }
	mut expected := map[string]u32{}
	defer { unsafe { expected.free() } }
	for file in p.files {
		if !relative_path(file.path) { return error('invalid installed payload path') }
		generation_entry(mut expected, file.path, if file.executable { u32(0o755) } else { u32(0o644) })!
	}
	mut pending := []string{cap: 16}
	unsafe { pending.flags |= .noslices }
	pending << ''
	defer { unsafe { for path in pending { path.free() }; (&array(&pending)).free() } }
	mut observed := 0
	mut next := 0
	for next < pending.len {
		path := pending[next]; next++
		observed += scan_installed_namespace(tree, path, expected, expected.len - observed, mut pending)!
	}
	if observed != expected.len { return error('installed package has missing entries') }
}

fn verify_installed_namespace(directory string, generation u64, p Package) ! {
	check_installed_namespace(directory, generation, p) or {
		message := err.msg()
		failure := '${p.id}: installed namespace verification failed: ${message}; use Repair installed or vinix-package repair, or restore trusted state parents before retrying'
		unsafe { message.free(); err.free() }
		return error(failure)
	}
}

fn installed_namespace_valid(directory string, generation u64, p Package) bool {
	verify_installed_namespace(directory, generation, p) or {
		message := err.msg(); unsafe { message.free(); err.free() }
		return false
	}
	return true
}
