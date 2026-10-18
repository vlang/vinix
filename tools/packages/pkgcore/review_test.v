// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time
import tools.packages.pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn review_fixture(label string) !(string, Config) {
	return review_fixture_arch(label, 'aarch64')
}

fn review_fixture_arch(label string, architecture string) !(string, Config) {
	work := os.temp_dir() + '/vinix-review-' + label + '-' + os.getpid().str()
	os.mkdir_all(work + '/source/bin')!
	os.write_file(work + '/source/bin/runner', 'signed fixture runner\n')!
	os.chmod(work + '/source/bin/runner', 0o755)!
	key := keygen(work + '/seed')!
	config := Config{
		architecture: architecture
		repositories: [Repository{
			id:         'fixture'
			url:        'file://' + work + '/repository'
			public_key: key
		}]
		policy:       Policy{ licenses: ['Vendor-EULA'], allow_firmware: true, reserve_bytes: 0 }
	}
	for p in [
		Package{
			id:           'app'
			name:         'Application'
			version:      '1.0.0'
			architecture: architecture
			license:      'MIT'
			kind:         'linux'
			runtime:      'runtime'
			entrypoint:   'bin/runner'
			permissions:  ['files']
			dependencies: [Dependency{ id: 'runtime', before: '3.0.0' }, Dependency{ id: 'assets' }]
		},
		Package{ id: 'runtime', name: 'Runtime', version: '1.0.0', architecture: architecture, license: 'MIT', kind: 'runtime', permissions: ['process'] },
		Package{ id: 'assets', name: 'Licensed firmware assets', version: '1.0.0', architecture: 'all', license: 'Vendor-EULA', kind: 'data', proprietary: true, firmware: true },
	] {
		os.write_file(work + '/manifest.json', json2.encode(p))!
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
	}
	publish(work + '/repository', 'fixture', work + '/seed', 1, time.now().unix() + 3600)!
	refresh(config, work + '/state')!
	return work, config
}

fn test_reviews_compare_permissions_against_frozen_installed_state_on_both_hosts() {
	for arch in ['aarch64', 'x86_64']! {
		work, config := review_fixture_arch('permission-' + arch, arch)!
		defer { os.rmdir_all(work) or {} }
		directory := work + '/state'
		mut initial := review_operation(config, directory, 'install', ['app'])!
		assert initial.rows.all(!it.installed_permissions_known && it.installed_permissions.len == 0)
		transact(config, directory, 'install', ['app'], TransactionOptions{expected_review: initial.fingerprint})!
		initial.close()
		old := json2.decode[Package](read_metadata(work + '/repository/manifests/app-' + arch + '-1.0.0.json')!)!
		os.write_file(work + '/manifest.json', json2.encode(Package{...old, version: '2.0.0', permissions: ['display', 'network']}))!
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
		publish(work + '/repository', 'fixture', work + '/seed', 2, time.now().unix() + 3600)!
		refresh(config, directory)!
		mut update := review_operation(config, directory, 'upgrade', [])!
		assert update.rows[0].installed_permissions_known && update.rows[0].installed_permissions == ['files']
		assert update.rows[0].permissions == ['display', 'network'] && update.rows[0].installed_version == '1.0.0'
		assert update.rows[1].installed_permissions_known && update.rows[1].installed_permissions.len == 0
		assert update.rows[2].installed_permissions == ['process'] && update.rows[2].action == 'keep'
		transact(config, directory, 'upgrade', [], TransactionOptions{expected_review: update.fingerprint})!
		update.close()
		mut repair := review_operation(config, directory, 'repair', [])!
		assert repair.rows.all(it.installed_permissions_known && it.installed_permissions == it.permissions)
		repair.close()
		mut rollback := review_operation(config, directory, 'rollback', [])!
		assert rollback.rows[0].installed_permissions == ['display', 'network'] && rollback.rows[0].permissions == ['files']
		rollback_reviewed(config, directory, rollback.fingerprint)!
		rollback.close()
		// Removal reads the active generation even after trust/policy refusal.
		revoked := Config{...config, repositories: [], policy: Policy{permissions: [], reserve_bytes: 0}}
		mut removal := review_operation(revoked, directory, 'remove', ['app'])!
		assert removal.rows.all(it.installed_permissions_known && it.installed_permissions == it.permissions)
		assert removal.rows[0].installed_permissions == ['files']
		removal.close()
	}
	println('REVIEW PERMISSIONS both hosts retain installed declarations across new installs, updates, unchanged dependencies, empty sets, repair, rollback and revoked removal PASS')
}

