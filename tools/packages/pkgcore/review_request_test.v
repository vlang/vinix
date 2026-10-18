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

fn request_cycles() int {
	$if review_request_baseline ? { return 2 }
	return 64
}

fn request_call(service Service, operation string, names []string, document string) !pkgprotocol.Review {
	if document != '' { return service.review_deployment(document) }
	return service.review(operation, names)
}

// The measured window includes the complete public request and reply/error
// retirement. Fixture construction, maintenance and configuration edits precede it.
fn request_scope(label string, service Service, operation string, names []string, document string, rows int, expected string) {
	for warmup in 0 .. 2 {
		if warmup == 1 { $if track_heap ? { C.vinix_heap_begin() } }
		for _ in 0 .. request_cycles() {
			mut review := request_call(service, operation, names, document) or {
				message := err.msg()
				assert expected != '' && message.contains(expected), label + ': ' + message
				unsafe { message.free(); err.free() }
				continue
			}
			assert expected == '', label
			assert review.rows.len == rows && review.operation == operation && digest_valid(review.fingerprint)
			review.validate() or { panic(err) }
			review.close(); review.close()
		}
	}
	mut kept := u64(0)
	$if track_heap ? { kept = C.vinix_heap_end() }
	println('REVIEW REQUEST ' + label + ' retained ' + kept.str() + ' tracked bytes')
	$if !review_request_baseline ? { assert kept == 0, label }
}

fn request_publish(work string, arch string, version string, sequence u64) ! {
	app := Package{id: 'app', name: 'Application é🚀', description: 'Complete signed application description',
		version: version, architecture: arch, license: 'MIT', kind: 'native', entrypoint: 'bin/app',
		permissions: if version == '1.0.0' { ['files'] } else { ['files', 'network'] },
		dependencies: [Dependency{id: 'runtime'}, Dependency{id: 'assets'}]}
	for p in [app, Package{id: 'runtime', name: 'Runtime', version: '1.0.0', architecture: arch, license: 'MIT', kind: 'runtime'},
		Package{id: 'assets', name: 'Assets', version: '1.0.0', architecture: 'all', license: 'MIT', kind: 'data'}] {
		text := json2.encode(p); os.write_file(work + '/manifest.json', text)!; unsafe { text.free() }
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
	}
	publish(work + '/repository', 'fixture', work + '/seed', sequence, time.now().unix() + 3600)!
}

fn request_save(path string, document DeploymentLock) ! {
	text := json2.encode(document); defer { unsafe { text.free() } }; os.write_file(path, text)!
}

