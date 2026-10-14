// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

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
	// created durable state, configuration and retained history require a lock.
	if state_requires_lock(directory) {
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
	atomic_write(path, text)!
}

fn save_configuration(path string, config Config) ! {
	write_administration_metadata(path, json2.encode(config) + '\n')!
}

// The administrator supplies the key through an authenticated external channel.
// Proving possession by a live signed index never learns or substitutes a key.
pub fn enroll_repository(root string, repository Repository, offline bool) !Config {
	return enroll_repository_reviewed(root, repository, offline, '')
}

pub fn enroll_repository_reviewed(root string, repository Repository, offline bool, expected string) !Config {
	directory := state_directory(root)
	guard := acquire(directory)!
	defer { guard.release() }
	current := load_config(root)!
	path := writable_configuration(root)!
	next := enrollment_configuration(current, repository)!
	mut history := history_with_snapshots(directory, read_snapshots(directory)!)!
	work := directory + '/enrollment'
	if os.exists(work) { os.rmdir_all(work)! }
	owned_directory(work, 0o700)!
	defer { os.rmdir_all(work) or {} }
	snapshot, index := enrollment_snapshot(current, repository, offline, work)!
	check_repository_review(expected, repository_fingerprint(current, history, 'enroll', repository, index_digest(snapshot.text)))!
	history = remember_index(history, repository, index, snapshot.text)!
	// History becomes durable before trust is enabled. An interrupted attempt
	// may remember a newer floor, but can never trust a replayed older index.
	save_history(directory, history)!
	save_configuration(path, next)!
	return next
}

// Revocation needs no live repository or valid catalog. Installed payload/data
// remain available for inspection and removal, and sequence history is retained.
pub fn revoke_repository(root string, id string) !Config {
	return revoke_repository_reviewed(root, id, '')
}

pub fn revoke_repository_reviewed(root string, id string, expected string) !Config {
	if !identifier(id) { return error('invalid repository ID') }
	directory := state_directory(root)
	guard := acquire(directory)!
	defer { guard.release() }
	current := load_config(root)!
	path := writable_configuration(root)!
	matches := current.repositories.filter(it.id == id)
	if matches.len != 1 { return error('repository is not enrolled: ${id}') }
	check_repository_review(expected, repository_fingerprint(current, TrustHistory{}, 'revoke', matches[0], ''))!
	next := Config{ ...current, repositories: current.repositories.filter(it.id != id) }
	next.validate()!
	save_configuration(path, next)!
	return next
}
