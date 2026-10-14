// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

// Enumerate only the expected flat namespace, stopping at the first unexpected
// name. Never descend into an unreviewed directory or follow its leaf alias.
fn export_stage_directory(path string, expected map[string]u64, mode u32) ! {
	fd := C.open(path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_NOFOLLOW | C.O_CLOEXEC)
	if fd < 0 { return error('export directory must be ordinary: ${path}') }
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o040000
		|| info.st_uid != u32(C.geteuid()) || (mode != 0 && info.st_mode & 0o7777 != mode) {
		C.close(fd)
		return error('export directory ownership or permissions changed: ${path}')
	}
	stream := C.fdopendir(fd)
	if stream == unsafe { nil } { C.close(fd); return error('cannot enumerate export directory: ${path}') }
	defer { C.closedir(stream) }
	mut count := 0
	for {
		C.errno = 0
		entry := C.readdir(stream)
		if entry == unsafe { nil } {
			if C.errno != 0 { return error('cannot read export directory: ${path}') }
			break
		}
		// The directory stream owns this view until its next readdir call.
		name := unsafe { tos(&u8(&entry.d_name[0]), int(C.strlen(&char(&entry.d_name[0])))) }
		if name == '.' || name == '..' { continue }
		if name !in expected || count >= expected.len { return error('unexpected export entry: ${path}/${name}') }
		count++
	}
	if count != expected.len { return error('export directory has missing entries: ${path}') }
	mut named := C.stat{}
	if C.fstatat(C.AT_FDCWD, path.str, unsafe { &named }, C.AT_SYMLINK_NOFOLLOW) != 0
		|| named.st_mode & 0o170000 != 0o040000 || named.st_dev != info.st_dev || named.st_ino != info.st_ino {
		return error('export directory identity changed: ${path}')
	}
}

fn export_stage_file(path string) ! {
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) != 0 || info.st_mode & 0o170000 != 0o100000
		|| info.st_nlink != 1 || info.st_mode & 0o7777 != 0o644 {
		return error('export file must be an ordinary single-link file with mode 0644: ${path}')
	}
}

fn export_stage_metadata(path string, expected string) ! {
	export_stage_file(path)!
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	if text != expected { return error('export metadata changed: ${path}') }
}

fn export_stage_payloads(path string, objects map[string]u64, mode u32) ! {
	export_stage_directory(path, objects, mode)!
	for hash, bytes in objects {
		object := path + '/' + hash
		// V copies string keys for map iteration; retire that copy too.
		defer { unsafe { object.free(); hash.free() } }
		export_stage_file(object)!
		if !verified_file_with(object, Payload{ sha256: hash, bytes: bytes }, HashReadOptions{ mode: 0o644 }) {
			return error('export payload changed: ${object}')
		}
	}
}

// Verify the whole exported closure after callbacks, including objects copied
// before a later callback ran. Source catalogs/cache and installed state stay
// separate from this read-only admission of the unpublished export.
fn verify_mirror_stage(stage string, prepared PreparedMirror, flushed bool) ! {
	mut roots := map[string]u64{}
	defer { unsafe { roots.free() } }
	for snapshot in prepared.snapshots { roots[snapshot.repository.id] = 0 }
	if prepared.deployment_text != '' { roots[pkgprotocol.deployment_mirror_filename] = 0 }
	export_stage_directory(stage, roots, if flushed { u32(0o755) } else { u32(0o700) })!
	if prepared.deployment_text != '' {
		path := stage + '/' + pkgprotocol.deployment_mirror_filename
		defer { unsafe { path.free() } }
		export_stage_metadata(path, prepared.deployment_text)!
	}
	entries := {'index.json': u64(0), 'index.sig': u64(0), 'objects': u64(0)}
	defer { unsafe { entries.free() } }
	for snapshot in prepared.snapshots {
		path := stage + '/' + snapshot.repository.id
		objects_path := path + '/objects'
		index_path := path + '/index.json'
		signature_path := path + '/index.sig'
		signature := snapshot.signature + '\n'
		defer { unsafe { path.free(); objects_path.free(); index_path.free(); signature_path.free(); signature.free() } }
		mode := if flushed { u32(0o755) } else { u32(0) }
		export_stage_directory(path, entries, mode)!
		export_stage_metadata(index_path, snapshot.text)!
		export_stage_metadata(signature_path, signature)!
		mut objects := map[string]u64{}
		defer { unsafe { objects.free() } }
		for installed in prepared.plan.packages {
			if installed.repository != snapshot.repository.id { continue }
			for payload in installed.package.files {
				if payload.sha256 in objects && objects[payload.sha256] != payload.bytes {
					return error('mirror payload has inconsistent authenticated lengths')
				}
				objects[payload.sha256] = payload.bytes
			}
		}
		export_stage_payloads(objects_path, objects, mode)!
	}
}
