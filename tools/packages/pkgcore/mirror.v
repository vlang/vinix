// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

// Only in-process qualification uses this hook; it has no CLI/environment switch.
struct MirrorOptions {
	checkpoint fn (string, string) ! = mirror_no_checkpoint
	available_space fn (string) !u64 = free_bytes
}

fn mirror_no_checkpoint(_ string, _ string) ! {}

fn check_mirror_parent(parent string) ! {
	mut path := parent
	for {
		info := os.lstat(path)!
		// A sticky shared directory such as /tmp protects our exclusive child.
		// Other users must not be able to rename its ancestors or replace it with
		// a symlink while this administrator writes authenticated objects.
		if os.is_link(path) || !os.is_dir(path)
			|| (info.uid != 0 && info.uid != u32(os.geteuid()))
			|| (info.mode & 0o022 != 0 && info.mode & 0o1000 == 0) {
			return error('offline mirror parent must be controlled by this administrator; writable shared directories require the sticky bit: ${path}')
		}
		if path == '/' { return }
		path = os.dir(path)
	}
}

fn prepare_mirror_parent(path string) !string {
	mut existing := os.abs_path(path)
	for !os.exists(existing) && !os.is_link(existing) { existing = os.dir(existing) }
	if !os.is_dir(existing) { return error('offline mirror parent must be a directory') }
	check_mirror_parent(os.real_path(existing))!
	os.mkdir_all(path)!
	parent := os.real_path(path)
	check_mirror_parent(parent)!
	return parent
}

pub fn mirror(config Config, directory string, destination string, names []string) ! {
	config.validate()!
	guard := acquire(directory)!
	defer { guard.release() }
	mirror_locked(config, directory, destination, names)!
}

fn mirror_locked(config Config, directory string, destination string, names []string) ! {
	mirror_export(config, directory, destination, names, MirrorOptions{})!
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
	for snapshot in snapshots {
		exported = mirror_cost(exported, u64(snapshot.text.len + snapshot.signature.len))!
	}
	for installed in plan.packages {
		for payload in installed.package.files {
			key := installed.repository + '/' + payload.sha256
			if key !in objects {
				exported = mirror_cost(exported, payload.bytes)!
				objects[key] = true
			}
			if payload.sha256 !in cached {
				cached[payload.sha256] = true
				if !verified_file(directory + '/objects/' + payload.sha256, payload) {
					acquired = mirror_cost(acquired, payload.bytes)!
				}
			}
		}
	}
	return exported, acquired
}

fn mirror_export(config Config, directory string, destination string, names []string, options MirrorOptions) ! {
	if destination == '' || !printable(destination, 4096) || destination.contains('\\') {
		return error('offline mirror requires a valid destination path')
	}
	trimmed := destination.trim_right('/')
	name := os.file_name(trimmed)
	if name in ['', '.', '..'] { return error('offline mirror destination must be a new directory') }
	if os.exists(destination) || os.is_link(destination) {
		return error('offline mirror destination must be new')
	}
	// Create missing parent directories, then place the private tree on the
	// destination filesystem. No signed index is exposed at the final name yet.
	parent := prepare_mirror_parent(os.dir(trimmed))!
	target := parent + '/' + name
	if os.exists(target) || os.is_link(target) { return error('offline mirror destination must be new') }
	catalog := load_catalog(config, directory)!
	plan := resolve(catalog, config, State{}, names, true)!
	mut snapshots := []Snapshot{}
	for snapshot in read_snapshots(directory)! {
		if config.repositories.any(it == snapshot.repository) { snapshots << snapshot }
	}
	exported, acquired := mirror_space(plan, snapshots, directory)!
	if os.stat(parent)!.dev == os.stat(directory)!.dev {
		if exported > ~u64(0) - acquired { return error('offline mirror disk requirement overflow') }
		disk_check(options.available_space(parent)!, exported + acquired, config.policy.reserve_bytes)!
	} else {
		disk_check(options.available_space(parent)!, exported, config.policy.reserve_bytes)!
		if acquired > 0 { disk_check(options.available_space(directory)!, acquired, config.policy.reserve_bytes)! }
	}
	mut template := (parent + '/.vinix-mirror-XXXXXX').bytes()
	template << u8(0)
	defer { unsafe { template.free() } }
	if C.mkdtemp(unsafe { &char(template.data) }) == unsafe { nil } {
		return error('cannot create private offline mirror staging directory')
	}
	stage := unsafe { cstring_to_vstring(&char(template.data)).clone() }
	mut published := false
	defer {
		if !published { os.rmdir_all(stage) or {} }
	}
	options.checkpoint('created', stage)!
	for snapshot in snapshots {
		path := stage + '/' + snapshot.repository.id
		os.mkdir_all(path + '/objects')!
		atomic_write(path + '/index.json', snapshot.text)!
		atomic_write(path + '/index.sig', snapshot.signature + '\n')!
	}
	mut copied := map[string]bool{}
	for installed in plan.packages {
		for payload in installed.package.files {
			key := installed.repository + '/' + payload.sha256
			if key in copied { continue }
			cached := cached_payload(config, installed, payload, directory)!
			path := stage + '/' + installed.repository + '/objects/' + payload.sha256
			copy_file(cached, path, 0, payload.bytes)!
			options.checkpoint('copied', path)!
			if !verified_file(path, payload) {
				return error('offline mirror payload verification failed: ${installed.package.id}/${payload.path}')
			}
			// Shared offline media must be readable by ordinary consumers too.
			os.chmod(path, 0o644)!
			sync_file(path)!
			copied[key] = true
		}
	}
	flush_tree(stage)!
	options.checkpoint('ready', stage)!
	publish_new_directory(stage, target)!
	published = true
	// Publication already happened. A flush error must leave the complete tree
	// intact and explain the uncertain durability instead of claiming a retry.
	sync_directory(parent) or {
		return error('offline mirror published at ${target}, but its directory flush failed; check storage and verify the export: ${err}')
	}
	println('Offline mirror ready: ${target}; enroll its file:// repository paths with the same public keys')
}
