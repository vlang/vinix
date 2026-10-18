// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn construction_cycles() int {
	$if review_construction_baseline ? { return 8 }
	return 128
}

fn construction_state(architecture string, newer bool) State {
	mut packages := []Installed{cap: 16}; mut roots := []string{cap: 16}
	for i in 0 .. 16 {
		number := (i + if newer { 0 } else { 1 }).str()
		id := 'app-' + if number.len == 1 { '0' + number } else { number.clone() }
		unsafe { number.free() }
		roots << id.clone()
		packages << Installed{repository: 'publisher', public_key: 'b'.repeat(64), sequence: 7,
			package: Package{id: id, name: 'Application é🚀'.clone(), description: 'complete description '.repeat(64),
				version: if newer { '2.0.0' } else { '1.0.0' }, architecture: architecture.clone(), kind: 'native',
				license: 'MIT', entrypoint: 'bin/app', permissions: [if newer { 'network' } else { 'files' }],
				files: [Payload{path: 'bin/app', sha256: 'c'.repeat(64), bytes: 1, executable: true}]}}
	}
	return State{architecture: architecture.clone(), generation: 7, previous: 3, requested: roots, packages: packages}
}

fn construction_check_bytes(label string, bytes u64) {
	println('REVIEW CONSTRUCTION ' + label + ' retained ' + bytes.str() + ' tracked bytes')
	$if !review_construction_baseline ? { assert bytes == 0, label }
}

fn construction_failure(config Config, directory string, current State, plan Plan, fingerprint string, expected string) {
	mut review := review_plan(config, directory, current, 'upgrade', [], plan, 0, [], fingerprint) or {
		message := err.msg(); assert message.contains(expected), message
		unsafe { message.free(); err.free() }; return
	}
	review.close(); assert false, 'review construction unexpectedly succeeded'
}

fn test_review_construction_and_refusals_retire_rows_counters_and_fingerprints() {
	$if !track_heap ? { return }
	$if track_heap ? {
		root := os.temp_dir() + '/vinix-review-construction-' + os.getpid().str()
		os.mkdir_all(root + '/generations/7')!; os.mkdir(root + '/generations/12')!; os.mkdir(root + '/generations/staging.tmp')!
		defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
		for arch in ['aarch64', 'x86_64']! {
			config := Config{architecture: arch, policy: Policy{permissions: [], reserve_bytes: 0}}
			old := construction_state(arch, false); target := construction_state(arch, true)
			defer { close_decoded_state(old); close_decoded_state(target) }
			plan := Plan{requested: target.requested, packages: target.packages}
			noop := Plan{requested: old.requested, packages: old.packages}
			oversized := Installed{...plan.packages[0], package: Package{...plan.packages[0].package,
				files: [Payload{...plan.packages[0].package.files[0], bytes: ~u64(0)}]}}
			mut overflow_packages := plan.packages.clone(); overflow_packages[0] = oversized
			defer { unsafe { (&array(&overflow_packages)).free(); (&array(&oversized.package.files)).free() } }
			overflow := Plan{requested: plan.requested, packages: overflow_packages}
			fingerprint := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
			defer { unsafe { fingerprint.free() } }
			missing := root + '/missing'; defer { unsafe { missing.free() } }
			for warmup in 0 .. 2 {
				if warmup == 1 { C.vinix_heap_begin() }
				for _ in 0 .. construction_cycles() {
					mut value := review_plan(config, root, old, 'upgrade', [], plan, 0, [], fingerprint)!
					assert value.rows.len == 17 && value.disk_needed > 0 && value.generation == 7
					assert value.rows[0].action == 'install' && value.rows[16].action == 'remove'
					value.close(); value.close()
					mut unchanged := review_plan(config, root, old, 'upgrade', [], noop, 0, [], fingerprint)!
					assert unchanged.disk_needed == 0 && unchanged.rows.len == 16; unchanged.close()
					construction_failure(config, missing, old, noop, fingerprint, 'available disk space')
					construction_failure(config, root, old, plan, 'invalid', 'invalid package review')
					construction_failure(config, root, old, overflow, fingerprint, 'requirement overflow')
				}
			}
			kept := C.vinix_heap_end()
			construction_check_bytes(arch + ' changed/no-op/space/validation cycles', kept)
			for name in ['01', '18446744073709551615', '18446744073709551616']! {
				path := root + '/generations/' + name; os.mkdir(path)!
				C.vinix_heap_begin()
				for _ in 0 .. construction_cycles() { construction_failure(config, root, old, plan, fingerprint, if name == '01' { 'canonical positive' } else if name == '18446744073709551615' { 'counter exhausted' } else { 'exceeds u64' }) }
				retained := C.vinix_heap_end()
				construction_check_bytes(arch + ' generation ' + name, retained)
				os.rmdir(path)!; unsafe { path.free() }
			}
		}
	}
	$if !review_construction_baseline ? { println('REVIEW CONSTRUCTION both hosts preserve changed/no-op proposals, reject space/validation/generation failures and retire 128 repeated calls per case PASS') }
}

