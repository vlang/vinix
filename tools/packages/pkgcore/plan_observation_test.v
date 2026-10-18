// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn plan_observation_cycles() int {
	$if plan_observation_baseline ? { return 2 }
	return 64
}

fn retire_observed_plan(mut plan Plan) {
	$if !plan_observation_baseline ? {
		plan.close(); plan.close()
		assert plan.requested.len == 0 && plan.packages.len == 0
	}
}

fn observed_plan_call(service Service, config Config, directory string, snapshot bool, operation string, names []string) !Plan {
	if snapshot { return preview_plan(config, directory, operation, names) }
	return service.plan(operation, names)
}

fn observed_plan_scope(label string, service Service, config Config, directory string, snapshot bool, operation string, names []string, count int, version string, expected string) {
	for warmup in 0 .. 2 {
		if warmup == 1 { $if track_heap ? { C.vinix_heap_begin() } }
		for _ in 0 .. plan_observation_cycles() {
			mut result := observed_plan_call(service, config, directory, snapshot, operation, names) or {
				message := err.msg(); assert expected != '' && message.contains(expected), label + ': ' + message
				unsafe { message.free(); err.free() }; continue
			}
			assert expected == '' && result.packages.len == count, label
			if count != 0 {
				assert result.packages[0].package.id == 'app' && result.packages[0].package.version == version
				assert result.packages[0].package.arguments[1] == 'literal é🚀 argument'
				assert result.packages[0].package.dependencies[0].minimum == '1.0.0'
				assert result.packages[0].package.window_protocol == 2 && result.packages[1].package.firmware
			}
			retire_observed_plan(mut result)
		}
	}
	mut kept := u64(0); $if track_heap ? { kept = C.vinix_heap_end() }
	println('PLAN OBSERVATION ' + label + ' retained ' + kept.str() + ' tracked bytes')
	$if !plan_observation_baseline ? { assert kept == 0, label }
}

fn observed_plan_publish(work string, arch string, version string, sequence u64) ! {
	for p in [
		Package{id: 'app', name: 'Application é🚀', description: 'Complete signed application description', homepage: 'https://example.invalid/app',
			version: version, architecture: arch, license: 'MIT', kind: 'native', entrypoint: 'bin/app', window_protocol: 2,
			permissions: if version == '1.0.0' { ['files', 'display'] } else { ['files', 'display', 'network'] },
			arguments: ['--literal', 'literal é🚀 argument'], associations: ['text/plain', 'application/x-plan'],
			dependencies: [Dependency{id: 'assets', minimum: '1.0.0', before: '3.0.0'}, Dependency{id: 'runtime', minimum: '1.0.0', before: '3.0.0'}]},
		Package{id: 'runtime', name: 'Runtime', version: '1.0.0', architecture: arch, license: 'MIT', kind: 'runtime'},
		Package{id: 'assets', name: 'Licensed firmware', version: '1.0.0', architecture: 'all', license: 'Vendor-EULA', kind: 'data', proprietary: true, firmware: true},
	] {
		text := json2.encode(p); os.write_file(work + '/manifest.json', text)!; unsafe { text.free() }
		pack(work + '/manifest.json', work + '/source', work + '/repository')!
	}
	publish(work + '/repository', 'fixture', work + '/seed', sequence, time.now().unix() + 3600)!
}

