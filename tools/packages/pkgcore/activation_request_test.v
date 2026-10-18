// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os
import time
import tools.packages.signing

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn activation_request_cycles() int {
	$if activation_request_baseline ? { return 2 }
	return 64
}

fn retire_activation_reply(mut state State) {
	$if !activation_request_baseline ? { state.close(); state.close(); assert state.generation == 0 && state.packages.len == 0 }
}

struct ActivationFixture {
	work string
	root string
	directory string
	config Config
	first State
	second State
	cache string
	history string
	document string
}

fn activation_materialize(directory string, state State, content string) ! {
	number := state.generation.str(); path := directory + '/generations/' + number
	os.mkdir_all(path + '/apps/app/bin')!; os.mkdir_all(path + '/apps/assets/share')!; os.mkdir_all(path + '/share/applications')!
	os.write_file(path + '/lease', '')!; os.chmod(path + '/lease', 0o444)!
	os.write_file(path + '/apps/app/bin/app', content)!; os.chmod(path + '/apps/app/bin/app', 0o755)!
	os.write_file(path + '/apps/assets/share/data', 'asset data')!; os.chmod(path + '/apps/assets/share/data', 0o644)!
	entry := desktop_entry(state.packages[0].package)
	os.write_file(path + '/share/applications/vinix-app.desktop', entry)!
	encoded := encode_generation_state(state)!; os.write_file(path + '/state.json', encoded)!; flush_tree(path)!
	unsafe { number.free(); path.free(); entry.free(); encoded.free() }
}

fn activation_fixture(arch string) !ActivationFixture {
	work := os.temp_dir() + '/vinix-activation-request-' + os.getpid().str()
	root := work + '/root'; directory := state_directory(root)
	os.mkdir_all(root + '/etc/vinix-packages')!; os.mkdir_all(work + '/repository/objects')!
	private := signing.new_key_from_seed([]u8{len: 32, init: 7}); key := private.public_key().hex()
	repository := Repository{id: 'fixture', url: 'file://' + work + '/repository', public_key: key}
	config := Config{architecture: arch, repositories: [repository], policy: Policy{offline: true, reserve_bytes: 0}}
	p := canonical_package(Package{id: 'app', name: 'Application é🚀', description: 'Independent activation metadata', homepage: 'https://example.invalid/app',
		version: '1.0.0', architecture: arch, license: 'MIT', kind: 'native', entrypoint: 'bin/app', window_protocol: 2,
		arguments: ['--literal', 'argument with spaces'], permissions: ['files', 'display'], associations: ['text/plain'],
		dependencies: [Dependency{id: 'assets', minimum: '1.0.0', before: '3.0.0'}],
		files: [Payload{path: 'bin/app', sha256: sha256.hexhash('old payload'), bytes: 11, executable: true}]})!
	newer := Package{...p, version: '2.0.0', files: [Payload{path: 'bin/app', sha256: sha256.hexhash('new payload'), bytes: 11, executable: true}]}
	asset := Package{id: 'assets', name: 'Assets', version: '1.0.0', architecture: 'all', license: 'MIT', kind: 'data',
		files: [Payload{path: 'share/data', sha256: sha256.hexhash('asset data'), bytes: 10}]}
	old_record := Installed{package: p, repository: repository.id, public_key: key, sequence: 7}
	new_record := Installed{package: newer, repository: repository.id, public_key: key, sequence: 7}
	asset_record := Installed{package: asset, repository: repository.id, public_key: key, sequence: 7}
	first := State{generation: 1, architecture: arch, requested: ['app'], packages: [old_record, asset_record]}
	second := State{generation: 2, previous: 1, architecture: arch, requested: ['app'], packages: [new_record, asset_record]}
	index := canonical_index(Index{repository: repository.id, sequence: 7, expires: time.now().unix() + 86400, packages: [p, newer, asset]})!
	snapshot := Snapshot{repository: repository, text: index, signature: signing.sign(private, index.bytes())!.hex()}
	cache := json2.encode([snapshot]); history := json2.encode(TrustHistory{repositories: [RepositoryFloor{id: repository.id,
		public_key: key, sequence: 7, index_sha256: index_digest(index)}]})
	save_configuration(root + '/etc/vinix-packages/config.json', config)!
	guard := acquire(directory)!; guard.release()
	activation_materialize(directory, first, 'old payload')!; activation_materialize(directory, second, 'new payload')!
	for content in ['old payload', 'new payload', 'asset data']! {
		os.write_file(work + '/repository/objects/' + sha256.hexhash(content), content)!
	}
	mut document := owned_deployment_lock(arch, Plan{requested: ['app'], packages: second.packages})!
	encoded := json2.encode(document); document.close()
	return ActivationFixture{work: work, root: root, directory: directory, config: config, first: first, second: second,
		cache: cache, history: history, document: encoded}
}

