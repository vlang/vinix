// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

// Profiles publish only the reviewed lock; payload inventories stay private.
// Capture both children so cleanup cannot delete a substituted inventory/lock.
struct ProfileDirectory {
	fd int = -1
	name string
	device u64
	inode u64
}

struct ProfileStage {
mut:
	stage ExportStage
	inventory ProfileDirectory
	lock ProfileDirectory
	published bool
}

fn create_profile_directory(stage ExportStage, name string) !ProfileDirectory {
	if C.mkdirat(stage.root, name.str, 0o700) != 0 { return error('cannot create private profile ' + name) }
	fd := C.openat(stage.root, name.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 { return error('cannot capture profile ' + name + '; retain staging data for inspection') }
	mut accepted := false
	defer { if !accepted { C.close(fd) } }
	info := recovery_directory(fd, stage.device)!
	if info.st_mode & 0o7777 != 0o700 { return error('profile ' + name + ' permissions changed') }
	child := ProfileDirectory{ fd: fd, name: name, device: u64(info.st_dev), inode: u64(info.st_ino) }
	child.check(stage)!
	accepted = true
	return child
}

fn (child ProfileDirectory) check(stage ExportStage) ! {
	if child.fd < 0 { return error('profile directory was not captured; retain staging data for inspection') }
	info := recovery_directory(child.fd, stage.device)!
	if info.st_mode & 0o022 != 0 { return error('profile ' + child.name + ' permissions changed') }
	check_stage_name(stage.root, child.name, child.device, child.inode)!
}

fn create_profile_stage(parent string, prefix string, kind string) !ProfileStage {
	mut stage := create_export_stage(parent, prefix, kind)!
	mut accepted := false
	defer { if !accepted { stage.close() } }
	// If creation/capture fails, retain the private root: an unadmitted child
	// must never be treated as an owned tree by failure cleanup.
	inventory := create_profile_directory(stage, 'inventory')!
	mut transferred := false
	defer { if !transferred { C.close(inventory.fd) } }
	output := create_profile_directory(stage, 'lock')!
	accepted = true; transferred = true
	return ProfileStage{ stage: stage, inventory: inventory, lock: output }
}

fn (profile ProfileStage) check() ! {
	profile.stage.check()!
	profile.inventory.check(profile.stage)!
	if !profile.published { profile.lock.check(profile.stage)! }
}

fn (profile ProfileStage) checkpoint(phase string, options CatalogOptions) ! {
	options.checkpoint(phase, profile.stage.path)!
	profile.check()!
}

fn (profile ProfileStage) retire() ! {
	// Use held descriptors even if the visible parent moved. Child identity
	// refusals preserve the entire private tree and its recovery snapshots.
	profile.inventory.check(profile.stage)!
	if !profile.published { profile.lock.check(profile.stage)! }
	profile.stage.retire()!
}

fn (profile ProfileStage) failure(cause IError) IError {
	profile.retire() or {
		primary := cause.msg(); secondary := err.msg()
		message := primary + '; unpublished ' + profile.stage.kind + ' cleanup refused at ' + profile.stage.path + ': ' + secondary + '; retain recovery data for inspection'
		unsafe { primary.free(); secondary.free(); cause.free(); err.free() }
		return error(message)
	}
	return cause
}

fn (mut profile ProfileStage) publish(canonical string, target string, options CatalogOptions) ! {
	path := profile.stage.path + '/lock/catalog.json'
	defer { unsafe { path.free() } }
	profile.check()!
	atomic_write(path, canonical)!
	profile.checkpoint('ready', options)!
	text := read_metadata(path)!
	defer { unsafe { text.free() } }
	if text != canonical { return error(profile.stage.kind + ' catalog lock changed before publication') }
	if C.fsync(profile.lock.fd) != 0 { return error('cannot flush private profile catalog directory') }
	profile.check()!
	name := target.all_after_last('/')
	parent := os.dir(target)
	defer { unsafe { name.free(); parent.free() } }
	if parent != profile.stage.parent_path || name in ['', '.', '..']! { return error('profile destination must remain in its captured parent') }
	if atomic_publish_between(profile.stage.root, 'lock', profile.stage.parent, name) != 0 {
		return error('cannot publish ' + profile.stage.kind + ' without replacing ' + target + '; destination must be new and storage must support exclusive atomic rename')
	}
	profile.published = true
	if options.flush(profile.stage.parent) != 0 {
		return error(profile.stage.kind + ' published at ' + target + ', but its directory flush failed; verify the saved catalog before retrying')
	}
	if !atomic_parent_matches(profile.stage.parent_path, profile.stage.parent_device, profile.stage.parent_inode) {
		return error(profile.stage.kind + ' published in its captured directory, but the parent path changed; inspect the saved catalog before retrying')
	}
}

fn (mut profile ProfileStage) finish(target string) ! {
	profile.retire() or { return error(profile.stage.kind + ' published at ' + target + ', but private inventory cleanup refused: ' + err.msg() + '; retain recovery data for inspection') }
	if C.fsync(profile.stage.parent) != 0 { return error(profile.stage.kind + ' published at ' + target + ', but its cleanup directory flush failed; verify storage') }
}

fn (mut profile ProfileStage) close() {
	if profile.inventory.fd >= 0 { C.close(profile.inventory.fd) }
	if profile.lock.fd >= 0 { C.close(profile.lock.fd) }
	profile.stage.close()
	profile.inventory = ProfileDirectory{}
	profile.lock = ProfileDirectory{}
}
