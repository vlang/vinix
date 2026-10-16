// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256
import json2
import os

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn launch_owned_fixture(architecture string, kind string, width int) (Config, State) {
	key := 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
	mut packages := []Installed{cap: width + 2}
	mut dependencies := []Dependency{cap: width + 1}
	if kind != 'native' {
		dependencies << Dependency{ id: 'runtime' }
		packages << Installed{ repository: 'publisher', public_key: key, sequence: 8,
			package: Package{ id: 'runtime', version: '2.1.0', architecture: architecture, name: 'Runtime', kind: 'runtime', license: 'MIT',
				dependencies: if width > 0 { [Dependency{ id: 'asset-0' }] } else { []Dependency{} },
				files: [Payload{ path: 'bin/runner', sha256: key, bytes: 1, executable: true }] } }
	}
	for i in 0 .. width {
		number := i.str(); defer { unsafe { number.free() } }
		id := 'asset-' + number
		dependencies << Dependency{ id: id }
		packages << Installed{ repository: 'publisher', public_key: key, sequence: 9,
			package: Package{ id: id, version: '1.0.0', architecture: 'all', name: 'Assets', kind: 'data', license: 'MIT',
				// Shared edges and a cycle must visit each member once.
				dependencies: [Dependency{ id: if i == 0 { 'app' } else { 'asset-0' } }],
				files: [Payload{ path: 'data', sha256: key, bytes: 1 }] } }
	}
	packages << Installed{ repository: 'publisher', public_key: key, sequence: 7,
		package: Package{ id: 'app', version: '1.2.3', architecture: architecture, name: 'App', license: 'MIT', kind: kind,
			runtime: if kind == 'native' { '' } else { 'runtime' }, entrypoint: 'bin/runner', dependencies: dependencies,
			window_protocol: if kind == 'native' { 1 } else { 0 }, permissions: ['files', 'display', 'audio', 'network', 'process'],
			arguments: ['@APP@/a', '@DATA@/b', '@RUNTIME@/c', '@APP@:@DATA@:@RUNTIME@', '', '$(literal)'],
			files: [Payload{ path: 'bin/runner', sha256: key, bytes: 1, executable: true }] } }
	return Config{ architecture: architecture, launch_user: 'alex', repositories: [Repository{ id: 'publisher', url: 'https://example.invalid', public_key: key }] },
		State{ generation: 42, architecture: architecture, requested: ['app'], packages: packages }
}

fn test_plan_wire_compatibility() {
	os.setenv('DISPLAY', ':fixture-display', true)
	os.write_file('/tmp/launch-comparison', 'document')!
	defer { os.rm('/tmp/launch-comparison') or {} }
	for architecture in ['aarch64', 'x86_64']! {
		for kind in ['native', 'linux', 'windows', 'apple']! {
			config, state := launch_owned_fixture(architecture, kind, 16)
			for mode in 0 .. if kind == 'native' { 6 } else { 4 } {
				input := LaunchInput{ documents: ['/tmp/launch-comparison'], terminal: mode == 1 || mode == 3, command: mode == 2 || mode == 3,
					data_cwd: mode == 3, window: mode >= 4, arguments: if mode in [2, 3]! { ['', '--uid', '$(literal)', '@DATA@/literal'] } else { []string{} } }
				mut selected := state
				if mode == 5 {
					mut packages := state.packages.clone(); last := packages.len - 1
					packages[last] = Installed{ ...packages[last], package: Package{ ...packages[last].package, window_protocol: 2 } }
					selected = State{ ...state, packages: packages }
				}
				mut plan := application_launch_plan(config, '/var/lib/vinix-packages', selected, 'app', '/home/user/data', 1000, 1000, input)!
				encoded := json2.encode(plan)
				println('WIRE ' + architecture + ' ' + kind + ' ' + mode.str() + ' ' + sha256.sum(encoded.bytes()).hex())
				$if !plan_baseline ? { plan.close() }
			}
		}
	}
	for count in [0, 1, 64, 256]! {
		for mode in 0 .. 5 {
			input := LaunchInput{ documents: []string{len: count, init: '/home/user/é🚀 space; $literal'},
				arguments: if mode in [2, 3]! { ['', '--file', '$(literal)', '@APP@/literal'] } else { []string{} },
				terminal: mode == 1 || mode == 3, command: mode == 2 || mode == 3, data_cwd: mode == 3, window: mode == 4 }
			mut plan := launch_session_request(Config{ architecture: 'aarch64', launch_user: 'alex' }, '/usr/bin/vinix-package', 'app', input)!
			println('WIRE session ' + count.str() + ' ' + mode.str() + ' ' + sha256.sum(json2.encode(plan).bytes()).hex())
			$if !plan_baseline ? { plan.close() }
		}
	}
}

fn comparison_refusal(config Config, state State, data string, input LaunchInput) {
	if _ := application_launch_plan(config, '/var/lib/vinix-packages', state, 'app', data, 1000, 1000, input) { assert false }
	else { message := err.msg(); unsafe { message.free(); err.free() } }
}

fn test_matched_refusal_retention() {
	config, state := launch_owned_fixture('aarch64', 'linux', 16)
	mut revoked := state.packages.clone(); revoked[1] = Installed{ ...revoked[1], repository: 'revoked' }
	mut weak := state.packages.clone(); weak[1] = Installed{ ...weak[1], public_key: '0'.repeat(64) }
	mut denied := state.packages.clone(); last := denied.len - 1
	denied[last] = Installed{ ...denied[last], package: Package{ ...denied[last].package, permissions: [] } }
	os.write_file('/tmp/launch-comparison-denied', 'document')!
	defer { os.rm('/tmp/launch-comparison-denied') or {} }
	for i in 0 .. 8 {
		selected := if i == 0 { State{ ...state, packages: revoked } } else if i == 1 { State{ ...state, packages: weak } } else if i == 2 { State{ ...state, packages: denied } } else { state }
		policy := if i == 3 { Config{ ...config, policy: Policy{ allowed: ['app', 'runtime'] } } } else { config }
		data := if i == 4 { '/home/../data' } else { '/home/user/data' }
		path := if i == 2 { '/tmp/launch-comparison-denied' } else if i == 5 { '/tmp' } else if i == 6 { 'relative' } else { '/missing-launch-owned-file' }
		input := LaunchInput{ documents: if i in [0, 1, 3, 4]! { []string{} } else { [path] } }
		comparison_refusal(policy, selected, data, input)
		C.vinix_heap_begin()
		for _ in 0 .. 5 { comparison_refusal(policy, selected, data, input) }
		kept := C.vinix_heap_end()
		println('RETAIN refusal ' + i.str() + ' ' + kept.str())
		$if !plan_baseline ? { assert kept == 0 }
	}
}