fn activation_reset(f ActivationFixture, mode string) ! {
	directory := f.directory
	for name in ['3', '.stage-3', '.stage-sentinel', '18446744073709551615']! {
		path := directory + '/generations/' + name
		if os.exists(path) { os.rmdir_all(path)! }
	}
	current := directory + '/current'
	if os.is_link(current) || os.exists(current) { os.rm(current)! }
	old := mode in ['upgrade', 'install-kept', 'file-download', 'resume-download', 'missing-source', 'offline-missing',
		'stale-review', 'disk-refusal', 'interrupted', 'prepare-damage', 'published-damage', 'unsafe-stage', 'counter-exhausted',
		'deployment-legacy', 'deployment-lock', 'deployment-stale', 'rollback-unavailable']!
	if mode != 'install' { os.symlink(if old { 'generations/1' } else { 'generations/2' }, current)! }
	for state in [f.first, f.second] {
		path := directory + '/generations/' + state.generation.str()
		text := encode_generation_state(state)!; os.write_file(path + '/state.json', text)!; unsafe { text.free() }
		os.write_file(path + '/apps/app/bin/app', if state.generation == 1 { 'old payload' } else { 'new payload' })!
		os.chmod(path + '/apps/app/bin/app', 0o755)!
	}
	if mode == 'damaged-repair' { os.write_file(directory + '/generations/2/apps/app/bin/app', 'damaged bytes')! }
	cache := if mode == 'offline-missing' {
		snapshots := json2.decode[[]Snapshot](f.cache)!
		json2.encode([Snapshot{...snapshots[0], repository: Repository{...snapshots[0].repository, url: 'https://example.invalid'}}])
	} else { f.cache }
	os.write_file(directory + '/catalog.json', if mode == 'bad-cache' || mode.starts_with('rollback') { '{unavailable cache' } else { cache })!
	os.write_file(directory + '/trust-history.json', if mode == 'bad-history' || mode.starts_with('rollback') { '{unavailable history' } else { f.history })!
	if mode == 'bad-state' { os.write_file(directory + '/generations/2/state.json', '{broken state')! }
	for content in ['old payload', 'new payload', 'asset data']! {
		digest := sha256.hexhash(content); path := directory + '/objects/' + digest
		if os.exists(path) { os.rm(path)! }; if os.exists(path + '.part') { os.rm(path + '.part')! }
		if content != 'new payload' || mode !in ['file-download', 'resume-download', 'missing-source', 'offline-missing']! { os.write_file(path, content)! }
		os.write_file(f.work + '/repository/objects/' + digest, content)!
	}
	new_digest := f.second.packages[0].package.files[0].sha256
	if mode == 'resume-download' { os.write_file(directory + '/objects/' + new_digest + '.part', 'new ')! }
	if mode == 'missing-source' { os.rm(f.work + '/repository/objects/' + new_digest)! }
	if mode == 'unsafe-stage' { os.mkdir(directory + '/generations/.stage-sentinel')!; os.chmod(directory + '/generations/.stage-sentinel', 0o777)! }
	if mode == 'counter-exhausted' { os.mkdir(directory + '/generations/18446744073709551615')! }
	if mode in ['disk-refusal', 'stale-review']! {
		os.mkdir(directory + '/generations/.stage-sentinel')!; os.write_file(directory + '/generations/.stage-sentinel/keep', 'recovery data')!
	}
	configuration := if mode == 'offline-missing' { Config{...f.config, repositories: [Repository{...f.config.repositories[0], url: 'https://example.invalid'}]} }
		else if mode == 'rollback-revoked' || mode == 'empty-deploy' || mode == 'deployment-empty' { Config{...f.config, repositories: []} }
		else if mode == 'disk-refusal' { Config{...f.config, policy: Policy{...f.config.policy, reserve_bytes: u64(1024) * 1024 * 1024 * 1024}} }
		else { f.config }
	save_configuration(f.root + '/etc/vinix-packages/config.json', configuration)!
	if mode in ['busy', 'bad-config']! { os.write_file(f.root + '/etc/vinix-packages/config.json', '{broken configuration')! }
	if mode.starts_with('deployment-') {
		document := match mode { 'deployment-empty' { json2.encode(DeploymentLock{architecture: f.config.architecture}) }
			'deployment-legacy' { '{"format":1,"architecture":"' + f.config.architecture + '","packages":["app"]}' }
			'deployment-malformed' { '{broken deployment' } else { f.document } }
		os.write_file(f.work + '/deployment.json', document)!
	}
}

