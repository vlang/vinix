// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import tools.packages.pkgprotocol

pub struct IsoOfflinePublisher {
pub:
	id string
	public_key string
	sequence u64
	index_sha256 string
	payload_bytes u64
	reviewed_origin string @[omitempty]
}

pub struct IsoPackageReceipt {
pub:
	format int = 1
	iso_sha256 string
	configuration_sha256 string
	deployment_sha256 string
	architecture string
	applications []string
	publishers []IsoOfflinePublisher
}

fn (receipt IsoPackageReceipt) close_decoded() {
	unsafe {
		receipt.iso_sha256.free()
		receipt.configuration_sha256.free()
		receipt.deployment_sha256.free()
		receipt.architecture.free()
		for application in receipt.applications { application.free() }
		(&array(&receipt.applications)).free()
		for publisher in receipt.publishers {
			publisher.id.free()
			publisher.public_key.free()
			publisher.index_sha256.free()
			publisher.reviewed_origin.free()
		}
		receipt.publishers.free()
	}
}

// Verify a mode-preserving copy of exported media against the trusted ISO
// receipt's application and publisher pins. This does not need an ISO copy,
// package state, private scratch storage, or the repository origin.
pub fn verify_iso_offline_media(directory string, architecture string, applications []string, deployment_sha256 string, publishers []IsoOfflinePublisher) ! {
	verify_iso_offline_media_at(directory, architecture, applications, deployment_sha256, publishers, 0)!
}

// Audit a retained media copy at the release time independently established by
// the caller. This only verifies the copy and cannot activate its repositories.
pub fn verify_archived_iso_offline_media(directory string, architecture string, applications []string, deployment_sha256 string, publishers []IsoOfflinePublisher, release_time i64) ! {
	if release_time <= 0 || release_time > time.now().unix() {
		return error('offline media archive verification requires a valid past Unix release time')
	}
	verify_iso_offline_media_at(directory, architecture, applications, deployment_sha256, publishers, release_time)!
}

fn verify_iso_offline_media_at(directory string, architecture string, applications []string, deployment_sha256 string, publishers []IsoOfflinePublisher, release_time i64) ! {
	if publishers.len == 0 || publishers.len > max_image_repository_indexes {
		return error('offline media verification requires bundled publishers in the ISO package receipt')
	}
	mut entries := {pkgprotocol.deployment_mirror_filename: u64(0)}
	defer { unsafe { entries.free() } }
	for publisher in publishers {
		if !identifier(publisher.id) || publisher.id in entries || publisher.sequence == 0
			|| !digest_valid(publisher.index_sha256) {
			return error('invalid or duplicate publisher pin in the ISO package receipt')
		}
		entries[publisher.id] = 0
	}
	path := publisher_path(directory)!
	defer { unsafe { path.free() } }
	fd := capture_prepared_root(path, 'ISO offline media')!
	defer { C.close(fd) }
	root := publisher_real_path(path)!
	defer { unsafe { root.free() } }
	check_offline_media_root(root, fd, entries)!
	lock_path := os.join_path(root, pkgprotocol.deployment_mirror_filename)
	defer { unsafe { lock_path.free() } }
	export_stage_file(lock_path)!
	deployment := read_release_lock_matching_digest(lock_path, deployment_sha256)!
	defer { unsafe { deployment.free() } }
	mut document := decode_offline_application_lock(deployment, architecture, applications)!
	defer { document.close() }
	for pin in document.locked {
		if pin.repository == pkgprotocol.deployment_mirror_filename || pin.repository !in entries {
			return error('${pin.id}: offline media deployment publisher is absent from the bundle: ${pin.repository}')
		}
	}
	mut expires := max_i64
	for publisher in publishers {
		if !atomic_captured_parent_matches(root, fd) { return error('ISO offline media root changed during verification') }
		repository := os.join_path(root, publisher.id)
		pins := document.locked.filter(it.repository == publisher.id)
		defer { unsafe { repository.free(); (&array(&pins)).free() } }
		mut checked := check_signed_release(repository, publisher.id, publisher.public_key,
			SignedReleaseCheck{ media_pin: unsafe { &publisher }, deployment_pins: pins, archived_at: release_time })!
		defer { checked.close() }
		if checked.expires < expires { expires = checked.expires }
	}
	export_stage_metadata(lock_path, deployment)!
	check_offline_media_root(root, fd, entries)!
	if expires <= release_index_time(release_time) { return error('offline media repository expired during verification') }
}

fn decode_offline_application_lock(deployment string, architecture string, applications []string) !DeploymentLock {
	mut document := decode_deployment(deployment, architecture)!
	mut accepted := false
	defer { if !accepted { document.close() } }
	if document.format != 2 || document.packages.len == 0 || document.packages != applications {
		return error('offline media application declaration differs from the ISO package receipt')
	}
	// The decoder sorts both lists. Every requested application needs a pin.
	mut index := 0
	for id in document.packages {
		for index < document.locked.len && document.locked[index].id < id { index++ }
		if index == document.locked.len || document.locked[index].id != id {
			return error('offline media deployment lock is missing an application pin: ${id}')
		}
	}
	accepted = true
	return document
}

fn check_offline_media_root(root string, fd int, entries map[string]u64) ! {
	if !atomic_captured_parent_matches(root, fd) { return error('ISO offline media root changed during verification') }
	check_export_parent(root, 'ISO offline media')!
	export_stage_directory(root, entries, 0o755)!
	if !atomic_captured_parent_matches(root, fd) { return error('ISO offline media root changed during verification') }
}

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
