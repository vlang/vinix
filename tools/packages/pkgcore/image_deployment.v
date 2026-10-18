// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import encoding.utf8
import os

struct ImageDeploymentOutput {
	destination string
	options AtomicWriteOptions
}

// Export is explicitly outside the image. Compare directory identities before
// resolving aliases, preserving the filesystem meaning of alias/.. paths.
fn image_deployment_target(root string, destination string) !string {
	if destination == '' || !printable(destination, 4096) || !utf8.validate_str(destination) || destination.ends_with('/') {
		return error('image deployment export requires a printable UTF-8 new-file path of at most 4096 bytes')
	}
	name := os.file_name(destination)
	parent := os.dir(destination)
	defer { unsafe { name.free(); parent.free() } }
	if name in ['', '.', '..']! { return error('image deployment export requires a new file name') }
	mut info := C.stat{}
	if C.fstatat(C.AT_FDCWD, parent.str, unsafe { &info }, 0) != 0 || info.st_mode & 0o170000 != 0o040000 {
		return error('image deployment export parent directory must already exist')
	}
	fd := capture_prepared_root(root, 'package image root')!
	defer { C.close(fd) }
	publisher_outside_source(fd, parent) or {
		unsafe { err.free() }
		return error('image deployment export must be outside the target image in an accessible directory')
	}
	physical := publisher_real_path(parent)!
	defer { unsafe { physical.free() } }
	check_export_parent(physical, 'image deployment export')!
	base := physical.trim_right('/')
	defer { unsafe { base.free() } }
	return base + '/' + name
}

// The returned report names the saved canonical format-2 lock and its exact
// newline-inclusive digest. Saving grants no authority to deploy it later.
pub fn (configuration &ImageConfiguration) export_applications(repositories &ImageRepositories, required []string, destination string) !string {
	if required.len == 0 { return error('image deployment export requires at least one application ID') }
	if destination == '' { return error('image deployment export requires a new file name') }
	return configuration.check_inputs(repositories, required, '', ImageDeploymentOutput{ destination: destination })
}

pub fn (configuration &ImageConfiguration) export_application_file(repositories &ImageRepositories, source string, destination string) !string {
	if destination == '' { return error('image deployment export requires a new file name') }
	return configuration.check_application_source(repositories, source, ImageDeploymentOutput{ destination: destination })
}