fn activation_checkpoint(phase string) {
	mode := os.getenv('VINIX_ACTIVATION_FAULT'); directory := os.getenv('VINIX_ACTIVATION_DIRECTORY')
	defer { unsafe { mode.free(); directory.free() } }
	if (phase == 'prepared' && mode == 'prepare-damage') || (phase == 'published' && mode == 'published-damage') {
		name := if phase == 'prepared' { '.stage-3' } else { '3' }
		path := directory + '/generations/' + name + '/state.json'
		defer { unsafe { path.free() } }; os.write_file(path, '{damaged metadata') or { panic(err) }
	}
}

fn activation_call(f ActivationFixture, mode string, explicit bool, expected string) !State {
	config := if mode == 'offline-missing' { Config{...f.config, repositories: [Repository{...f.config.repositories[0], url: 'https://example.invalid'}]} }
		else if mode == 'rollback-revoked' || mode == 'empty-deploy' { Config{...f.config, repositories: []} }
		else { f.config }
	defer { if mode == 'offline-missing' { unsafe { (&array(&config.repositories)).free() } } }
	service := Service{root: if mode == 'invalid-root' { 'relative' } else { f.root }}
	options := TransactionOptions{expected_review: expected, stop_before_activation: mode == 'interrupted', checkpoint: activation_checkpoint}
	if mode.starts_with('rollback') {
		if explicit { return rollback_reviewed(config, f.directory, expected) }; return service.rollback(expected)
	}
	if mode.starts_with('deployment-') {
		path := f.work + '/deployment.json'; defer { unsafe { path.free() } }
		if mode == 'deployment-stale' { return service.apply_deployment(path, expected) }
		return service.deploy(path)
	}
	operation := if mode in ['remove', 'blocked-remove']! { 'remove' }
		else if mode in ['repair', 'damaged-repair']! { 'repair' }
		else if mode == 'empty-deploy' { 'deploy' }
		else if mode in ['install', 'install-kept', 'bad-state', 'bad-cache', 'bad-history', 'busy', 'bad-config', 'invalid-root']! { 'install' }
		else { 'upgrade' }
	names := if mode == 'blocked-remove' { ['assets'] } else if operation in ['install', 'remove']! { ['app'] } else { []string{} }
	defer { unsafe { (&array(&names)).free() } }
	if explicit { return transact(config, f.directory, operation, names, options) }
	return service.transact(operation, names, options)
}

fn activation_scope(arch string, mode string, explicit bool) ! {
	label := arch + (if explicit { ' explicit ' } else { ' service ' }) + mode
	selection := os.getenv('VINIX_ACTIVATION_CASE'); defer { unsafe { selection.free(); label.free() } }
	if selection != '' && selection != label { return }
	f := activation_fixture(arch)!; defer { os.rmdir_all(f.work) or {} }
	os.setenv('VINIX_ACTIVATION_DIRECTORY', f.directory, true); os.setenv('VINIX_ACTIVATION_FAULT', mode, true)
	defer { os.unsetenv('VINIX_ACTIVATION_DIRECTORY'); os.unsetenv('VINIX_ACTIVATION_FAULT') }
	expected := if mode in ['stale-review', 'deployment-stale']! { 'f'.repeat(64) } else { '' }
	mut total := u64(0)
	for pass in 0 .. 2 {
		loops := if pass == 0 { 2 } else { activation_request_cycles() }
		for _ in 0 .. loops {
			activation_reset(f, mode)!
			before := if os.is_link(f.directory + '/current') { os.readlink(f.directory + '/current')! } else { '' }
			mut guard := Lock{fd: -1}; if mode == 'busy' { guard = acquire(f.directory)! }
			$if track_heap ? { C.vinix_heap_begin() }
			mut refused := false
			mut state := activation_call(f, mode, explicit, expected) or {
				refused = true; message := err.msg()
				wanted := match mode {
					'offline-missing' { 'offline mode' } 'missing-source' { 'offline repository file unavailable' }
					'stale-review', 'deployment-stale' { 'stale' } 'disk-refusal' { 'insufficient disk space' }
					'interrupted' { 'interrupted before activation' } 'prepare-damage' { 'metadata changed' }
					'published-damage' { 'not activated' } 'unsafe-stage' { 'unsafe unpublished' }
					'counter-exhausted' { 'counter exhausted' } 'busy' { 'another package transaction' }
					'bad-config' { 'invalid package configuration' } 'invalid-root' { 'absolute directory' }
					'rollback-unavailable' { 'no previous' } 'rollback-revoked' { 'no longer trusted' }
					'blocked-remove' { 'required by' } else { 'metadata' }
				}
				assert message.contains(wanted), label + ': ' + message
				unsafe { message.free(); err.free() }; State{}
			}
			if !refused {
				assert state.architecture == arch
				assert state.packages.len == if mode in ['remove', 'empty-deploy', 'deployment-empty']! { 0 } else { 2 }
				if state.packages.len != 0 { assert state.packages[0].package.arguments[1] == 'argument with spaces' }
				retire_activation_reply(mut state)
			}
			mut kept := u64(0); $if track_heap ? { kept = C.vinix_heap_end() }
			if pass == 1 { total += kept }
			if guard.fd >= 0 { guard.release() }
			fail := mode in ['blocked-remove', 'offline-missing', 'missing-source', 'stale-review', 'disk-refusal', 'interrupted',
				'prepare-damage', 'published-damage', 'bad-state', 'bad-cache', 'bad-history', 'unsafe-stage', 'counter-exhausted',
				'busy', 'bad-config', 'invalid-root', 'rollback-unavailable', 'rollback-revoked', 'deployment-stale', 'deployment-malformed']!
			assert refused == fail, label
			if refused { assert os.readlink(f.directory + '/current')! == before }
			assert os.exists(f.directory + '/generations/.stage-3') == (mode == 'interrupted')
			if mode == 'published-damage' { assert os.exists(f.directory + '/generations/3') }
			if mode in ['stale-review', 'disk-refusal']! { assert os.read_file(f.directory + '/generations/.stage-sentinel/keep')! == 'recovery data' }
			unsafe { before.free() }
		}
	}
	println('ACTIVATION REQUEST ' + label + ' retained ' + total.str() + ' tracked bytes')
	$if !activation_request_baseline ? { assert total == 0, label }
}

