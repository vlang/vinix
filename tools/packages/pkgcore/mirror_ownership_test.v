// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import time
import json2

fn C.mkfifo(&char, u32) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn mirror_ownership_plan() Plan {
	mut packages := []Installed{cap: 16}
	for i in 0 .. 16 {
		packages << Installed{ repository: 'publisher', public_key: 'a'.repeat(64), sequence: 7,
			package: Package{ id: 'app-' + i.str(), version: '1.0.0', architecture: 'aarch64',
				name: 'Application', description: 'd'.repeat(2048), kind: 'native', entrypoint: 'bin/app', license: 'MIT',
				files: [Payload{ path: 'bin/app', sha256: 'b'.repeat(64), bytes: 7, executable: true }] } }
	}
	return Plan{ requested: ['app-0'], packages: packages }
}

fn test_mirror_preflight_retires_path_space_and_prepared_metadata_scratch() {
	$if track_heap ? {
		work := os.real_path(os.temp_dir()) + '/vinix-mirror-owned-' + os.getpid().str() + '-' + time.now().unix_micro().str()
		os.mkdir_all(work + '/store/objects')!
		defer { os.rmdir_all(work) or {} }
		store := work + '/store'; destination := work + '/missing/parents/export'
		plan := mirror_ownership_plan()
		config := Config{ architecture: 'aarch64', policy: Policy{ reserve_bytes: 0 } }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			target, parent := mirror_location(destination)!
			assert target == destination && parent == work
			unsafe { target.free(); parent.free() }
		}
		paths := C.vinix_heap_end()
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { exported, acquired := mirror_space(plan, [], store)!; assert exported > 0 && acquired > 0 }
		space := C.vinix_heap_end()
		mut warm := prepare_mirror_plan(config, store, destination, plan.requested, plan, '', '')!
		warm.close()
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut prepared := prepare_mirror_plan(config, store, destination, plan.requested, plan, '', '')!
			assert prepared.plan.packages.len == 16 && prepared.fingerprint.len == 64
			prepared.close(); prepared.close()
		}
		metadata := C.vinix_heap_end()
		println('MIRROR OWNERSHIP preflight: 1000 path cycles retained ${paths} bytes; 1000 space cycles retained ${space} bytes; 1000 warmed prepared metadata cycles retained ${metadata} bytes')
		assert paths == 0 && space == 0 && metadata == 0
	}
}

fn test_mirror_paths_preserve_normalization_aliases_and_owned_inputs() {
	cwd := os.getwd()
	for path in ['', '.', '..', 'a/./b//../c/', '/./a//b/../c', '/../../a', 'a/../../..', '/']! {
		expected := os.abs_path(path)
		actual := mirror_absolute_path(path)!
		assert actual == expected
		unsafe { expected.free(); actual.free() }
	}
	$if track_heap ? {
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { path := mirror_absolute_path('missing/../export')!; unsafe { path.free() } }
		kept := C.vinix_heap_end(); assert kept == 0, 'relative path retained ${kept} bytes'
	}
	assert os.getwd() == cwd
	println('MIRROR OWNERSHIP relative/absolute dot, backlink, repeated/trailing separator normalization and 1000 relative-path retirements PASS')
}

fn test_mirror_reviews_own_fields_after_prepared_storage_is_retired() {
	work := os.real_path(os.temp_dir()) + '/vinix-mirror-review-owned-' + os.getpid().str()
	os.mkdir_all(work + '/store/objects')!
	defer { os.rmdir_all(work) or {} }
	store := work + '/store'; destination := work + '/new-export'
	plan := mirror_ownership_plan()
	config := Config{ architecture: 'aarch64', policy: Policy{ reserve_bytes: 0 } }
	mut prepared := prepare_mirror_plan(config, store, destination, plan.requested, plan, '', '')!
	mut review := mirror_review(config, store, destination, plan.requested, prepared)!
	before := json2.encode(review)
	prepared.close()
	assert review.review.rows.len == 16 && review.review.rows[15].description.len == 2048 && json2.encode(review) == before
	review.close(); review.close()
	assert plan.packages[0].package.description.len == 2048 && plan.requested == ['app-0']
	mut live := prepare_mirror_plan(config, store, destination, plan.requested, plan, '', '')!
	defer { live.close() }
	$if track_heap ? {
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { mut result := mirror_review(config, store, destination, plan.requested, live)!; result.close() }
		kept := C.vinix_heap_end()
		println('MIRROR OWNERSHIP 1000 independent review build/retirement cycles retained ${kept} bytes')
		assert kept == 0
	}
	println('MIRROR OWNERSHIP review fields survive prepared retirement, repeated close and intact borrowed manifests PASS')
}

fn mirror_ownership_refused(config Config, store string, destination string, plan Plan, expected string) bool {
	if mut prepared := prepare_mirror_plan(config, store, destination, plan.requested, plan, '', '') {
		prepared.close()
		return false
	} else {
		message := unsafe { (&err).msg() }
		matched := message.contains(expected)
		unsafe { message.free(); (&err).free() }
		return matched
	}
}