fn test_review_fingerprints_match_old_encoding_and_retire_all_hash_storage() {
	config := Config{architecture: 'aarch64', policy: Policy{permissions: [], reserve_bytes: 0}}
	old := construction_state('aarch64', false); target := construction_state('aarch64', true)
	defer { close_decoded_state(old); close_decoded_state(target) }
	plan := Plan{requested: target.requested, packages: target.packages}
	document := DeploymentLock{architecture: 'aarch64', packages: target.requested}
	for operation in ['install', 'remove', 'upgrade', 'repair', 'deploy', 'rollback']! {
		for repairs in [false, true]! {
			items := if repairs { ['app-01'] } else { []string{} }
			defer { unsafe { (&array(&items)).free() } }
			before := json2.encode(ReviewIdentity{config: config, operation: operation, names: target.requested, current: old,
				plan: plan, target_generation: if operation == 'rollback' { u64(3) } else { u64(0) }, repairs: items})
			expected := index_digest(before)
			fingerprint := review_fingerprint(config, operation, target.requested, old, plan, if operation == 'rollback' { u64(3) } else { u64(0) }, items)
			assert expected == fingerprint
			unsafe { before.free(); expected.free(); fingerprint.free() }
		}
	}
	previous := json2.encode(DeploymentIdentity{config: config, current: old, document: document, plan: plan, repairs: ['app-01']})
	expected := index_digest(previous)
	actual := deployment_fingerprint(config, old, document, plan, ['app-01'])
	assert expected == actual
	unsafe { previous.free(); expected.free(); actual.free() }
	$if track_heap ? {
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. if construction_cycles() == 8 { 32 } else { 1000 } {
				first := review_fingerprint(config, 'upgrade', [], old, plan, 0, [])
				second := deployment_fingerprint(config, old, document, plan, [])
				unsafe { first.free(); second.free() }
			}
		}
		construction_check_bytes('ordinary/deployment fingerprint cycles', C.vinix_heap_end())
	}
	$if !review_construction_baseline ? { println('REVIEW CONSTRUCTION ordinary/deployment identities retain exact prior JSON digests, repair domains and 1000 repeated hash retirements PASS') }
}

fn test_review_construction_owns_fingerprint_and_rows_after_borrowed_inputs_retire() {
	$if review_construction_baseline ? { return }
	root := os.temp_dir() + '/vinix-review-independent-' + os.getpid().str()
	os.mkdir_all(root + '/generations/7')!
	defer { os.rmdir_all(root) or {}; unsafe { root.free() } }
	for arch in ['aarch64', 'x86_64']! {
		config := Config{architecture: arch, policy: Policy{permissions: [], reserve_bytes: 0}}
		old := construction_state(arch, false); target := construction_state(arch, true)
		fingerprint := 'a'.repeat(64)
		mut review := review_plan(config, root, old, 'deploy', target.requested,
			Plan{requested: target.requested, packages: target.packages}, 0, [], fingerprint)!
		assert review.fingerprint.str != fingerprint.str && review.rows[1].id.str != target.packages[1].package.id.str
		before := json2.encode(review)
		close_decoded_state(old); close_decoded_state(target); unsafe { fingerprint.free() }
		review.validate()!
		after := json2.encode(review); assert before == after
		assert review.rows[1].installed_permissions[0] == 'files' && review.rows[1].permissions[0] == 'network'
		review.close(); review.close(); unsafe { before.free(); after.free() }
	}
	println('REVIEW CONSTRUCTION independently owned fingerprints, rows and prior declarations survive input retirement on both hosts PASS')
}
