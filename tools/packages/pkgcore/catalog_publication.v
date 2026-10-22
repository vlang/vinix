// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// A catalog workspace carries the reviewed import lock. Absence preserves plain
// pack/pack-root workspaces; every other open failure, including a dangling
// alias, refuses publication. Read only the admitted descriptor and size.
fn publication_catalog_text(path string, options MetadataReadOptions) !(bool, string) {
	fd := C.open(path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if fd < 0 {
		if C.errno == C.ENOENT {
			mut named := C.stat{}
			if C.lstat(path.str, unsafe { &named }) != 0 && C.errno == C.ENOENT { return false, '' }
		}
		return error('publisher catalog lock must be an ordinary controlled single-link file')
	}
	defer { C.close(fd) }
	options.checkpoint('opened', path)!
	mut info := C.stat{}
	if C.fstat(fd, unsafe { &info }) != 0 || !publication_catalog_file(info) {
		return error('publisher catalog lock must be an ordinary controlled single-link file')
	}
	if info.st_size < 0 || info.st_size > max_metadata {
		return error('publisher catalog lock exceeds metadata limit')
	}
	expected := int(info.st_size)
	device := info.st_dev
	inode := info.st_ino
	mode := info.st_mode
	options.checkpoint('sized', path)!
	mut bytes := []u8{len: expected + 1}
	defer { unsafe { bytes.free() } }
	mut done := 0
	for done < bytes.len {
		count := C.read(fd, unsafe { &u8(bytes.data) + done }, usize(bytes.len - done))
		if count < 0 && C.errno == C.EINTR { continue }
		if count < 0 { return error('cannot read publisher catalog lock') }
		if count == 0 { break }
		done += int(count)
	}
	options.checkpoint('read', path)!
	mut named := C.stat{}
	if done != expected || C.fstat(fd, unsafe { &info }) != 0 || !publication_catalog_file(info)
		|| info.st_size != expected || info.st_mode != mode
		|| C.lstat(path.str, unsafe { &named }) != 0 || !publication_catalog_file(named)
		|| named.st_dev != device || named.st_ino != inode || named.st_size != expected || named.st_mode != mode {
		return error('publisher catalog lock changed while reading; restore a stable lock and retry')
	}
	return true, unsafe { tos(&u8(bytes.data), done).clone() }
}

fn publication_catalog_file(info C.stat) bool {
	return info.st_mode & 0o170000 == 0o100000 && info.st_mode & 0o022 == 0
		&& info.st_uid == u32(C.geteuid()) && info.st_nlink == 1
}

// Compare complete semantic declarations, including file pins and permissions.
// Only the four set-like manifest collections are canonicalized. Argument order
// remains significant. The imported lock owns its records; actual records stay
// borrowed from publication_with_seed throughout this check.
fn publication_catalog_matches(repository string, packages []Package) ! {
	path := repository + '/catalog.json'
	defer { unsafe { path.free() } }
	present, text := publication_catalog_text(path, MetadataReadOptions{})!
	defer { unsafe { text.free() } }
	if !present { return }
	catalog := catalog_recipe(text) or {
		message := err.msg()
		diagnostic := 'publisher catalog lock: ' + message
		unsafe {
			message.free()
			err.free()
		}
		return error(diagnostic)
	}
	defer { close_decoded_catalog(catalog) }
	if packages.len != catalog.packages.len {
		return error('publisher manifest set differs from catalog lock; rebuild the reviewed catalog workspace')
	}
	mut ordered := packages.clone()
	defer { unsafe { (&array(&ordered)).free() } }
	ordered.sort_with_compare(package_order)
	for i, item in catalog.packages {
		if !catalog_packed_matches(ordered[i], item.recipe.manifest)! {
			return error('publisher manifest differs from catalog lock: ' + item.recipe.manifest.id + '/' + item.recipe.manifest.architecture + '/' + item.recipe.manifest.version + '; rebuild the reviewed catalog workspace')
		}
	}
}
