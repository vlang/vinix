// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn preference_package(id string, version string, architecture string, dependencies []Dependency) Installed {
	return Installed{ package: Package{ id: id, name: id, version: version, architecture: architecture,
		kind: 'data', license: 'MIT', dependencies: dependencies }, repository: 'fixture', public_key: 'a'.repeat(64), sequence: 2 }
}

fn preference_config(architecture string) Config {
	return Config{ architecture: architecture, repositories: [Repository{ id: 'fixture', url: 'https://example.invalid', public_key: 'a'.repeat(64) }] }
}

fn test_install_can_replace_a_preferred_version_without_retrying_unrelated_installed_choices() {
	for architecture in ['aarch64', 'x86_64']! {
		base := preference_package('base', '1.0.0', architecture, [])
		new_base := preference_package('base', '2.0.0', architecture, [])
		addon := preference_package('zz-addon', '1.0.0', architecture, [Dependency{id: 'base', minimum: '2.0.0'}])
		mut installed := [base]
		mut requested := ['base']
		for i in 0 .. 20 {
			id := 'node-' + i.str()
			installed << preference_package(id, '1.0.0', architecture, [])
			requested << id
		}
		current := State{ architecture: architecture, packages: installed, requested: requested }
		catalog := Catalog{ packages: [...installed, new_base, addon] }
		roots := desired_roots(current, 'install', ['zz-addon'])!
		plan := resolve(catalog, preference_config(architecture), current, roots, false)!
		assert plan.packages.len == 22 && plan.requested.len == 22
		assert plan.packages.filter(it.package.id == 'base')[0].package.version == '2.0.0'
		assert plan.packages.filter(it.package.id.starts_with('node-')).all(it.package.version == '1.0.0')
		unsafe { (&array(&roots)).free(); (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
	}
}

fn test_unrelated_missing_requirement_keeps_its_cause_with_many_preferred_installed_packages() {
	for architecture in ['aarch64', 'x86_64']! {
		mut installed := []Installed{cap: 20}
		mut roots := []string{cap: 21}
		for i in 0 .. 20 {
			id := 'node-' + i.str()
			installed << preference_package(id, '1.0.0', architecture, [])
			roots << id
		}
		roots << 'zz-missing'
		if _ := resolve(Catalog{packages: installed}, preference_config(architecture), State{packages: installed}, roots, false) { assert false } else {
			message := err.msg()
			assert message.contains('zz-missing') && !message.contains('search limit'), message
			assert message.contains('Dependency path: zz-missing'), message
			unsafe { message.free(); err.free() }
		}
	}
}

fn test_preference_rotates_one_exact_authenticated_variant_and_preserves_fallback_order() {
	for architecture in ['aarch64', 'x86_64']! {
		old := preference_package('app', '1.0.0', architecture, [])
		middle := preference_package('app', '2.0.0', architecture, [])
		newer := preference_package('app', '3.0.0', architecture, [])
		all := Installed{ ...middle, package: Package{ ...middle.package, architecture: 'all' } }
		original := [newer, middle, all, old]
		for previous in [Installed{ ...old, sequence: 1 },
			Installed{ ...old, public_key: 'b'.repeat(64) }, Installed{ ...old, repository: 'other' },
			Installed{ ...old, package: Package{ ...old.package, description: 'different metadata' } }] {
			mut candidates := original.clone()
			prefer_installed(mut candidates, State{packages: [previous]})
			assert candidates.len == original.len
			if previous.public_key == old.public_key && previous.repository == old.repository && previous.package == old.package {
				assert candidates == [old, newer, middle, all]
				assert candidates[0].sequence == 2
			} else { assert candidates == original }
			unsafe { (&array(&candidates)).free() }
		}
		// An installed all variant can remain preferred over an equal host
		// version; ordinary fallback still follows host-before-all ordering.
		mut candidates := original.clone()
		prefer_installed(mut candidates, State{packages: [all]})
		assert candidates == [all, newer, middle, old]
		unsafe { (&array(&candidates)).free() }
		config := preference_config(architecture)
		catalog := Catalog{packages: original}
		current := State{packages: [old]}
		for upgrade in [false, true]! {
			plan := resolve(catalog, config, current, ['app'], upgrade)!
			assert plan.packages[0].package.version == if upgrade { '3.0.0' } else { '1.0.0' }
			unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
		}
		pinned := Config{ ...config, policy: Policy{pins: [Dependency{id: 'app', minimum: '2.0.0'}]} }
		plan := resolve(catalog, pinned, current, ['app'], false)!
		assert plan.packages[0].package.version == '3.0.0'
		unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
		assert catalog.packages == original && current.packages[0] == old
	}
}

fn test_preference_handles_maximum_catalog_and_installed_closure_without_duplicating_candidates() {
	mut installed := []Installed{cap: 4096}
	mut candidates := []Installed{cap: 32768}
	for i in 0 .. 4096 {
		id := 'node-' + i.str()
		for version in 1 .. 9 {
			candidate := preference_package(id, version.str() + '.0.0', 'aarch64', [])
			candidates << candidate
			if version == 1 { installed << candidate }
		}
	}
	candidates.sort_with_compare(candidate_order)
	prefer_installed(mut candidates, State{packages: installed})
	assert candidates.len == 32768
	for group in 0 .. 4096 {
		first := group * 8
		assert candidates[first].package.version == '1.0.0'
		for offset in 1 .. 8 {
			assert candidates[first + offset].package.id == candidates[first].package.id
			assert candidates[first + offset].package.version == (9 - offset).str() + '.0.0'
		}
	}
	unsafe { (&array(&candidates)).free() }
	println('Resolver preference: 32768 catalog variants and 4096 installed identities retain one choice each and stable fallback order PASS')
}

fn test_public_install_preference_retires_scratch_and_preserves_borrowed_catalog_and_state() {
	$if track_heap ? {
		config := preference_config('aarch64')
		mut installed := []Installed{cap: 64}
		mut candidates := []Installed{cap: 192}
		mut roots := []string{cap: 64}
		for i in 0 .. 64 {
			id := 'node-' + i.str()
			roots << id
			for version in 1 .. 4 {
				candidate := preference_package(id, version.str() + '.0.0', 'aarch64', [])
				candidates << candidate
				if version == 1 { installed << candidate }
			}
		}
		catalog := Catalog{packages: candidates}
		current := State{packages: installed}
		missing := [...roots, 'zz-missing']
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				plan := resolve(catalog, config, current, roots, false)!
				assert plan.packages.len == 64 && plan.packages.all(it.package.version == '1.0.0')
				unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
				// Single-variant refusal avoids exponential *real* alternatives;
				// successful multi-version resolution exercises in-place rotation.
				if _ := resolve(Catalog{packages: installed}, config, current, missing, false) { assert false } else {
					message := err.msg()
					assert message.contains('zz-missing') && !message.contains('search limit'), message
					unsafe { message.free(); err.free() }
				}
			}
		}
		kept := C.vinix_heap_end()
		assert kept == 0, 'public install preference retained ${kept} bytes'
		assert catalog.packages.len == 192 && catalog.packages[0] == installed[0] && current.packages == installed
		println('Resolver preference: 1000 public successful multi-version installs and missing-requirement refusals retain zero tracked bytes PASS')
	}
}
