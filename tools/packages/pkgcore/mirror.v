// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import crypto.sha256
import json2
import tools.packages.pkgprotocol

// Checkpoint and space overrides are in-process qualification hooks, without a
// CLI/environment switch. Production callers supply progress and review intent.
struct MirrorOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	available_space fn (string) !u64 = free_bytes
	progress fn (pkgprotocol.Progress) = no_progress
	expected_review string
	deployment string // exact format-2 deployment export; empty for catalog mirrors
}

fn mirror_no_checkpoint(_ string, _ string) ! {}

pub fn mirror(config Config, directory string, destination string, names []string) ! {
	config.validate()!
	guard := acquire(directory)!
	defer { guard.release() }
	mirror_locked(config, directory, destination, names)!
}

fn mirror_locked(config Config, directory string, destination string, names []string) ! {
	mirror_export(config, directory, destination, names, MirrorOptions{})!
}

struct MirrorIdentity {
	domain string = 'vinix-mirror-review-1'
	config Config
	names []string
	plan Plan
	snapshots []Snapshot
	destination string
	target string
	ancestor string
	device u64
	inode u64
	deployment string
	deployment_sha256 string
}

struct PreparedMirror {
	target string
	ancestor string
	plan Plan
	snapshots []Snapshot
	exported u64
	acquired u64
	shared_disk bool
	fingerprint string
	deployment_text string
	deployment_sha256 string
	catalog Catalog // owns authenticated manifests; publisher strings borrow Config
	source_snapshots []Snapshot // owns fields borrowed by the selected snapshot array
}

fn (mut prepared PreparedMirror) close() {
	close_authenticated_catalog(prepared.catalog)
	close_decoded_snapshots(prepared.source_snapshots)
	unsafe {
		prepared.plan.requested.free(); (&array(&prepared.plan.packages)).free()
		(&array(&prepared.snapshots)).free()
		prepared.target.free(); prepared.ancestor.free(); prepared.fingerprint.free()
		prepared.deployment_text.free(); prepared.deployment_sha256.free()
	}
	prepared = PreparedMirror{}
}

fn mirror_path_exists(path string) !bool {
	mut info := C.stat{}
	if C.lstat(path.str, unsafe { &info }) == 0 { return true }
	if C.errno in [C.ENOENT, C.ENOTDIR]! { return false }
	return error('cannot inspect offline mirror path: ' + path)
}

// Resolve missing parents without creating them. The review binds the existing
// ancestor's inode and filesystem so swapping removable media invalidates it.
fn mirror_location(destination string) !(string, string) {
	if destination == '' || !printable(destination, 4096) || destination.contains('\\') {
		return error('offline mirror requires a valid destination path')
	}
	absolute := mirror_absolute_path(destination)!
	path := absolute.trim_right('/')
	defer { unsafe { absolute.free(); path.free() } }
	if path == '' || mirror_path_exists(path)! {
		return error('offline mirror destination must be new')
	}
	mut ancestor := os.dir(path)
	defer { unsafe { ancestor.free() } }
	for !mirror_path_exists(ancestor)! {
		next := os.dir(ancestor); unsafe { ancestor.free() }; ancestor = next
	}
	mut info := C.stat{}
	if C.fstatat(C.AT_FDCWD, ancestor.str, unsafe { &info }, 0) != 0 || info.st_mode & 0o170000 != 0o040000 { return error('offline mirror parent must be a directory') }
	real := mirror_real_path(ancestor)!
	mut accepted := false
	defer { if !accepted { unsafe { real.free() } } }
	check_export_parent(real, 'offline mirror')!
	suffix := path[ancestor.len..]
	trimmed := real.trim_right('/')
	ending := if ancestor == '/' { '/' + suffix } else { suffix.clone() }
	defer { unsafe { suffix.free(); trimmed.free(); ending.free() } }
	target := trimmed + ending
	defer { if !accepted { unsafe { target.free() } } }
	if mirror_path_exists(target)! { return error('offline mirror destination must be new') }
	accepted = true
	return target, real
}

fn prepare_mirror(config Config, directory string, destination string, names []string) !PreparedMirror {
	if names.len == 0 || names.len > 4096 { return error('offline mirror requires 1 to 4096 package IDs') }
	catalog := load_catalog(config, directory)!
	mut accepted := false
	defer { if !accepted { close_authenticated_catalog(catalog) } }
	plan := resolve(catalog, config, State{}, names, true)!
	defer { unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() } }
	prepared := prepare_mirror_plan(config, directory, destination, names, plan, '', '')!
	accepted = true
	return PreparedMirror{ ...prepared, catalog: catalog }
}