fn test_complete_plan_observations_retire_preparation_and_owned_replies() {
	$if !track_heap ? { return }
	$if track_heap ? {
		for arch in ['aarch64', 'x86_64']! {
			work := os.temp_dir() + '/vinix-plan-observation-' + arch + '-' + os.getpid().str()
			root := work + '/root'; directory := state_directory(root); path := root + '/etc/vinix-packages/config.json'
			os.mkdir_all(root + '/etc/vinix-packages')!; os.mkdir_all(work + '/source/bin')!
			os.write_file(work + '/source/bin/app', 'signed application\n')!; os.chmod(work + '/source/bin/app', 0o755)!
			defer { os.rmdir_all(work) or {} }
			key := keygen(work + '/seed')!
			config := Config{architecture: arch, repositories: [Repository{id: 'fixture', url: 'file://' + work + '/repository', public_key: key}],
				policy: Policy{licenses: ['Vendor-EULA'], allow_firmware: true, reserve_bytes: 0}}
			save_configuration(path, config)!; service := Service{root: root}; offline := Service{root: root, offline: true}
			app := ['app']; runtime := ['runtime']; missing := ['missing']; empty := []string{}
			observed_plan_publish(work, arch, '1.0.0', 1)!; service.refresh()!
			for snapshot in [false, true]! {
				label := arch + if snapshot { ' explicit' } else { ' service' }
				observed_plan_scope(label + ' fresh install', service, config, directory, snapshot, 'install', app, 3, '1.0.0', '')
				observed_plan_scope(label + ' fresh repair', service, config, directory, snapshot, 'repair', empty, 0, '', '')
				observed_plan_scope(label + ' empty deploy', service, config, directory, snapshot, 'deploy', empty, 0, '', '')
			}
			service.transact('install', app, TransactionOptions{})!
			observed_plan_publish(work, arch, '2.0.0', 2)!; service.refresh()!
			for snapshot in [false, true]! {
				label := arch + if snapshot { ' explicit' } else { ' service' }
				observed_plan_scope(label + ' available upgrade', service, config, directory, snapshot, 'upgrade', empty, 3, '2.0.0', '')
				observed_plan_scope(label + ' preserved installed', service, config, directory, snapshot, 'install', app, 3, '1.0.0', '')
				observed_plan_scope(label + ' exact repair', service, config, directory, snapshot, 'repair', empty, 3, '1.0.0', '')
			}
			service.transact('upgrade', empty, TransactionOptions{})!
			mut paths := [path, directory + '/catalog.json', directory + '/trust-history.json', directory + '/generations/1/state.json', directory + '/generations/2/state.json']
			for name in os.ls(directory + '/objects')! { paths << directory + '/objects/' + name }
			mut contents := []string{}; for file in paths { contents << os.read_file(file)! }
			for snapshot in [false, true]! {
				label := arch + if snapshot { ' explicit' } else { ' service' }
				for operation in ['install', 'upgrade', 'repair', 'deploy']! {
					observed_plan_scope(label + ' installed ' + operation, service, config, directory, snapshot, operation,
						if operation in ['install', 'deploy']! { app } else { empty }, 3, '2.0.0', '')
				}
				observed_plan_scope(label + ' remove', service, config, directory, snapshot, 'remove', app, 0, '', '')
				observed_plan_scope(label + ' blocked removal', service, config, directory, snapshot, 'remove', runtime, 0, '', 'required by')
				observed_plan_scope(label + ' missing', service, config, directory, snapshot, 'install', missing, 0, '', 'missing')
				observed_plan_scope(label + ' invalid repair', service, config, directory, snapshot, 'repair', app, 0, '', 'takes no package IDs')
				observed_plan_scope(label + ' invalid upgrade', service, config, directory, snapshot, 'upgrade', app, 0, '', 'complete installed closure')
				observed_plan_scope(label + ' unknown operation', service, config, directory, snapshot, 'rollback', empty, 0, '', 'unknown package operation')
			}
			observed_plan_scope(arch + ' offline cached', offline, config, directory, false, 'install', app, 3, '2.0.0', '')
			blocked := Config{...config, policy: Policy{permissions: [], reserve_bytes: 0}}
			save_configuration(path, blocked)!
			observed_plan_scope(arch + ' service policy refusal', service, blocked, directory, false, 'install', app, 0, '', 'permissions blocked')
			observed_plan_scope(arch + ' explicit policy refusal', service, blocked, directory, true, 'repair', empty, 0, '', 'permissions blocked')
			revoked := Config{...config, repositories: []}; save_configuration(path, revoked)!
			for snapshot in [false, true]! {
				label := arch + if snapshot { ' explicit' } else { ' service' }
				observed_plan_scope(label + ' revoked remove', service, revoked, directory, snapshot, 'remove', app, 0, '', '')
				observed_plan_scope(label + ' revoked empty deploy', service, revoked, directory, snapshot, 'deploy', empty, 0, '', '')
			}
			save_configuration(path, config)!
			for suffix in ['catalog.json', 'trust-history.json', 'generations/2/state.json']! {
				file := directory + '/' + suffix; original := os.read_file(file)!
				os.write_file(file, '{broken metadata')!
				for snapshot in [false, true]! {
					observed_plan_scope(arch + suffix + if snapshot { ' explicit' } else { ' service' }, service, config, directory, snapshot, 'install', app, 0, '', 'metadata')
				}
				os.write_file(file, original)!; unsafe { file.free(); original.free() }
			}
			guard := acquire(directory)!; os.write_file(path, '{broken configuration')!
			for snapshot in [false, true]! {
				observed_plan_scope(arch + if snapshot { ' busy explicit' } else { ' busy service' }, service, config, directory, snapshot, 'install', app, 0, '', 'another package transaction')
			}
			guard.release()
			observed_plan_scope(arch + ' malformed configuration', service, config, directory, false, 'install', app, 0, '', 'invalid package configuration')
			save_configuration(path, config)!
			for i, file in paths { assert os.read_file(file)! == contents[i], file }
			assert os.readlink(directory + '/current')! == 'generations/2' && !os.exists(directory + '/generations/3')
			$if !plan_observation_baseline ? {
				mut owned_config := service.configuration()!
				mut names := ['app'.clone()]
				current := read_state(directory, arch)!
				mut prepared := prepare_operation_plan(owned_config, directory, current, 'install', names)!
				expected := json2.encode(prepared.plan)
				mut first := preview_plan(owned_config, directory, 'install', names)!
				mut second := service.plan('install', names)!
				assert first.packages[0].package.arguments.data != prepared.plan.packages[0].package.arguments.data
				assert first.packages[0].repository.str != owned_config.repositories[0].id.str
				prepared.close(); close_decoded_state(current); close_decoded_configuration(owned_config); unsafe { names.free() }
				one := json2.encode(first); assert one == expected
				retire_observed_plan(mut first)
				two := json2.encode(second); assert two == expected
				retire_observed_plan(mut second)
				unsafe { expected.free(); one.free(); two.free() }
			}
		}
	}
	$if !plan_observation_baseline ? { println('PLAN OBSERVATION complete service and explicit previews preserve independent manifests, exact JSON and signed state across 64 calls per case on both declarations PASS') }
}

