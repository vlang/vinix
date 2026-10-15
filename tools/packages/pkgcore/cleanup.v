// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import tools.packages.pkgprotocol

struct CleanupIdentity {
	domain string = 'vinix-generation-cleanup-1'
	config Config
	current State
	previous State
	targets []CollectionTarget
}

// The fingerprint binds the operation, configuration, both retained states and
// the complete removable set, including captured parent/root/lease identities.
// Lease release, new generations, root replacement and activation invalidate it.
fn prepare_cleanup(config Config, directory string, owner u32) !(pkgprotocol.CleanupReview, []CollectionTarget) {
	current := read_state(directory, config.architecture)!
	defer { if current.generation != 0 { close_decoded_state(current) } }
	previous := if current.previous == 0 { State{} }
		else { read_generation_state(directory, config.architecture, current.previous)! }
	defer { if previous.generation != 0 { close_decoded_state(previous) } }
	mut targets := if state_requires_lock(directory) { collection_targets_owned(directory, current, owner)! }
		else { []CollectionTarget{} }
	mut accepted := false
	defer { if !accepted { close_collection_targets(targets) } }
	if targets.len > 4096 { return error('cleanup review supports at most 4096 obsolete generations; inspect package storage as administrator') }
	targets.sort(a.path < b.path)
	mut generations := []u64{cap: targets.len}
	defer { if !accepted { unsafe { generations.free() } } }
	for target in targets {
		name := os.file_name(target.path)
		generation := generation_number(name) or { unsafe { name.free() }; return err }
		unsafe { name.free() }
		generations << generation
	}
	generations.sort()
	mut bytes := []u8{cap: 4096}
	unsafe { bytes.flags |= .noslices }
	defer { unsafe { bytes.free() } }
	json2.encode_append(CleanupIdentity{ config: config, current: current, previous: previous, targets: targets }, mut bytes)
	mut review := pkgprotocol.CleanupReview{ architecture: config.architecture.clone(), generation: current.generation,
		previous: current.previous, fingerprint: sha256.sum(bytes).hex(), generations: generations }
	review.validate() or { review.close(); accepted = true; close_collection_targets(targets); return err }
	accepted = true
	return review, targets
}

fn (service Service) cleanup_review_locked(directory string) !pkgprotocol.CleanupReview {
	config := load_config(service.root)!
	defer { close_decoded_configuration(config) }
	// The real image uses root-owned state. Alternate roots are fixture/admin
	// workspaces owned by their invoking account, as with other package APIs.
	owner := if service.root == '' { u32(0) } else { u32(C.geteuid()) }
	review, targets := prepare_cleanup(config, directory, owner)!
	close_collection_targets(targets)
	return review
}

pub fn (service Service) review_cleanup() !pkgprotocol.CleanupReview {
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	if state_requires_lock(directory) {
		guard := acquire_reader(directory)!
		defer { guard.release() }
		return service.cleanup_review_locked(directory)
	}
	return service.cleanup_review_locked(directory)
}

pub fn (service Service) apply_cleanup(expected string) ! {
	if !digest_valid(expected) { return error('generation cleanup requires a review fingerprint') }
	directory := service.directory()!
	defer { unsafe { directory.free() } }
	guard := acquire(directory)!
	defer { guard.release() }
	config := load_config(service.root)!
	defer { close_decoded_configuration(config) }
	mut review, targets := prepare_cleanup(config, directory, u32(C.geteuid()))!
	defer { review.close(); close_collection_targets(targets) }
	if review.fingerprint != expected { return error('generation cleanup review is stale: retained state, configuration, generations or leases changed; review cleanup again') }
	// This operation intentionally leaves cache objects and recovery stages for
	// raw administrator gc. No acquisition, policy admission or publisher needed.
	// Admit every complete directory inventory before the first removal.
	for target in targets { visit_collection_target(target, false)! }
	for target in targets { remove_collection_target(target)! }
	if targets.len > 0 {
		path := directory + '/generations'
		defer { unsafe { path.free() } }
		sync_directory(path)!
	}
}
