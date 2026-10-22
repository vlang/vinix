// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

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
			window_protocol: 0, permissions: ['files', 'audio', 'network', 'process'],
			arguments: ['@APP@/a', '@DATA@/b', '@RUNTIME@/c', '@APP@:@DATA@:@RUNTIME@', '', '$(literal)'],
			files: [Payload{ path: 'bin/runner', sha256: key, bytes: 1, executable: true }] } }
	return Config{ architecture: architecture, launch_user: 'alex', repositories: [Repository{ id: 'publisher', url: 'https://example.invalid', public_key: key }] },
		State{ generation: 42, architecture: architecture, requested: ['app'], packages: packages }
}

fn launch_owned_cycles() int { return $if track_heap ? { 1000 } $else { 32 } }

fn launch_owned_refusal(config Config, state State, data string, input LaunchInput, expected string) {
	if mut value := application_launch_plan(config, '/var/lib/vinix-packages', state, 'app', data, 1000, 1000, input) {
		value.close(); assert false
	} else { message := err.msg(); assert message == expected, message; unsafe { message.free(); err.free() } }
}

fn test_launch_plans_survive_source_state_and_sibling_retirement() {
	config, fixture := launch_owned_fixture('aarch64', 'linux', 16)
	text := json2.encode(fixture)
	mut state := decode_persistent_state(text, 'aarch64')!
	unsafe { text.free() }
	root := '/var/lib/vinix-packages'.clone()
	data := '/home/user/é🚀 data'.clone()
	id := 'app'.clone()
	executable := '/usr/bin/vinix-package'.clone()
	account := 'alex'.clone()
	mut input := command_launch(['--data-cwd', '--file', '/tmp/launch-owned', '--', '', '--uid', '$(literal)', '@APP@/literal'])!
	os.write_file('/tmp/launch-owned', 'document')!
	defer { os.rm('/tmp/launch-owned') or {} }
	mut first := command_launch_plan(config, root, state, id, data, 1000, 1000, input, false)!
	mut second := command_launch_plan(config, root, state, id, data, 1000, 1000, input, true)!
	mut session := launch_session_request(Config{ ...config, launch_user: account }, executable, id,
		LaunchInput{ command: true, data_cwd: true, arguments: input.arguments, documents: input.documents })!
	input.close(); state.close()
	unsafe { root.free(); data.free(); id.free(); executable.free(); account.free() }
	assert first.directory == '/home/user/é🚀 data'
	assert first.arguments.last() == '@APP@/literal' && '/tmp/launch-owned' in first.arguments
	first.close(); first.close()
	assert first.program == '' && first.directory == '' && first.arguments.len == 0
	assert second.arguments.last() == '@APP@/literal' && 'TERM=linux' in second.arguments
	assert session.arguments == ['run', '--isolated', 'alex', '/usr/bin/vinix-package', 'run-args', 'app',
		'--data-cwd', '--file', '/tmp/launch-owned', '--', '', '--uid', '$(literal)', '@APP@/literal']
	second.close(); second.close(); session.close(); session.close()
	assert session.program == '' && session.directory == '' && session.arguments.len == 0
	println('LAUNCH OWNERSHIP plans survive request/state/path/account and sibling retirement; repeated close resets all fields PASS')
}

fn test_launch_plan_matrix_retires_success_storage_and_keeps_inputs_literal() {
	os.write_file('/tmp/launch-owned-matrix', 'document')!
	defer { os.rm('/tmp/launch-owned-matrix') or {} }
	for architecture in ['aarch64', 'x86_64']! {
		for kind in ['native', 'linux', 'windows', 'apple']! {
			config, state := launch_owned_fixture(architecture, kind, 16)
			for mode in 0 .. if kind == 'native' { 6 } else { 4 } {
				input := LaunchInput{ terminal: mode == 1 || mode == 3, command: mode == 2 || mode == 3,
					data_cwd: mode == 3, window: mode >= 4, documents: ['/tmp/launch-owned-matrix'],
					arguments: if mode in [2, 3]! { ['', '--uid', '$(literal)', '@DATA@/literal'] } else { []string{} } }
				mut selected := state
				if mode >= 4 {
					mut packages := state.packages.clone()
					last := packages.len - 1
					packages[last] = Installed{ ...packages[last], package: Package{ ...packages[last].package, window_protocol: if mode == 5 { 2 } else { 1 }, permissions: [...packages[last].package.permissions, 'display'] } }
					selected = State{ ...state, packages: packages }
				}
				for _ in 0 .. 1 { mut warm := application_launch_plan(config, '/var/lib/vinix-packages', selected, 'app', '/home/user/data', 1000, 1000, input)!; warm.close() }
				$if track_heap ? { C.vinix_heap_begin() }
				for _ in 0 .. launch_owned_cycles() {
					mut plan := application_launch_plan(config, '/var/lib/vinix-packages', selected, 'app', '/home/user/data', 1000, 1000, input)!
					assert plan.program == '/usr/bin/vinix-sandbox'
					assert plan.directory == if input.data_cwd { '/home/user/data' } else { '/var/lib/vinix-packages/generations/42/apps/app' }
					assert plan.arguments[5] == if input.window { 'stdio rpath wpath cpath flock exec prot_exec inet dns proc' }
						else if input.terminal { 'stdio rpath wpath cpath flock exec prot_exec tty inet dns proc' }
						else { 'stdio rpath wpath cpath flock exec prot_exec inet dns proc' }
					assert ('TERM=linux' in plan.arguments) == input.terminal
					assert !plan.arguments.any(it.starts_with('DISPLAY=') || it.starts_with('XAUTHORITY='))
					assert plan.arguments.last() == if input.command { '@DATA@/literal' } else { '/tmp/launch-owned-matrix' }
					plan.close(); plan.close()
				}
				$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, architecture + ' ' + kind + ' mode ' + mode.str() + ' retained ' + kept.str() }
			}
		}
	}
	$if track_heap ? { println('LAUNCH OWNERSHIP 36 architecture/kind/mode cases: 1000 plan/close cycles each retained 0 bytes') }
	println('LAUNCH OWNERSHIP both architectures and native/Linux/Windows/Apple plans preserve promises, environment, templates and literal tails PASS')
}