fn prepare_mirror_plan(config Config, directory string, destination string, names []string, plan Plan, deployment string, text_lock string) !PreparedMirror {
	target, ancestor := mirror_location(destination)!
	mut accepted := false
	defer { if !accepted { unsafe { target.free(); ancestor.free() } } }
	source_snapshots := read_snapshots(directory)!
	defer { if !accepted { close_decoded_snapshots(source_snapshots) } }
	mut snapshots := []Snapshot{cap: source_snapshots.len}
	defer { if !accepted { unsafe { (&array(&snapshots)).free() } } }
	for snapshot in source_snapshots {
		if config.repositories.any(it == snapshot.repository) { unsafe { snapshots.push_many(&snapshot, 1) } }
	}
	base_exported, acquired := mirror_space(plan, snapshots, directory)!
	exported := if text_lock == '' { base_exported } else { mirror_cost(base_exported, u64(text_lock.len))! }
	lock_sha256 := if text_lock == '' { '' } else { index_digest(text_lock) }
	defer { if !accepted { unsafe { lock_sha256.free() } } }
	mut info := C.stat{}; mut stored := C.stat{}
	if C.fstatat(C.AT_FDCWD, ancestor.str, unsafe { &info }, 0) != 0 || C.fstatat(C.AT_FDCWD, directory.str, unsafe { &stored }, 0) != 0 { return error('cannot inspect offline mirror filesystems') }
	mut bytes := []u8{cap: 2048}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(MirrorIdentity{ config: config, names: names, plan: plan, snapshots: snapshots,
		domain: if deployment == '' { 'vinix-mirror-review-1' } else { 'vinix-deployment-mirror-review-1' },
		destination: destination, target: target, ancestor: ancestor, device: u64(info.st_dev), inode: u64(info.st_ino),
		deployment: deployment, deployment_sha256: lock_sha256 }, mut bytes)
	mut hash := sha256.new(); mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); digest.free() } }
	hash.write(bytes)!
	hash.checksum_into(mut digest)
	fingerprint := digest.hex()
	accepted = true
	return PreparedMirror{ target: target, ancestor: ancestor,
		// Deployment roots outlive their decoded document; package fields borrow
		// the independently retained catalog (or a live caller's fixture plan).
		plan: Plan{ requested: review_strings(plan.requested), packages: plan.packages.clone() }, snapshots: snapshots, source_snapshots: source_snapshots,
		exported: exported, acquired: acquired, shared_disk: info.st_dev == stored.st_dev,
		fingerprint: fingerprint, deployment_text: text_lock.clone(), deployment_sha256: lock_sha256 }
}

fn mirror_destination_cost(prepared PreparedMirror) !u64 {
	if !prepared.shared_disk { return prepared.exported }
	if prepared.exported > ~u64(0) - prepared.acquired { return error('offline mirror disk requirement overflow') }
	return prepared.exported + prepared.acquired
}

pub fn (service Service) review_mirror(destination string, names []string) !pkgprotocol.MirrorReview {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire_reader(directory)!
	defer { guard.release() }
	config := service.configuration()!
	defer { close_decoded_configuration(config) }
	mut prepared := prepare_mirror(config, directory, destination, names)!
	defer { prepared.close() }
	return mirror_review(config, directory, destination, names, prepared)
}

fn mirror_review(config Config, directory string, destination string, names []string, prepared PreparedMirror) !pkgprotocol.MirrorReview {
	// Finish fallible observations before allocating the independent presentation.
	cache_available := free_bytes(directory)!
	disk_needed := mirror_destination_cost(prepared)!
	disk_available := free_bytes(prepared.ancestor)!
	mut rows := []pkgprotocol.ReviewPackage{cap: prepared.plan.packages.len}
	for installed in prepared.plan.packages {
		rows << review_row(installed, '', installed.package.id in prepared.plan.requested, 'export')
	}
	rows.sort(a.id < b.id)
	mut result := pkgprotocol.MirrorReview{
		format: 1, destination: prepared.target.clone(), input_destination: destination.clone(),
		cache_needed: prepared.acquired, cache_available: cache_available, shared_disk: prepared.shared_disk,
		review: pkgprotocol.Review{ format: 2, operation: 'mirror'.clone(), names: review_strings(names),
			architecture: config.architecture.clone(), fingerprint: prepared.fingerprint.clone(),
			requested: review_strings(prepared.plan.requested), rows: rows,
			disk_needed: disk_needed, disk_available: disk_available,
			disk_reserve: config.policy.reserve_bytes }
	}
	result.validate() or { result.close(); return err }
	return result
}

pub fn (service Service) apply_mirror(destination string, names []string, expected string) ! {
	if !digest_valid(expected) { return error('offline mirror apply requires a review fingerprint') }
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := service.configuration()!; defer { close_decoded_configuration(config) }
	mirror_export(config, directory, destination, names,
		MirrorOptions{ progress: service.progress, expected_review: expected })!
}

fn mirror_cost(total u64, bytes u64) !u64 {
	if bytes > ~u64(0) - 8192 || total > ~u64(0) - bytes - 8192 {
		return error('offline mirror disk requirement overflow')
	}
	return total + bytes + 8192
}

