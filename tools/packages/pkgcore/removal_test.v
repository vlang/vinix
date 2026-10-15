// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn removal_fixture_package(id string, dependencies []Dependency) Installed {
	return Installed{ package: Package{id: id, name: id, version: '1.0.0', architecture: 'all',
		kind: 'data', license: 'MIT', dependencies: dependencies} }
}

fn test_implicit_dependency_removal_names_the_retained_requested_package() {
	state := State{ requested: ['app'], packages: [
		removal_fixture_package('app', [Dependency{id: 'bridge'}]),
		removal_fixture_package('bridge', [Dependency{id: 'shared'}]), removal_fixture_package('shared', [])] }
	if _ := desired_roots(state, 'remove', ['shared']) { assert false } else {
		message := err.msg()
		assert message.contains('shared is not explicitly installed') && message.contains('required by requested package app'), message
		unsafe { message.free(); err.free() }
	}
	assert state.requested == ['app'] && state.packages.len == 3
}

fn test_removal_blocker_follows_retained_roots_through_shared_cycles_and_batch_removals() {
	packages := [removal_fixture_package('alpha', [Dependency{id: 'bridge'}]),
		removal_fixture_package('beta', [Dependency{id: 'shared'}]),
		removal_fixture_package('bridge', [Dependency{id: 'alpha'}, Dependency{id: 'shared'}]),
		removal_fixture_package('shared', [Dependency{id: 'bridge'}])]
	for reverse in [false, true]! {
		state := State{ requested: ['shared', 'beta', 'alpha'], packages: if reverse { packages.reverse() } else { packages } }
		blocker := removal_blocker(state, ['shared'], '') or { panic('missing removal blocker') }
		assert blocker.id == 'shared' && blocker.root == 'beta'
		transitive := removal_blocker(state, ['shared', 'beta'], '') or { panic('missing transitive blocker') }
		assert transitive.id == 'shared' && transitive.root == 'alpha'
		if _ := removal_blocker(state, ['shared', 'alpha', 'beta'], '') { assert false }
		if _ := removal_blocker(state, ['unknown'], '') { assert false }
		if _ := removal_blocker(state, ['shared'], 'other') { assert false }
		roots := desired_roots(state, 'remove', ['alpha', 'beta', 'shared'])!
		assert roots.len == 0
		unsafe { (&array(&roots)).free() }
		assert state.requested == ['shared', 'beta', 'alpha'] && state.packages.len == 4
	}
}

fn test_implicit_batch_refusal_names_only_a_requested_package_that_would_remain() {
	state := State{ requested: ['alpha', 'beta'], packages: [
		removal_fixture_package('alpha', [Dependency{id: 'shared'}]),
		removal_fixture_package('beta', [Dependency{id: 'shared'}]), removal_fixture_package('shared', [])] }
	if _ := desired_roots(state, 'remove', ['alpha', 'shared']) { assert false } else {
		message := err.msg()
		assert message.contains('required by requested package beta') && !message.contains('package alpha'), message
		unsafe { message.free(); err.free() }
	}
	// Naming all dependents does not promote an implicit dependency into a
	// removable requested root. The existing explicit-root rule still applies.
	if _ := desired_roots(state, 'remove', ['alpha', 'beta', 'shared']) { assert false } else {
		message := err.msg()
		assert message.contains('not explicitly installed') && !message.contains('required by requested package'), message
		unsafe { message.free(); err.free() }
	}
}

fn test_removal_guidance_handles_deep_and_dense_graphs_with_bounded_messages() {
	mut packages := []Installed{cap: 4096}
	for i in 0 .. 4096 {
		id := 'node-' + i.str()
		dependencies := if i < 4095 { [Dependency{id: 'node-' + (i + 1).str()}] } else { []Dependency{} }
		packages << removal_fixture_package(id, dependencies)
	}
	state := State{requested: ['node-0'], packages: packages}
	if _ := desired_roots(state, 'remove', ['node-4095']) { assert false } else {
		message := err.msg()
		assert message.contains('node-4095 is not explicitly installed; required by requested package node-0') && message.len < 512
		unsafe { message.free(); err.free() }
	}
	mut dense := []Installed{cap: 512}
	for i in 0 .. 512 {
		mut dependencies := []Dependency{cap: 128}
		for offset in 1 .. 129 { dependencies << Dependency{id: 'node-' + ((i + offset) % 512).str()} }
		dense << removal_fixture_package('node-' + i.str(), dependencies)
	}
	blocker := removal_blocker(State{requested: ['node-0', 'node-511'], packages: dense}, ['node-511'], '') or { panic('missing dense blocker') }
	assert blocker.id == 'node-511' && blocker.root == 'node-0'
	println('Removal guidance: transitive/shared/cyclic and batched roots, chain-4096 and dense-512 retain an actual requested blocker PASS')
}

fn test_desired_root_buffers_retire_on_success_growth_and_refusal_without_changing_inputs() {
	$if track_heap ? {
		mut roots := []string{cap: 64}
		mut additions := []string{cap: 64}
		mut packages := [removal_fixture_package('shared', [])]
		for i in 0 .. 64 {
			id := 'root-' + i.str()
			roots << id; additions << 'extra-' + i.str()
			packages << removal_fixture_package(id, if i == 0 { [Dependency{id: 'shared'}] } else { []Dependency{} })
		}
		state := State{ requested: roots, packages: packages }
		explicit := State{requested: ['app', 'shared'], packages: [
			removal_fixture_package('app', [Dependency{id: 'shared'}]), removal_fixture_package('shared', [])]}
		config := Config{architecture: 'aarch64'}
		remove_app := ['app']
		remove := [roots[0]]
		implicit := ['shared']
		empty := []string{}
		operations := ['install', 'remove', 'upgrade', 'deploy']!
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				for operation in operations {
					names := if operation == 'remove' { remove } else if operation == 'upgrade' { empty } else { additions }
					result := desired_roots(state, operation, names)!
					assert result.len == match operation { 'install' {128} 'remove' {63} else {64} }
					unsafe { (&array(&result)).free() }
				}
				for operation in ['install', 'remove', 'upgrade', 'unknown']! {
					names := if operation == 'upgrade' { additions } else { empty }
					if _ := desired_roots(state, operation, names) { assert false } else {
						message := err.msg(); assert message != ''
						unsafe { message.free(); err.free() }
					}
				}
				if _ := desired_roots(state, 'remove', implicit) { assert false } else {
					message := err.msg(); assert message.contains('not explicitly installed')
					unsafe { message.free(); err.free() }
				}
				if _ := operation_plan(config, '', explicit, 'remove', implicit) { assert false } else {
					message := err.msg(); assert message.contains('cannot remove shared: still required by requested package app')
					unsafe { message.free(); err.free() }
				}
				plan := operation_plan(config, '', explicit, 'remove', remove_app)!
				assert plan.requested == implicit && plan.packages.len == 1
				unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
			}
		}
		kept := C.vinix_heap_end()
		assert kept == 0, 'root planning retained ${kept} bytes'
		assert state.requested == roots && roots[0] == 'root-0' && roots.last() == 'root-63' && additions.last() == 'extra-63'
		println('Removal guidance: 1000 root-planning install/remove/upgrade/deploy and removal-plan success/refusal cycles retain zero tracked bytes and preserve borrowed inputs PASS')
	}
}
