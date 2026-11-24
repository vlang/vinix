// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import encoding.utf8
import tools.packages.pkgprotocol

pub struct DeploymentMediaSaved {
pub:
	format int = 1
	destination string
	architecture string
	sha256 string
	roots int
	packages int
}

pub fn (mut saved DeploymentMediaSaved) close() {
	unsafe { saved.destination.free(); saved.architecture.free(); saved.sha256.free() }
	saved = DeploymentMediaSaved{}
}

// Save the exact media lock after resolving its additions against the local
// authenticated catalog. A later deployment still needs its own review.
pub fn (service Service) save_media_deployment(source string, destination string, expected_sha256 string) !DeploymentMediaSaved {
	if !source.starts_with('/') || !printable(source, 4096) {
		return error('deployment media save requires an absolute media directory')
	}
	if !printable(destination, 4096) || !utf8.validate_str(destination) {
		return error('deployment media save requires a printable UTF-8 new-file path of at most 4096 bytes')
	}
	if expected_sha256 != '' && !digest_valid(expected_sha256) {
		return error('deployment media save requires a lowercase SHA-256 digest')
	}
	parent, name := atomic_file_path(destination)!
	defer { unsafe { parent.free(); name.free() } }
	fd := open_atomic_parent(parent)!
	defer { C.close(fd) }
	check_new_atomic_destination(fd, name)!
	media := open_repository_media(source)!
	defer { C.close(media.fd); unsafe { media.path.free() } }
	publisher_outside_directory(media.fd, fd) or {
		unsafe { err.free() }
		return error('saved deployment must be outside the media directory')
	}
	path := media.path + '/' + pkgprotocol.deployment_mirror_filename
	defer { unsafe { path.free() } }
	export_stage_file(path)!
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	digest := index_digest(text)
	defer { unsafe { digest.free() } }
	if expected_sha256 != '' && digest != expected_sha256 {
		return error('media deployment SHA-256 differs from the expected digest')
	}
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	mut document := decode_deployment(text, config.architecture)!
	defer { document.close() }
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	mut prepared := prepare_deployment_plan(config, directory, current, document, .additions)!
	defer { prepared.close() }
	media.check()!
	export_stage_metadata(path, text)!
	media.check()!
	atomic_write_at(parent, name, text, AtomicWriteOptions{ exclusive: true, parent_fd: fd })!
	return DeploymentMediaSaved{ destination: destination.clone(), architecture: document.architecture.clone(),
		sha256: digest.clone(), roots: document.packages.len, packages: document.locked.len }
}
