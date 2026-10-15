// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

#include <sys/wait.h>
fn C.fork() int
fn C.waitpid(int, &int, int) int
fn C._exit(int)
fn C.setgroups(usize, voidptr) int
fn C.setgid(u32) int
fn C.setuid(u32) int
fn C.chown(&char, i32, i32) int

fn cleanup_fixture(architecture string) !string {
	work := os.temp_dir() + '/vinix-reviewed-cleanup-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(work + '/etc/vinix-packages')!
	os.write_file(work + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: architecture, policy: Policy{ offline: true } }))!
	directory := state_directory(work)
	guard := acquire(directory)!
	defer { guard.release() }
	for generation in 1 .. 6 {
		path := directory + '/generations/' + generation.str()
		os.mkdir(path)!
		os.write_file(path + '/lease', '')!; os.chmod(path + '/lease', 0o444)!
		os.write_file(path + '/state.json', json2.encode(State{ architecture: architecture, generation: u64(generation),
			previous: if generation == 5 { u64(4) } else { u64(0) } }))!
		os.write_file(path + '/payload', 'old version')!
	}
	os.symlink('generations/5', directory + '/current')!
	os.write_file(directory + '/objects/' + 'a'.repeat(64), 'offline cache')!
	os.write_file(directory + '/objects/' + 'b'.repeat(64) + '.part', 'resume data')!
	os.mkdir(directory + '/generations/.stage-interrupted')!
	os.write_file(directory + '/generations/.stage-interrupted/keep', 'recovery data')!
	os.mkdir_all(work + '/home/user/.local/share/vinix-apps/app')!
	os.write_file(work + '/home/user/.local/share/vinix-apps/app/data', 'personal data')!
	return work
}

fn cleanup_preserved(work string) ! {
	directory := state_directory(work)
	assert os.readlink(directory + '/current')! == 'generations/5'
	for id in ['4', '5'] { assert os.read_file(directory + '/generations/' + id + '/payload')! == 'old version' }
	assert os.read_file(directory + '/objects/' + 'a'.repeat(64))! == 'offline cache'
	assert os.read_file(directory + '/objects/' + 'b'.repeat(64) + '.part')! == 'resume data'
	assert os.read_file(directory + '/generations/.stage-interrupted/keep')! == 'recovery data'
	assert os.read_file(work + '/home/user/.local/share/vinix-apps/app/data')! == 'personal data'
}

fn test_reviewed_cleanup_retains_active_previous_live_cache_recovery_and_personal_data() {
	for architecture in ['aarch64', 'x86_64'] {
		work := cleanup_fixture(architecture)!; defer { os.rmdir_all(work) or {} }
		directory := state_directory(work)
		service := Service{ root: work }
		os.write_file(directory + '/catalog.json', 'damaged unavailable publisher cache')!
		os.write_file(directory + '/trust-history.json', 'unavailable trust')!
		os.symlink(work + '/home', directory + '/generations/1/external')!
		lease := open_collection_generation(directory + '/generations/3')!
		defer { close_collection_lease(lease) }
		assert C.flock(lease.lease, C.LOCK_SH) == 0
		mut review := service.review_cleanup()!; defer { review.close() }
		assert review.architecture == architecture && review.generation == 5 && review.previous == 4
		assert review.generations == [u64(1), 2]
		for id in ['1', '2', '3'] { assert os.exists(directory + '/generations/' + id + '/payload') }
		cleanup_preserved(work)!
		service.apply_cleanup(review.fingerprint)!
		assert !os.exists(directory + '/generations/1') && !os.exists(directory + '/generations/2')
		assert os.exists(directory + '/generations/3/payload')
		cleanup_preserved(work)!
		assert C.flock(lease.lease, C.LOCK_UN) == 0
		mut next := service.review_cleanup()!; defer { next.close() }
		assert next.generations == [u64(3)]
		service.apply_cleanup(next.fingerprint)!
		assert !os.exists(directory + '/generations/3')
		cleanup_preserved(work)!
		mut empty := service.review_cleanup()!; defer { empty.close() }; assert empty.generations.len == 0
		service.apply_cleanup(empty.fingerprint)!
	}
	println('REVIEWED CLEANUP both architectures, offline/revoked catalog independence, retained active/rollback/live leases, cache, stages and personal data PASS')
}

