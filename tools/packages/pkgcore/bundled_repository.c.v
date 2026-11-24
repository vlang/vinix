// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.pkgprotocol

// Offline transfers can use an image export while the authenticated snapshot
// and installed provenance keep the configured repository ID, URL and key.
fn repository_fetch_base(directory string, repository Repository, offline bool, payload bool) !string {
	if offline {
		path := bundled_repository_directory(directory, repository, payload)!
		defer { unsafe { path.free() } }
		if path != '' { return 'file://' + path }
	}
	return repository.url.trim_right('/')
}

fn bundled_repository_directory(directory string, repository Repository, payload bool) !string {
	if !repository.url.starts_with('https://') || !directory.starts_with('/')
		|| !directory.ends_with(package_state_path) { return '' }
	root := directory[..directory.len - package_state_path.len]
	defer { unsafe { root.free() } }
	suffix := image_repositories_path + '/' + repository.id
	defer { unsafe { suffix.free() } }
	probe := root + suffix
	defer { unsafe { probe.free() } }
	mut info := C.stat{}
	if C.lstat(probe.str, unsafe { &info }) != 0 {
		if C.errno == C.ENOENT { return '' }
		return error('cannot inspect bundled repository: ' + probe)
	}
	// Resolve an explicitly selected alternate root before checking the fixed
	// image path. Keep the bundle and all of its ancestors free of aliases.
	physical := if root == '' { '/'.clone() } else { publisher_real_path(root)! }
	defer { unsafe { physical.free() } }
	path := rooted_package_path(physical, suffix)
	mut admitted := false
	defer { if !admitted { unsafe { path.free() } } }
	check_bundle_directory(path)!
	if payload {
		objects := path + '/objects'
		defer { unsafe { objects.free() } }
		check_bundle_directory(objects)!
	}
	admitted = true
	return path
}

// Online acquisition can use image bytes authenticated by the current index.
// A missing or unusable source leaves the HTTPS download path available.
fn copy_bundled_payload(directory string, repository Repository, payload Payload, part string,
	event pkgprotocol.Progress, report fn (pkgprotocol.Progress)) !bool {
	bundle := bundled_repository_directory(directory, repository, true) or {
		unsafe { err.free() }
		return false
	}
	defer { unsafe { bundle.free() } }
	if bundle == '' { return false }
	source := bundle + '/objects/' + payload.sha256
	defer { unsafe { source.free() } }
	input := copy_source(source, payload.bytes) or {
		unsafe { err.free() }
		return false
	}
	defer { C.close(input.fd) }
	if input.bytes != payload.bytes { return false }
	digest := hash_opened(input.fd, payload.bytes, source, HashReadOptions{}) or {
		unsafe { err.free() }
		return false
	}
	defer { unsafe { digest.free() } }
	if digest != payload.sha256 { return false }
	copy_opened(input, source, part, 0, event, report)!
	return true
}

fn check_bundle_directory(path string) ! {
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) != 0 || info.st_mode & 0o170022 != 0o040000 {
		return error('bundled repository requires a controlled ordinary directory: ' + path)
	}
	check_export_parent(path, 'bundled repository')!
}
