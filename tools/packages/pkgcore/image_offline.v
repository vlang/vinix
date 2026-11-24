// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.pkgprotocol

// An ISO verifier can populate only its private, captured destination stage.
pub struct IsoOfflineMedia {
	stage ExportStage
}

// Capture the destination before ISO verification and publish the complete
// media only when that verification and staging have both succeeded.
pub fn write_iso_offline_media(destination string, prepare fn (&IsoOfflineMedia) !) ! {
	target := export_target(destination, 'ISO offline media')!
	parent := os.dir(target)
	defer { unsafe { target.free(); parent.free() } }
	mut media := IsoOfflineMedia{
		stage: create_export_stage(parent, '.vinix-iso-offline', 'ISO offline media')!
	}
	defer { media.stage.close() }
	media.prepare_and_publish(target, prepare) or { return media.stage.failure(err) }
}

fn (mut media IsoOfflineMedia) prepare_and_publish(target string, prepare fn (&IsoOfflineMedia) !) ! {
	prepare(unsafe { &media })!
	media.stage.check()!
	mut deployment := C.stat{}
	if C.fstatat(media.stage.root, pkgprotocol.deployment_mirror_filename.str,
		unsafe { &deployment }, C.AT_SYMLINK_NOFOLLOW) != 0 || deployment.st_mode & 0o177777 != 0o100644
		|| deployment.st_nlink != 1 || deployment.st_size == 0 {
		return error('ISO offline media stage is missing its deployment lock')
	}
	if C.fchmod(media.stage.root, 0o755) != 0 || atomic_flush(media.stage.root) != 0 {
		return error('cannot set permissions or flush ISO offline media directory')
	}
	media.stage.publish(target)!
}

// Copy complete, currently authenticated repositories with their signed indexes
// intact. The ISO verifier admitted the exact deployment lock bytes separately.
pub fn (media &IsoOfflineMedia) write(repositories &ImageRepositories, deployment string) ! {
	if repositories.capture == '' || repositories.archived_at != 0 {
		return error('ISO offline media requires current signed repositories')
	}
	media.stage.check()!
	repositories.capture_stage.check()!
	disk_check(free_bytes(media.stage.path)!, mirror_cost(repositories.needed,
		u64(deployment.len))!, 64 * 1024 * 1024)!
	for item in repositories.repositories {
		source := repositories.capture + '/' + item.id
		destination := media.stage.path + '/' + item.id
		defer { unsafe { source.free(); destination.free() } }
		image_repository_copy(source, destination, item)!
	}
	media.stage.check()!
	repositories.verify(media.stage.path, 0o700)!
	atomic_write_at(media.stage.path, pkgprotocol.deployment_mirror_filename, deployment,
		AtomicWriteOptions{ exclusive: true, parent_fd: media.stage.root })!
}