fn test_plan_copies_preserve_every_manifest_field_and_retire_independently() {
	$if plan_observation_baseline ? { return }
	$if !plan_observation_baseline ? {
		for arch in ['aarch64', 'x86_64']! {
			mut packages := []Installed{cap: 33}; mut roots := []string{cap: 33}
			for i in 0 .. 33 {
				number := i.str(); id := 'item-' + number; unsafe { number.free() }
				roots << id.clone()
				p := Package{id: id, version: '1.2.3'.clone(), architecture: arch.clone(), name: 'Name é🚀'.clone(),
					description: 'wide description '.repeat(128), homepage: 'https://example.invalid/app'.clone(),
					license: 'Vendor-EULA'.clone(), proprietary: true, firmware: true, kind: 'linux'.clone(),
					runtime: 'runtime'.clone(), entrypoint: 'bin/run'.clone(), sdk: 1, window_protocol: 0,
					arguments: ['--literal'.clone(), 'argument with spaces'.clone()], permissions: ['files'.clone(), 'display'.clone()],
					associations: ['text/plain'.clone(), 'application/x-plan'.clone()],
					dependencies: [Dependency{id: 'runtime'.clone(), minimum: '1.0.0'.clone(), before: '3.0.0'.clone()}],
					files: [Payload{path: 'bin/run'.clone(), sha256: 'a'.repeat(64), bytes: 9876543210, executable: true}]}
				value := Installed{package: p, repository: 'publisher'.clone(), public_key: 'b'.repeat(64), sequence: 18446744073709551615}
				pointer := unsafe { &value }; unsafe { packages.push_many(pointer, 1) }
			}
			// This fixture explicitly owns all fields, like a decoded observation.
			mut source := Plan{requested: roots, packages: packages}
			mut first := owned_plan(source); mut second := owned_plan(source)
			assert first == source && second == source
			assert first.packages[0].package.id.str != source.packages[0].package.id.str
			assert first.packages[0].package.files[0].sha256.str != source.packages[0].package.files[0].sha256.str
			assert first.requested[0].str != source.requested[0].str
			for warmup in 0 .. 2 {
				if warmup == 1 { $if track_heap ? { C.vinix_heap_begin() } }
				for _ in 0 .. 1000 {
					mut copy := owned_plan(source)
					assert copy == source && copy.packages[32].package.files[0].bytes == 9876543210
					retire_observed_plan(mut copy)
				}
			}
			mut kept := u64(0); $if track_heap ? { kept = C.vinix_heap_end() }
			assert kept == 0
			println('PLAN OBSERVATION ' + arch + ' 1000 complete nested copies retained ' + kept.str() + ' tracked bytes')
			text := json2.encode(source); source.close(); first.close(); first.close()
			after := json2.encode(second); assert text == after
			assert second.packages[32].package.runtime == 'runtime' && second.packages[32].sequence == ~u64(0)
			second.close(); second.close(); unsafe { text.free(); after.free() }
		}
		println('PLAN OBSERVATION 33-package nested copies preserve every field, full-width numbers and independent retirement across 1000 cycles per architecture PASS')
	}
}
