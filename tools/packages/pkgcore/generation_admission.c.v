// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Admit the complete namespace before recursive flushing or activation. Keep
// only one directory stream open, including for deeply nested package paths.
fn generation_entry(mut expected map[string]u32, path string, mode u32) ! {
	for i, c in path {
		if c != `/` { continue }
		prefix := unsafe { tos(path.str, i) }
		if prefix in expected && expected[prefix] != 0 { return error('generation file/directory collision: ${path}') }
		expected[prefix] = 0
	}
	if path in expected { return error('duplicate generation entry: ${path}') }
	expected[path] = mode
}

fn scan_generation_directory(root string, relative string, expected map[string]u32, flushed bool, remaining int, mut pending []string) !int {
	path := if relative == '' { root.clone() } else { root + '/' + relative }
	defer { unsafe { path.free() } }
	fd := C.open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('generation directory must be ordinary: ${path}') }
	mut info := C.stat{}
	mode := if flushed { u32(0o755) } else if relative == '' { u32(0o700) } else { u32(0) }
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o040000
		|| info.st_uid != u32(C.geteuid()) || (mode != 0 && info.st_mode & 0o7777 != mode) {
		C.close(fd)
		return error('generation directory ownership or permissions changed: ${path}')
	}
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate generation directory: ${path}') }
	defer { C.closedir(stream) }
	mut count := 0
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read generation directory: ${path}') }
			break
		}
		name := unsafe { tos(&u8(&entry.d_name[0]), int(C.strlen(&char(&entry.d_name[0])))) }
		if name == '.' || name == '..' { continue }
		child := if relative == '' { name.clone() } else { relative + '/' + name }
		defer { unsafe { child.free() } }
		if child !in expected || count >= remaining { return error('unexpected generation entry: ${child}') }
		count++
		mut leaf := C.stat{}
		if C.fstatat(fd, name.str, unsafe { &leaf }, C.AT_SYMLINK_NOFOLLOW) != 0
			|| leaf.st_uid != u32(C.geteuid()) { return error('generation entry ownership or identity changed: ${child}') }
		wanted := expected[child]
		if wanted == 0 {
			if leaf.st_mode & 0o170000 != 0o040000 || (flushed && leaf.st_mode & 0o7777 != 0o755) {
				return error('generation directory type or permissions changed: ${child}')
			}
			// V clones string pushes; the queue owns its copy independently.
			pending << child
		} else if leaf.st_mode & 0o170000 != 0o100000 || leaf.st_nlink != 1 || leaf.st_mode & 0o7777 != wanted {
			return error('generation file type, link count or permissions changed: ${child}')
		}
	}
	mut named := C.stat{}
	if C.fstatat(C.AT_FDCWD, path.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o040000 || named.st_dev != info.st_dev || named.st_ino != info.st_ino {
		return error('generation directory identity changed: ${path}')
	}
	return count
}

fn verify_generation_tree(root string, state State, text string, flushed bool) ! {
	mut expected := {'apps': u32(0), 'share': u32(0), 'share/applications': u32(0),
		'state.json': u32(0o644), 'lease': u32(0o444)}
	defer { unsafe { expected.free() } }
	for installed in state.packages {
		p := installed.package
		for file in p.files {
			path := 'apps/' + p.id + '/' + file.path
			defer { unsafe { path.free() } }
			generation_entry(mut expected, path, if file.executable { u32(0o755) } else { u32(0o644) })!
		}
		if p.kind !in ['data', 'runtime'] {
			path := 'share/applications/vinix-' + p.id + '.desktop'
			defer { unsafe { path.free() } }
			generation_entry(mut expected, path, 0o644)!
		}
	}
	mut pending := []string{cap: 16}
	unsafe { pending.flags |= .noslices }
	pending << ''
	defer {
		for path in pending { unsafe { path.free() } }
		unsafe { (&array(&pending)).free() }
	}
	mut observed := 0
	mut next := 0
	for next < pending.len {
		relative := pending[next]
		next++
		observed += scan_generation_directory(root, relative, expected, flushed, expected.len - observed, mut pending)!
	}
	if observed != expected.len { return error('generation has missing entries: ${root}') }
	metadata := root + '/state.json'
	lease := root + '/lease'
	defer { unsafe { metadata.free(); lease.free() } }
	captured := read_metadata(metadata)!
	defer { unsafe { captured.free() } }
	if captured != text { return error('generation metadata changed: ${metadata}') }
	if !verified_file_with(lease, Payload{ bytes: 0,
		sha256: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' }, HashReadOptions{ mode: 0o444 }) {
		return error('generation lease changed: ${lease}')
	}
	for installed in state.packages {
		p := installed.package
		for file in p.files {
			path := root + '/apps/' + p.id + '/' + file.path
			defer { unsafe { path.free() } }
			if !verified_installed_file(path, file) { return error('generation payload changed: ${path}') }
		}
		if !verified_registration_with(root, p, RegistrationOptions{ flushed: flushed }) { return error('generation application registration changed: ${p.id}') }
	}
}
