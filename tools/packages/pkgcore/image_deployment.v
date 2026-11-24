// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import encoding.utf8
import os

struct ImageDeploymentOutput {
	destination string
	options AtomicWriteOptions
}

struct ImageDeploymentTarget {
	path string
	directory int = -1
}

// Use one output directory for containment and publication. Opening the
// literal parent preserves the filesystem meaning of alias/.. paths.
fn (configuration &ImageConfiguration) capture_deployment_target(destination string) !ImageDeploymentTarget {
	if destination == '' || !printable(destination, 4096) || !utf8.validate_str(destination) || destination.ends_with('/') {
		return error('image deployment export requires a printable UTF-8 new-file path of at most 4096 bytes')
	}
	name := os.file_name(destination)
	parent := os.dir(destination)
	defer { unsafe { name.free(); parent.free() } }
	if name in ['', '.', '..']! { return error('image deployment export requires a new file name') }
	directory := C.open(parent.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NONBLOCK)
	if directory < 0 {
		return error('image deployment export parent directory must already exist')
	}
	mut accepted := false
	defer { if !accepted { C.close(directory) } }
	image := capture_prepared_root(configuration.root, 'package image root')!
	defer { C.close(image) }
	mut info := C.stat{}
	if C.fstat(image, unsafe { &info }) != 0 || u64(info.st_dev) != configuration.device
		|| u64(info.st_ino) != configuration.inode {
		return error('package image root changed before deployment export')
	}
	publisher_outside_directory(image, directory) or {
		unsafe { err.free() }
		return error('image deployment export must be outside the target image in an accessible directory')
	}
	physical := publisher_real_path(parent)!
	defer { unsafe { physical.free() } }
	check_export_parent(physical, 'image deployment export')!
	if C.fstat(directory, unsafe { &info }) != 0 || !atomic_parent_matches(physical, u64(info.st_dev), u64(info.st_ino)) {
		return error('image deployment export parent directory changed during admission')
	}
	base := physical.trim_right('/')
	defer { unsafe { base.free() } }
	accepted = true
	return ImageDeploymentTarget{ path: base + '/' + name, directory: directory }
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