fn test_review_permission_rows_retire_independently_owned_sets() {
	$if track_heap ? {
		before := Installed{package: Package{id: 'editor', name: 'Editor', version: '1.0.0', permissions: ['files']}, repository: 'trusted', public_key: 'a'.repeat(64)}
		after := Installed{...before, package: Package{...before.package, version: '2.0.0', permissions: ['display', 'network']}}
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				row := review_row_previous(after, before, true, 'update')
				assert row.installed_permissions.len == 1 && row.installed_permissions[0] == 'files'
				assert row.permissions.len == 2 && row.permissions[0] == 'display' && row.permissions[1] == 'network'
				assert row.installed_permissions.data != before.package.permissions.data
				mut rows := []pkgprotocol.ReviewPackage{cap: 1}
				pointer := unsafe { &row }; unsafe { rows.push_many(pointer, 1) }
				mut reply := pkgprotocol.Review{rows: rows}; reply.close(); reply.close()
			}
		}
		kept := C.vinix_heap_end(); assert kept == 0, 'review rows retained ' + kept.str()
		println('REVIEW PERMISSIONS 1000 independently owned before/target row creation and retirement cycles retain zero tracked bytes PASS')
	}
}

fn test_review_contains_dependencies_provenance_licenses_and_disk_estimate() {
	work, config := review_fixture('closure')!
	defer { os.rmdir_all(work) or {} }
	directory := work + '/state'
	mut review := review_operation(config, directory, 'install', ['app'])!
	defer { review.close() }
	assert review.format == 2 && review.generation == 0 && review.requested == ['app']
	assert review.rows.map(it.id) == ['app', 'assets', 'runtime']
	assert review.rows.all(it.action == 'install' && it.repository == 'fixture' && it.public_key == config.repositories[0].public_key)
	assert review.rows[0].runtime == 'runtime' && review.rows[0].permissions == ['files']
	assert review.rows[1].firmware && review.rows[1].proprietary && review.rows[1].license == 'Vendor-EULA'
	assert review.rows[2].permissions == ['process'] && !review.rows[2].requested
	mut decoded := pkgprotocol.decode_review(json2.encode(review))!
	assert decoded == review
	decoded.close()
	assert review.disk_needed > 4 * 1024 * 1024 && review.disk_available > 0
	assert read_state(directory, 'aarch64')!.generation == 0
	assert os.ls(directory + '/objects')!.len == 0 && os.ls(directory + '/generations')!.len == 0
	second := review_operation(config, directory, 'install', ['app'])!
	assert second.fingerprint == review.fingerprint
	installed := transact(config, directory, 'install', ['app'], TransactionOptions{ expected_review: review.fingerprint })!
	assert installed.packages.len == 3 && installed.generation == 1
	unchanged := review_operation(config, directory, 'install', ['app'])!
	assert unchanged.rows.all(it.action == 'keep') && unchanged.disk_needed == 0
	assert transact(config, directory, 'install', ['app'], TransactionOptions{ expected_review: unchanged.fingerprint })!.generation == 1
	// Shared preview locks do not wait behind a running writer.
	guard := acquire(directory)!
	mut refused := false
	review_operation(config, directory, 'remove', ['app']) or { refused = err.msg().contains('transaction') }
	guard.release()
	assert refused
}