fn test_cleanup_stale_approval_and_damaged_inventory_refuse_before_first_removal() {
	for change in ['config', 'activation', 'new-generation', 'root', 'parent', 'lease', 'busy', 'release', 'previous-state', 'unsafe-root'] {
		work := cleanup_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
		directory := state_directory(work)
		service := Service{ root: work }
		lease := open_collection_generation(directory + '/generations/3')!; defer { close_collection_lease(lease) }
		if change == 'release' { assert C.flock(lease.lease, C.LOCK_SH) == 0 }
		mut review := service.review_cleanup()!; defer { review.close() }
		match change {
			'config' { os.write_file(work + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: 'aarch64', policy: Policy{ reserve_bytes: 0 } }))! }
			'activation' { os.rm(directory + '/current')!; os.symlink('generations/4', directory + '/current')! }
			'new-generation' { os.mkdir(directory + '/generations/6')!; os.write_file(directory + '/generations/6/lease', '')! }
			'root' {
				os.rename(directory + '/generations/3', work + '/saved-3')!
				os.mkdir(directory + '/generations/3')!; os.write_file(directory + '/generations/3/lease', '')!
			}
			'parent' {
				os.rename(directory + '/generations', work + '/saved-generations')!
				os.mkdir(directory + '/generations')!
				for name in os.ls(work + '/saved-generations')! { os.rename(work + '/saved-generations/' + name, directory + '/generations/' + name)! }
			}
			'lease' { os.rename(directory + '/generations/3/lease', work + '/saved-lease')!; os.write_file(directory + '/generations/3/lease', '')! }
			'busy' { assert C.flock(lease.lease, C.LOCK_SH) == 0 }
			'release' { assert C.flock(lease.lease, C.LOCK_UN) == 0 }
			'previous-state' { os.write_file(directory + '/generations/4/state.json', '{}')! }
			'unsafe-root' { os.chmod(directory + '/generations/3', 0o777)! }
			else {}
		}
		mut refused := false
		service.apply_cleanup(review.fingerprint) or { refused = true; unsafe { err.free() } }
		assert refused, change
		for id in ['1', '2'] { assert os.exists(directory + '/generations/' + id + '/payload'), change }
		assert os.exists(directory + '/objects/' + 'a'.repeat(64))
		assert os.read_file(directory + '/generations/.stage-interrupted/keep')! == 'recovery data'
	}
	println('REVIEWED CLEANUP stale configuration/activation/set/root/parent/lease/busy/release approvals and damaged rollback/unsafe roots refuse before removal PASS')
}

fn test_cleanup_review_uses_reader_lock_and_does_not_initialize_fresh_storage() {
	work := os.temp_dir() + '/vinix-cleanup-fresh-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	defer { os.rmdir_all(work) or {} }
	os.mkdir_all(work + '/etc/vinix-packages')!
	os.write_file(work + '/etc/vinix-packages/config.json', json2.encode(Config{ architecture: 'aarch64' }))!
	service := Service{ root: work }
	mut empty := service.review_cleanup()!; defer { empty.close() }
	assert empty.generation == 0 && empty.generations.len == 0 && !os.exists(work + '/var')
	directory := state_directory(work)
	guard := acquire(directory)!
	mut refused := false
	service.review_cleanup() or { refused = true; unsafe { err.free() } }
	assert refused
	guard.release()
	mut review := service.review_cleanup()!; defer { review.close() }
	reader := acquire_reader(directory)!
	refused = false; service.apply_cleanup(review.fingerprint) or { refused = true; unsafe { err.free() } }
	assert refused; reader.release()
	refused = false; service.apply_cleanup('not-a-review') or { refused = true; unsafe { err.free() } }; assert refused
	println('REVIEWED CLEANUP read-only fresh observation, reader/writer exclusion and required approval PASS')
}

fn test_cleanup_ordinary_reader_and_all_inventory_preflight_on_root_owned_state() {
	if os.geteuid() != 0 { println('REVIEWED CLEANUP root-owned reader/inventory checks require guest root'); return }
	work := cleanup_fixture('aarch64')!; defer { os.rmdir_all(work) or {} }
	directory := state_directory(work)
	config := load_config(work)!; defer { close_decoded_configuration(config) }
	mut approved, targets := prepare_cleanup(config, directory, 0)!
	defer { approved.close(); close_collection_targets(targets) }
	child := C.fork(); assert child >= 0
	if child == 0 {
		assert C.setgroups(0, unsafe { nil }) == 0 && C.setgid(1000) == 0 && C.setuid(1000) == 0
		guard := acquire_reader(directory)!
		assert C.access(directory.str, C.W_OK) != 0
		mut observed, captured := prepare_cleanup(config, directory, 0)!
		assert observed == approved
		observed.close(); close_collection_targets(captured); guard.release()
		C._exit(0)
	}
	mut status := 0
	assert C.waitpid(child, unsafe { &status }, 0) == child && status == 0
	foreign := directory + '/generations/3/foreign'
	os.mkdir(foreign)!; assert C.chown(foreign.str, 1000, 1000) == 0
	service := Service{ root: work }
	mut refused := false; service.apply_cleanup(approved.fingerprint) or { refused = true; unsafe { err.free() } }
	assert refused && os.exists(directory + '/generations/1/payload') && os.exists(directory + '/generations/2/payload')
	assert C.chown(foreign.str, 0, 0) == 0
	service.apply_cleanup(approved.fingerprint)!
	cleanup_preserved(work)!
	println('REVIEWED CLEANUP ordinary UID 1000 reads root-owned state with identical approval; foreign nested inventory refuses before any deletion and restored inventory retries PASS')
}