fn test_complete_activation_requests_retire_success_refusal_and_owned_replies() {
	for arch in ['aarch64', 'x86_64']! {
		for explicit in [false, true]! {
			for mode in ['install', 'upgrade', 'install-kept', 'repair', 'damaged-repair', 'remove', 'file-download',
				'offline-missing', 'stale-review', 'rollback', 'rollback-unavailable', 'rollback-revoked']! { activation_scope(arch, mode, explicit)! }
		}
		for mode in ['upgrade-noop', 'blocked-remove', 'empty-deploy', 'resume-download', 'missing-source', 'disk-refusal', 'interrupted',
			'prepare-damage', 'published-damage', 'bad-state', 'bad-cache', 'bad-history', 'unsafe-stage', 'counter-exhausted',
			'busy', 'bad-config', 'invalid-root', 'deployment-legacy', 'deployment-lock', 'deployment-empty', 'deployment-stale', 'deployment-malformed']! {
			activation_scope(arch, mode, false)!
		}
	}
	$if !activation_request_baseline ? {
		selection := os.getenv('VINIX_ACTIVATION_CASE'); defer { unsafe { selection.free() } }
		println(if selection == '' { 'ACTIVATION REQUEST 92 cases with 64 measured calls preserve activation, rollback, deployment and owned replies PASS' }
			else { 'ACTIVATION REQUEST selected case PASS' })
	}
}

fn test_activation_replies_outlive_configuration_and_sibling_replies() {
	$if activation_request_baseline ? { return }
	for arch in ['aarch64', 'x86_64']! {
		for mode in ['install', 'install-kept', 'repair', 'rollback', 'deployment-lock', 'deployment-empty']! {
			f := activation_fixture(arch)!
			activation_reset(f, mode)!
			config := load_config(f.root)!
			input := ActivationFixture{...f, config: config}
			mut first := activation_call(input, mode, !mode.starts_with('deployment-'), '')!
			activation_reset(f, mode)!
			mut second := activation_call(input, mode, !mode.starts_with('deployment-'), '')!
			close_decoded_configuration(config)
			assert first == second
			first.close(); first.close()
			os.rmdir_all(f.work)!
			assert second.architecture == arch && second.generation != 0
			if mode == 'deployment-empty' { assert second.packages.len == 0 && second.requested.len == 0 }
			else {
				p := second.packages[0].package
				assert p.name == 'Application é🚀' && p.description == 'Independent activation metadata'
				assert p.homepage == 'https://example.invalid/app' && p.arguments[1] == 'argument with spaces'
				assert p.permissions == ['display', 'files'] && p.associations[0] == 'text/plain'
				assert p.dependencies[0].before == '3.0.0' && p.files[0].path == 'bin/app'
				assert p.files[0].bytes == 11 && p.window_protocol == 2
				assert second.packages[0].repository == 'fixture' && digest_valid(second.packages[0].public_key)
				assert second.requested[0] == 'app' && second.packages[1].package.files[0].path == 'share/data'
			}
			second.close(); second.close()
		}
	}
	println('ACTIVATION REQUEST independent nested replies survive configuration, sibling and fixture retirement PASS')
}