fn test_complete_review_requests_retire_preparation_and_preserve_signed_state() {
	$if !track_heap ? { return }
	$if track_heap ? {
		for arch in ['aarch64', 'x86_64']! {
			work := os.temp_dir() + '/vinix-review-request-' + arch + '-' + os.getpid().str()
			root := work + '/root'; directory := state_directory(root)
			config_path := root + '/etc/vinix-packages/config.json'
			os.mkdir_all(root + '/etc/vinix-packages')!; os.mkdir_all(work + '/source/bin')!
			os.write_file(work + '/source/bin/app', 'signed application\n')!; os.chmod(work + '/source/bin/app', 0o755)!
			defer { os.rmdir_all(work) or {} }
			key := keygen(work + '/seed')!
			config := Config{architecture: arch, repositories: [Repository{id: 'fixture', url: 'file://' + work + '/repository', public_key: key}],
				policy: Policy{reserve_bytes: 0}}
			save_configuration(config_path, config)!
			service := Service{root: root}; offline := Service{root: root, offline: true}
			app := ['app']; runtime := ['runtime']; missing := ['missing']; empty := []string{}
			defer { unsafe { (&array(&app)).free(); (&array(&runtime)).free(); (&array(&missing)).free(); (&array(&empty)).free() } }
			request_publish(work, arch, '1.0.0', 1)!; service.refresh()!
			request_scope(arch + ' fresh install', service, 'install', app, '', 3, '')
			request_scope(arch + ' fresh repair', service, 'repair', empty, '', 0, '')
			request_scope(arch + ' fresh rollback refusal', service, 'rollback', empty, '', 0, 'no previous')
			service.transact('install', app, TransactionOptions{})!
			mut old_lock := service.lock_deployment(empty)!; old_path := work + '/old.json'; request_save(old_path, old_lock)!
			old_lock.close()
			request_publish(work, arch, '2.0.0', 2)!; service.refresh()!
			request_scope(arch + ' upgrade', service, 'upgrade', empty, '', 3, '')
			service.transact('upgrade', empty, TransactionOptions{})!
			mut deployment_lock := service.lock_deployment(empty)!; exact_path := work + '/exact.json'; request_save(exact_path, deployment_lock)!
			bad_pin := DeploymentLock{...deployment_lock, locked: [DeploymentPackage{...deployment_lock.locked[0], metadata_sha256: '0'.repeat(64)}, ...deployment_lock.locked[1..]]}
			bad_pin_path := work + '/bad-pin.json'; request_save(bad_pin_path, bad_pin)!; deployment_lock.close()
			legacy_path := work + '/legacy.json'; os.write_file(legacy_path, '{"format":1,"architecture":"' + arch + '","packages":["app"]}')!
			empty_path := work + '/empty.json'; request_save(empty_path, DeploymentLock{architecture: arch})!
			bad_path := work + '/bad.json'; os.write_file(bad_path, '{"format":2,"architecture":')!
			// Retain bytes outside measurement. Reviews may take/release their lock,
			// but cannot activate, rewrite state/catalog/history or consume objects.
			mut paths := [config_path, directory + '/catalog.json', directory + '/trust-history.json',
				directory + '/generations/1/state.json', directory + '/generations/2/state.json']
			for name in os.ls(directory + '/objects')! { paths << directory + '/objects/' + name }
			mut snapshots := []string{}
			for path in paths { snapshots << os.read_file(path)! }
			for operation in ['install', 'upgrade', 'repair', 'rollback', 'remove', 'deploy']! {
				request_scope(arch + ' installed ' + operation, service, operation,
					if operation in ['install', 'remove', 'deploy']! { app } else { empty }, '', 3, '')
			}
			request_scope(arch + ' offline cached review', offline, 'install', app, '', 3, '')
			request_scope(arch + ' blocked removal', service, 'remove', runtime, '', 0, 'required by')
			request_scope(arch + ' missing package', service, 'install', missing, '', 0, 'missing')
			request_scope(arch + ' invalid repair arguments', service, 'repair', app, '', 0, 'takes no package IDs')
			request_scope(arch + ' invalid rollback arguments', service, 'rollback', app, '', 0, 'takes no package IDs')
			for path in [legacy_path, exact_path, old_path, empty_path]! {
				request_scope(arch + ' deployment ' + os.file_name(path), service, 'deploy', empty, path, 3, '')
			}
			request_scope(arch + ' refused exact pins', service, 'deploy', empty, bad_pin_path, 0, 'metadata')
			request_scope(arch + ' malformed deployment', service, 'deploy', empty, bad_path, 0, 'metadata')
			// A valid pin outside the selected closure fails after resolution.
			mut surplus := service.lock_deployment(empty)!
			request_save(bad_pin_path, DeploymentLock{...surplus, packages: runtime})!; surplus.close()
			request_scope(arch + ' surplus deployment closure', service, 'deploy', empty, bad_pin_path, 0, 'outside the requested')
			// The result must remain independent after the public request retires
			// its configuration, both states, authenticated catalog and document.
			mut names := ['app'.clone()]
			mut independent := service.review('install', names)!; unsafe { names.free() }
			assert independent.rows[0].permissions.len == 2 && independent.rows[0].installed_permissions[0] == 'files'
			text := json2.encode(independent); independent.validate()!; independent.close(); independent.close(); unsafe { text.free() }
			for i, path in paths { assert os.read_file(path)! == snapshots[i], path }
			assert os.readlink(directory + '/current')! == 'generations/2' && !os.exists(directory + '/generations/3')
			blocked := Config{...config, policy: Policy{permissions: [], reserve_bytes: 0}}
			save_configuration(config_path, blocked)!
			request_scope(arch + ' policy refusal', service, 'install', app, '', 0, 'permissions blocked')
			request_scope(arch + ' rollback policy refusal', service, 'rollback', empty, '', 0, 'permissions blocked')
			request_scope(arch + ' deployment policy refusal', service, 'deploy', empty, exact_path, 0, 'permissions blocked')
			save_configuration(config_path, Config{...config, repositories: []})!
			request_scope(arch + ' revoked rollback', service, 'rollback', empty, '', 0, 'no longer trusted')
			request_scope(arch + ' revoked removal', service, 'remove', app, '', 3, '')
			request_scope(arch + ' revoked empty deployment', service, 'deploy', empty, empty_path, 3, '')
			save_configuration(config_path, config)!
			// Damaged old payload refuses rollback; damaged current bytes produce
			// a repair review while leaving the damage untouched.
			old_payload := directory + '/generations/1/apps/app/bin/app'; old_bytes := os.read_file(old_payload)!
			os.write_file(old_payload, 'damaged')!
			request_scope(arch + ' damaged rollback', service, 'rollback', empty, '', 0, 'payload verification failed')
			os.write_file(old_payload, old_bytes)!
			registration := directory + '/generations/1/share/applications/vinix-app.desktop'
			registration_bytes := os.read_file(registration)!; os.write_file(registration, 'damaged')!
			request_scope(arch + ' damaged rollback registration', service, 'rollback', empty, '', 0, 'registration verification failed')
			os.write_file(registration, registration_bytes)!
			payload := directory + '/generations/2/apps/app/bin/app'; bytes := os.read_file(payload)!
			os.write_file(payload, 'damaged')!
			request_scope(arch + ' damaged repair', service, 'repair', empty, '', 3, '')
			assert os.read_file(payload)! == 'damaged'; os.write_file(payload, bytes)!
			for suffix in ['catalog.json', 'trust-history.json', 'generations/2/state.json']! {
				path := directory + '/' + suffix; original := os.read_file(path)!
				os.write_file(path, '{broken metadata')!
				request_scope(arch + ' corrupt ' + suffix, service, 'install', app, '', 0, 'metadata')
				request_scope(arch + ' deployment corrupt ' + suffix, service, 'deploy', empty, exact_path, 0, 'metadata')
				os.write_file(path, original)!; unsafe { path.free(); original.free() }
			}
			counter := directory + '/generations/01'; os.mkdir(counter)!
			request_scope(arch + ' late generation refusal', service, 'remove', app, '', 0, 'canonical positive')
			request_scope(arch + ' deployment late generation refusal', service, 'deploy', empty, empty_path, 0, 'canonical positive')
			os.rmdir(counter)!
			// A held writer must win over malformed configuration and documents.
			guard := acquire(directory)!
			os.write_file(config_path, '{broken configuration')!
			request_scope(arch + ' busy ordinary', service, 'install', app, '', 0, 'another package transaction')
			request_scope(arch + ' busy deployment', service, 'deploy', empty, bad_path, 0, 'another package transaction')
			guard.release()
			request_scope(arch + ' malformed configuration', service, 'install', app, '', 0, 'invalid package configuration')
			request_scope(arch + ' deployment malformed configuration', service, 'deploy', empty, exact_path, 0, 'invalid package configuration')
			save_configuration(config_path, config)!
			mut verified := service.verify()!; assert verified.generation == 2; verified.close()
			for i, path in paths { assert os.read_file(path)! == snapshots[i], path }
			assert os.readlink(directory + '/current')! == 'generations/2' && !os.exists(directory + '/generations/3')
		}
	}
	$if !review_request_baseline ? { println('REVIEW REQUEST complete public ordinary/deployment calls retire preparation and preserve signed state across 64 calls per case on both declarations PASS') }
}
