// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn C.mkstemp(&u8) i32

pub struct RepositoryStatus {
pub:
	format       int = 1
	architecture string
	repositories []Repository
	history      []RepositoryFloor
}

fn configured_repository_status(config Config, directory string) !RepositoryStatus {
	history := history_with_snapshots(directory, read_snapshots(directory)!)!
	return RepositoryStatus{
		architecture: config.architecture
		repositories: config.repositories
		history:      history.repositories
	}
}

pub fn repository_status(root string) !RepositoryStatus {
	directory := state_directory(root)
	// Listing a fresh image does not initialize its store. Once a writer has
	// created the lock, configuration and retained history are read together.
	if os.exists(directory + '/lock') {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return configured_repository_status(load_config(root)!, directory)
	}
	return configured_repository_status(load_config(root)!, directory)
}

fn writable_configuration(root string) !string {
	parent := root.trim_right('/') + '/etc/vinix-packages'
	path := parent + '/config.json'
	for entry in [parent, path] {
		info := os.lstat(entry)!
		if os.is_link(entry) || info.uid != u32(os.geteuid()) || info.mode & 0o022 != 0
			|| if entry == parent { !os.is_dir(entry) } else { !os.is_file(entry) } {
			return error('repository changes require administrator-owned ordinary configuration files and directories')
		}
	}
	return path
}

fn write_administration_metadata(path string, text string) ! {
	if text.len > max_metadata {
		return error('package administration metadata exceeds its size limit')
	}
	mut template := (os.dir(path) + '/.administration-XXXXXX').bytes()
	template << u8(0)
	fd := C.mkstemp(template.data)
	if fd < 0 { return error('cannot create a private package administration temporary file') }
	temporary := unsafe { cstring_to_vstring(&char(template.data)).clone() }
	mut moved := false
	defer {
		C.close(fd)
		if !moved { os.rm(temporary) or {} }
	}
	mut offset := 0
	for offset < text.len {
		written := C.write(fd, unsafe { text.str + offset }, usize(text.len - offset))
		if written < 0 && C.errno == C.EINTR { continue }
		if written <= 0 {
			return error('cannot write package administration metadata; check disk space')
		}
		offset += int(written)
	}
	if C.fchmod(fd, 0o644) != 0 || C.fsync(fd) != 0 {
		return error('cannot flush package administration metadata')
	}
	replace_path(temporary, path)!
	moved = true
	sync_directory(os.dir(path)) or {
		return error('package administration metadata saved, but directory flush failed; inspect repo-list and check storage')
	}
}

fn save_configuration(path string, config Config) ! {
	write_administration_metadata(path, json2.encode(config) + '\n')!
}

// The administrator supplies the key through an authenticated external channel.
// Proving possession by a live signed index never learns or substitutes a key.
pub fn enroll_repository(root string, repository Repository, offline bool) !Config {
	directory := state_directory(root)
	guard := acquire(directory)!
	defer { guard.release() }
	current := load_config(root)!
	path := writable_configuration(root)!
	mut repositories := current.repositories.filter(it.id != repository.id)
	repositories << repository
	repositories.sort(a.id < b.id)
	next := Config{ ...current, repositories: repositories }
	next.validate()!
	mut history := history_with_snapshots(directory, read_snapshots(directory)!)!
	work := directory + '/enrollment'
	if os.exists(work) { os.rmdir_all(work)! }
	owned_directory(work, 0o700)!
	defer { os.rmdir_all(work) or {} }
	fetch(repository.url.trim_right('/') + '/index.json', work + '/index.json', max_metadata, false,
		current.policy.offline || offline)!
	fetch(repository.url.trim_right('/') + '/index.sig', work + '/index.sig', 256, false,
		current.policy.offline || offline)!
	text := read_metadata(work + '/index.json')!
	signature := read_metadata(work + '/index.sig')!
	index := verify_index(repository, text, signature, time.now().unix())!
	history = remember_index(history, repository, index, text)!
	// History becomes durable before trust is enabled. An interrupted attempt
	// may remember a newer floor, but can never trust a replayed older index.
	save_history(directory, history)!
	save_configuration(path, next)!
	return next
}

// Revocation needs no live repository or valid catalog. Installed payload/data
// remain available for inspection and removal, and sequence history is retained.
pub fn revoke_repository(root string, id string) !Config {
	if !identifier(id) { return error('invalid repository ID') }
	directory := state_directory(root)
	guard := acquire(directory)!
	defer { guard.release() }
	current := load_config(root)!
	path := writable_configuration(root)!
	if !current.repositories.any(it.id == id) { return error('repository is not enrolled: ${id}') }
	next := Config{ ...current, repositories: current.repositories.filter(it.id != id) }
	next.validate()!
	save_configuration(path, next)!
	return next
}