// Objects are deduplicated within each mirrored repository, and globally in the
// source cache. Budget both copies when the disks are the same.
fn mirror_space(plan Plan, snapshots []Snapshot, directory string) !(u64, u64) {
	mut exported := u64(4 * 1024 * 1024)
	mut acquired := u64(0)
	mut objects := map[string]bool{}
	mut cached := map[string]bool{}
	defer { unsafe { objects.free(); cached.free() } }
	for snapshot in snapshots {
		exported = mirror_cost(exported, u64(snapshot.text.len + snapshot.signature.len))!
	}
	for installed in plan.packages {
		for payload in installed.package.files {
			key := installed.repository + '/' + payload.sha256
			defer { unsafe { key.free() } }
			if key !in objects {
				exported = mirror_cost(exported, payload.bytes)!
				objects[key] = true
			}
			if payload.sha256 !in cached {
				cached[payload.sha256] = true
				path := directory + '/objects/' + payload.sha256
				defer { unsafe { path.free() } }
				if !verified_file(path, payload) {
					acquired = mirror_cost(acquired, payload.bytes)!
				}
			}
		}
	}
	return exported, acquired
}

fn mirror_export(config Config, directory string, destination string, names []string, options MirrorOptions) ! {
	mut prepared := if options.deployment == '' { prepare_mirror(config, directory, destination, names)! }
		else { prepare_deployment_mirror(config, directory, destination, options.deployment)! }
	defer { prepared.close() }
	if options.expected_review != '' && options.expected_review != prepared.fingerprint {
		return error('offline mirror review is stale: destination, publisher metadata, policy or resolved packages changed; review the export again')
	}
	disk_check(options.available_space(prepared.ancestor)!, mirror_destination_cost(prepared)!, config.policy.reserve_bytes)!
	if !prepared.shared_disk && prepared.acquired > 0 {
		disk_check(options.available_space(directory)!, prepared.acquired, config.policy.reserve_bytes)!
	}
	options.progress(pkgprotocol.Progress{ phase: 'resolve' })
	target := export_target(destination, 'offline mirror')!
	defer { unsafe { target.free() } }
	if target != prepared.target { return error('offline mirror destination changed; review the export again') }
	parent := os.dir(target)
	defer { unsafe { parent.free() } }
	mut exporting := create_export_stage(parent, '.vinix-mirror', 'offline mirror')!
	defer { exporting.close() }
	write_mirror_stage(config, directory, prepared, options, target, mut exporting) or {
		return exporting.failure(err)
	}
}

fn write_mirror_stage(config Config, directory string, prepared PreparedMirror, options MirrorOptions, target string, mut exporting ExportStage) ! {
	stage := exporting.path
	options.checkpoint('created', stage)!
	exporting.check()!
	if prepared.deployment_text != '' {
		atomic_write(stage + '/' + pkgprotocol.deployment_mirror_filename, prepared.deployment_text)!
	}
	for snapshot in prepared.snapshots {
		path := stage + '/' + snapshot.repository.id
		os.mkdir_all(path + '/objects')!
		atomic_write(path + '/index.json', snapshot.text)!
		atomic_write(path + '/index.sig', snapshot.signature + '\n')!
	}
	mut copied := map[string]bool{}
	for installed in prepared.plan.packages {
		for payload in installed.package.files {
			key := installed.repository + '/' + payload.sha256
			if key in copied { continue }
			cached := cached_payload_progress(config, installed, payload, directory, options.progress)!
			path := stage + '/' + installed.repository + '/objects/' + payload.sha256
			copy_file_progress(cached, path, 0, payload.bytes,
				pkgprotocol.Progress{ phase: 'copy', package: installed.package.id, repository: installed.repository,
					path: payload.path, total: payload.bytes }, options.progress)!
			options.checkpoint('copied', path)!
			exporting.check()!
			options.progress(pkgprotocol.Progress{ phase: 'verify', package: installed.package.id,
				repository: installed.repository, path: payload.path })
			exporting.check()!
			if !verified_file(path, payload) {
				return error('offline mirror payload verification failed: ${installed.package.id}/${payload.path}')
			}
			// Shared offline media must be readable by ordinary consumers too.
			os.chmod(path, 0o644)!
			sync_file(path)!
			copied[key] = true
		}
	}
	verify_mirror_stage(stage, prepared, false) or {
		message := err.msg()
		defer { unsafe { message.free(); err.free() } }
		return error('offline mirror verification failed before publication: ' + message)
	}
	flush_tree(stage)!
	options.checkpoint('ready', stage)!
	exporting.check()!
	verify_mirror_stage(stage, prepared, true) or {
		message := err.msg()
		defer { unsafe { message.free(); err.free() } }
		return error('offline mirror verification failed before publication: ' + message)
	}
	exporting.publish(target)!
	options.progress(pkgprotocol.Progress{ phase: 'complete', current: 1, total: 1 })
	println('Offline mirror ready: ${target}; enroll its file:// repository paths with the same public keys')
}