fn test_mirror_preparation_failures_preserve_paths_and_retire_partial_storage() {
	work := os.real_path(os.temp_dir()) + '/vinix-mirror-fail-owned-' + os.getpid().str()
	os.mkdir_all(work + '/store/objects')!
	defer { os.rmdir_all(work) or {} }
	store := work + '/store'; destination := work + '/missing/export'
	plan := mirror_ownership_plan()
	config := Config{ architecture: 'aarch64', policy: Policy{ reserve_bytes: 0 } }
	os.write_file(work + '/file', 'preserve')!
	os.symlink(work + '/file', work + '/link')!
	os.symlink(work + '/absent', work + '/dangling')!
	fifo := work + '/fifo'; assert C.mkfifo(fifo.str, 0o600) == 0
	for leaf in ['file', 'link', 'dangling', 'fifo', 'store']! {
		assert mirror_ownership_refused(config, store, work + '/' + leaf, plan, 'must be new')
	}
	assert mirror_ownership_refused(config, store, work + '/file/export', plan, 'must be a directory')
	os.mkdir(work + '/unsafe')!; os.chmod(work + '/unsafe', 0o777)!
	assert mirror_ownership_refused(config, store, work + '/unsafe/export', plan, 'parent must be controlled')
	os.chmod(work + '/unsafe', 0o700)!
	unsafe_destination := work + '/unsafe/export'
	missing_store := work + '/absent-store'
	assert mirror_ownership_refused(config, missing_store, destination, plan, 'cannot inspect offline mirror filesystems')
	oversized := Plan{ requested: plan.requested, packages: [Installed{ ...plan.packages[0], package: Package{ ...plan.packages[0].package,
		files: [Payload{ ...plan.packages[0].package.files[0], bytes: ~u64(0) }] } }] }
	assert mirror_ownership_refused(config, store, destination, oversized, 'requirement overflow')
	$if track_heap ? {
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			assert mirror_ownership_refused(config, missing_store, destination, plan, 'cannot inspect offline mirror filesystems')
			assert mirror_ownership_refused(config, store, destination, oversized, 'requirement overflow')
		}
		kept := C.vinix_heap_end()
		println('MIRROR OWNERSHIP 2000 filesystem/overflow failure cycles retained ${kept} bytes')
		assert kept == 0
	}
	os.write_file(store + '/catalog.json', '[{"repository":{}}]')!
	assert mirror_ownership_refused(config, store, destination, plan, 'invalid cached repository metadata')
	os.rm(store + '/catalog.json')!
	mut retry := prepare_mirror_plan(config, store, unsafe_destination, plan.requested, plan, '', '')!
	retry.close()
	assert os.read_file(work + '/file')! == 'preserve' && os.readlink(work + '/link')! == work + '/file'
	assert os.readlink(work + '/dangling')! == work + '/absent'
	assert !os.exists(work + '/missing') && !os.exists(unsafe_destination) && os.ls(store + '/objects')!.len == 0
	println('MIRROR OWNERSHIP occupied/special/unsafe paths, malformed metadata, filesystem and overflow failures preserve inputs, retire scratch and permit retry PASS')
}

fn test_mirror_snapshot_selection_and_fingerprint_preserve_exact_identity() {
	work := os.real_path(os.temp_dir()) + '/vinix-mirror-identity-owned-' + os.getpid().str()
	os.mkdir_all(work + '/physical/store/objects')!
	defer { os.rmdir_all(work) or {} }
	os.symlink(work + '/physical', work + '/alias')!
	store := work + '/physical/store'; destination := work + '/alias/missing/export'
	plan := mirror_ownership_plan()
	repository := Repository{ id: 'publisher', url: 'file:///publisher', public_key: 'a'.repeat(64) }
	config := Config{ architecture: 'aarch64', repositories: [repository], policy: Policy{ reserve_bytes: 0 } }
	text := json2.encode([
		Snapshot{ repository: repository, text: 'preserved exact signed bytes\n', signature: 'c'.repeat(128) },
		Snapshot{ repository: Repository{ id: 'revoked', url: 'file:///revoked', public_key: 'd'.repeat(64) }, text: 'old signed bytes', signature: 'e'.repeat(128) },
	])
	os.write_file(store + '/catalog.json', text)!
	lock_text := '{"format":2,"exact":"captured bytes"}\n'
	for deployment in ['', work + '/lock.json'] {
		captured := if deployment == '' { '' } else { lock_text }
		mut prepared := prepare_mirror_plan(config, store, destination, plan.requested, plan, deployment, captured)!
		assert prepared.snapshots.len == 1 && prepared.source_snapshots.len == 2
		assert prepared.target == work + '/physical/missing/export' && prepared.ancestor == work + '/physical'
		mut info := C.stat{}
		assert C.fstatat(C.AT_FDCWD, prepared.ancestor.str, unsafe { &info }, 0) == 0
		identity := MirrorIdentity{ config: config, names: plan.requested, plan: plan, snapshots: prepared.snapshots,
			domain: if deployment == '' { 'vinix-mirror-review-1' } else { 'vinix-deployment-mirror-review-1' },
			destination: destination, target: prepared.target, ancestor: prepared.ancestor, device: u64(info.st_dev), inode: u64(info.st_ino),
			deployment: deployment, deployment_sha256: if captured == '' { '' } else { index_digest(captured) } }
		assert prepared.fingerprint == index_digest(json2.encode(identity))
		assert prepared.deployment_text == captured
		prepared.close(); prepared.close()
	}
	mut live := prepare_mirror_plan(config, store, destination, plan.requested, plan, '', '')!
	os.rm(store + '/catalog.json')!
	assert live.snapshots[0].text == 'preserved exact signed bytes\n'
	live.close()
	assert plan.packages[0].repository == repository.id && config.repositories[0] == repository
	assert !os.exists(work + '/physical/missing')
	println('MIRROR OWNERSHIP physical aliases, selected/revoked snapshot lifetimes and byte-identical ordinary/deployment review fingerprints PASS')
}