fn test_review_refuses_changed_state_catalog_policy_and_intent_before_acquisition() {
	work, config := review_fixture('stale')!
	defer { os.rmdir_all(work) or {} }
	directory := work + '/state'
	initial := review_operation(config, directory, 'install', ['app'])!
	// Changed intent cannot consume another operation's fingerprint.
	mut refused := false
	transact(config, directory, 'install', ['runtime'], TransactionOptions{ expected_review: initial.fingerprint }) or { refused = err.msg().contains('stale') }
	assert refused && read_state(directory, 'aarch64')!.generation == 0
	modified_policy := Config{ ...config, policy: Policy{ ...config.policy, reserve_bytes: 1 } }
	refused = false
	transact(modified_policy, directory, 'install', ['app'], TransactionOptions{ expected_review: initial.fingerprint }) or { refused = err.msg().contains('stale') }
	assert refused && os.ls(directory + '/objects')!.len == 0
	// An authenticated catalog refresh with a new runtime requires fresh review.
	old := json2.decode[Package](read_metadata(work + '/repository/manifests/runtime-aarch64-1.0.0.json')!)!
	os.write_file(work + '/manifest.json', json2.encode(Package{ ...old, version: '2.0.0', permissions: [
		'process',
		'network',
	] }))!
	pack(work + '/manifest.json', work + '/source', work + '/repository')!
	publish(work + '/repository', 'fixture', work + '/seed', 2, time.now().unix() + 3600)!
	refresh(config, directory)!
	os.mkdir_all(directory + '/generations/.stage-sentinel')!
	refused = false
	transact(config, directory, 'install', ['app'], TransactionOptions{ expected_review: initial.fingerprint }) or { refused = err.msg().contains('stale') }
	assert refused && os.ls(directory + '/objects')!.len == 0
	assert os.is_dir(directory + '/generations/.stage-sentinel')
	fresh := review_operation(config, directory, 'install', ['app'])!
	assert fresh.fingerprint != initial.fingerprint
	assert fresh.rows[2].version == '2.0.0' && fresh.rows[2].permissions == ['network', 'process']
	transact(config, directory, 'install', ['app'], TransactionOptions{ expected_review: fresh.fingerprint })!
	refused = false
	transact(config, directory, 'install', ['app'], TransactionOptions{ expected_review: fresh.fingerprint }) or { refused = err.msg().contains('stale') }
	assert refused && read_state(directory, 'aarch64')!.generation == 1
}

fn test_review_removal_after_revocation_and_reviewed_rollback() {
	work, config := review_fixture('remove-rollback')!
	defer { os.rmdir_all(work) or {} }
	directory := work + '/state'
	transact(config, directory, 'install', ['app'], TransactionOptions{})!
	revoked := Config{ ...config, repositories: [], policy: Policy{ permissions: [], reserve_bytes: 0 } }
	removal := review_operation(revoked, directory, 'remove', ['app'])!
	assert removal.rows.len == 3 && removal.rows.all(it.action == 'remove' && !it.requested)
	transact(revoked, directory, 'remove', ['app'], TransactionOptions{ expected_review: removal.fingerprint })!
	assert read_state(directory, 'aarch64')!.packages.len == 0
	mut refused := false
	review_operation(revoked, directory, 'rollback', []) or { refused = true }
	assert refused
	rollback_review := review_operation(config, directory, 'rollback', [])!
	assert rollback_review.target_generation == 1 && rollback_review.rows.all(it.action == 'install')
	assert rollback_review.disk_needed > 4 * 1024 * 1024
	assert rollback_reviewed(config, directory, rollback_review.fingerprint)!.generation == 3
	refused = false
	rollback_reviewed(config, directory, rollback_review.fingerprint) or { refused = true }
	assert refused && read_state(directory, 'aarch64')!.generation == 3
	// Rollback preview verifies the retained bytes, rather than only their metadata.
	transact(config, directory, 'remove', ['app'], TransactionOptions{})!
	os.write_file(directory + '/generations/3/apps/runtime/bin/runner', 'tampered\n')!
	refused = false
	review_operation(config, directory, 'rollback', []) or { refused = err.msg().contains('verification') }
	assert refused
}