fn test_launch_plan_dependency_and_document_growth_retires_storage() {
	os.write_file('/tmp/launch-owned-growth', 'document')!
	defer { os.rm('/tmp/launch-owned-growth') or {} }
	for width in [0, 1, 64]! {
		config, state := launch_owned_fixture('x86_64', 'native', width)
		documents := []string{len: if width == 64 { 256 } else { width }, init: '/tmp/launch-owned-growth'}
		input := LaunchInput{ documents: documents, command: true, arguments: []string{len: 256, init: 'literal'}, data_cwd: true }
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. launch_owned_cycles() {
			mut plan := application_launch_plan(config, '/var/lib/vinix-packages', state, 'app', '/home/user/data', 1000, 1000, input)!
			assert plan.arguments.last() == 'literal'; plan.close()
			closure := application_closure(state, 'app')
			assert closure.len == width + 1
			unsafe { (&array(&closure)).free() }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, 'growth retained ' + kept.str() }
	}
	println('LAUNCH OWNERSHIP 0/1/64 dependencies, shared edges/cycles, 256 documents and 256 literal arguments retire vector growth PASS')
}

fn test_launch_plan_refusals_retire_partial_plans() {
	config, state := launch_owned_fixture('aarch64', 'linux', 16)
	mut revoked_packages := state.packages.clone()
	revoked_packages[1] = Installed{ ...revoked_packages[1], repository: 'revoked' }
	mut weak_packages := state.packages.clone()
	weak_packages[1] = Installed{ ...weak_packages[1], public_key: '0'.repeat(64) }
	mut denied_packages := state.packages.clone()
	last := denied_packages.len - 1
	denied_packages[last] = Installed{ ...denied_packages[last], package: Package{ ...denied_packages[last].package, permissions: [] } }
	for case_index in 0 .. 8 {
		selected := if case_index == 0 { State{ ...state, packages: revoked_packages } } else if case_index == 1 { State{ ...state, packages: weak_packages } }
			else if case_index == 2 { State{ ...state, packages: denied_packages } } else { state }
		policy := if case_index == 3 { Config{ ...config, policy: Policy{ allowed: ['app', 'runtime'] } } } else { config }
		data := if case_index == 4 { '/home/../data' } else { '/home/user/data' }
		path := if case_index == 5 { '/tmp' } else if case_index == 6 { 'relative' } else { '/missing-launch-owned-file' }
		input := LaunchInput{ documents: if case_index <= 3 || case_index == 4 { []string{} } else { [path] } }
		// Permission refusal needs an existing regular file, after plan construction.
		os.write_file('/tmp/launch-owned-denied', 'document')!
		actual := if case_index == 2 { LaunchInput{ documents: ['/tmp/launch-owned-denied'] } } else { input }
		expected := match case_index {
			0 { 'asset-0: dependency publisher key has been revoked' }
			1 { 'invalid repository publisher key: expected a canonical non-identity Ed25519 point in the prime-order subgroup' }
			2 { 'app: file permission is not declared' }
			3 { 'asset-15: blocked by organization allowlist' }
			4 { 'invalid application context directories' }
			5 { 'document must be an existing absolute regular file: /tmp' }
			6 { 'document must be an existing absolute regular file' }
			else { 'document must be an existing absolute regular file: /missing-launch-owned-file' }
		}
		launch_owned_refusal(policy, selected, data, actual, expected)
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. launch_owned_cycles() { launch_owned_refusal(policy, selected, data, actual, expected) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, 'refusal ' + case_index.str() + ' retained ' + kept.str() }
		os.rm('/tmp/launch-owned-denied')!
	}
	println('LAUNCH OWNERSHIP policy, revoked/weak publishers, SDK directories and regular-file/permission refusals retire partial plans PASS')
}

fn test_isolated_session_plans_own_and_retire_every_mode() {
	for count in [0, 1, 64, 256]! {
		documents := []string{len: count, init: '/home/user/é🚀 space; $literal'}
		for mode in 0 .. 5 {
			config := Config{ architecture: 'aarch64', launch_user: 'alex' }
			input := LaunchInput{ documents: documents, arguments: if mode in [2, 3]! { ['', '--file', '$(literal)', '@APP@/literal'] } else { []string{} },
				terminal: mode == 1 || mode == 3, command: mode == 2 || mode == 3, data_cwd: mode == 3, window: mode == 4 }
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. launch_owned_cycles() {
				mut plan := launch_session_request(config, '/usr/bin/vinix-package', 'app', input)!
				assert plan.program == '/usr/sbin/vinix-session' && plan.directory == '/'
				assert plan.arguments[4] == ['run', 'run-terminal', 'run-args', 'run-terminal-args', 'run-window']![mode]
				plan.close(); plan.close()
			}
			$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, 'session retained ' + kept.str() }
		}
	}
	println('LAUNCH OWNERSHIP five isolated session modes and 0/1/64/256 documents release independent vectors PASS')
}
