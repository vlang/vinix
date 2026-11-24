// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Offline transfers can use an image export while the authenticated snapshot
// and installed provenance keep the configured repository ID, URL and key.
fn repository_fetch_base(directory string, repository Repository, offline bool, payload bool) !string {
	if !offline || !repository.url.starts_with('https://') || !directory.starts_with('/')
		|| !directory.ends_with(package_state_path) {
		return repository.url.trim_right('/')
	}
	root := directory[..directory.len - package_state_path.len]
	defer { unsafe { root.free() } }
	suffix := image_repositories_path + '/' + repository.id
	defer { unsafe { suffix.free() } }
	probe := root + suffix
	defer { unsafe { probe.free() } }
	mut info := C.stat{}
	if C.lstat(probe.str, unsafe { &info }) != 0 {
		if C.errno == C.ENOENT { return repository.url.trim_right('/') }
		return error('cannot inspect bundled repository: ' + probe)
	}
	// Resolve an explicitly selected alternate root before checking the fixed
	// image path. Keep the bundle and all of its ancestors free of aliases.
	physical := if root == '' { '/'.clone() } else { publisher_real_path(root)! }
	defer { unsafe { physical.free() } }
	path := rooted_package_path(physical, suffix)
	defer { unsafe { path.free() } }
	check_bundle_directory(path)!
	if payload {
		objects := path + '/objects'
		defer { unsafe { objects.free() } }
		check_bundle_directory(objects)!
	}
	return 'file://' + path
}

fn check_bundle_directory(path string) ! {
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) != 0 || info.st_mode & 0o170022 != 0o040000 {
		return error('bundled repository requires a controlled ordinary directory: ' + path)
	}
	check_export_parent(path, 'bundled repository')!
}
