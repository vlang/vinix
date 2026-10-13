// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn search_fixture_package(id string, dependencies []Dependency) Package {
	return Package{ id: id, name: id, version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
		files: [Payload{path: 'data/value', sha256: '00'.repeat(32), bytes: 1}], dependencies: dependencies }
}

fn search_fixture_candidate(p Package) Installed {
	return Installed{package: p, repository: 'fixture', public_key: 'a'.repeat(64), sequence: 1}
}

fn search_fixture_config(architecture string) Config {
	return Config{architecture: architecture, repositories: [Repository{id: 'fixture', url: 'https://example.invalid', public_key: 'a'.repeat(64)}]}
}

fn test_resolution_search_budget_is_not_swallowed_by_backtracking() {
	mut search := Search{config: search_fixture_config('aarch64'), steps: 99999, candidates: [
		search_fixture_candidate(search_fixture_package('app', [Dependency{id: 'data'}])),
		search_fixture_candidate(search_fixture_package('data', [])),
	]}
	mut refused := false
	defer { unsafe { search.diagnostic.free() } }
	search.solve([Dependency{id: 'app'}]) or {
		refused = true
		assert err.msg().contains('search limit'), err.msg()
	}
	assert refused
}

fn test_deep_chain_and_dense_shared_cycles() {
	for dense in [false, true] {
		count := if dense { 512 } else { 4096 }
		mut names := []string{cap: count}
		for i in 0 .. count { names << 'node-' + i.str() }
		mut candidates := []Installed{cap: count}
		for i in 0 .. count {
			mut dependencies := []Dependency{}
			if dense {
				for offset in 1 .. 129 { dependencies << Dependency{id: names[(i + offset) % count]} }
			} else if i + 1 < count { dependencies << Dependency{id: names[i + 1]} }
			candidates << search_fixture_candidate(search_fixture_package(names[i], dependencies))
		}
		mut search := Search{config: search_fixture_config('aarch64'), candidates: candidates}
		result := search.solve([Dependency{id: names[0]}])!
		assert result.len == count
		assert search.steps < 100000
		unsafe { (&array(&result)).free(); search.diagnostic.free() }
	}
}

fn test_dense_graph_limit_and_closure_limits_are_explicit() {
	mut candidates := []Installed{cap: 4097}
	for i in 0 .. 4097 {
		dependencies := if i == 4096 { []Dependency{} } else { [Dependency{id: 'node-' + (i + 1).str()}] }
		candidates << search_fixture_candidate(search_fixture_package('node-' + i.str(), dependencies))
	}
	mut search := Search{config: search_fixture_config('aarch64'), candidates: candidates}
	if _ := search.solve([Dependency{id: 'node-0'}]) { assert false } else {
		assert err.msg().contains('4096-package limit'), err.msg()
		unsafe { err.free() }
	}
	unsafe { search.diagnostic.free() }
	mut wide := []Dependency{cap: 129}
	for i in 0 .. 129 { wide << Dependency{id: 'node-' + i.str()} }
	mut malformed := Search{config: search_fixture_config('aarch64'), candidates: [
		search_fixture_candidate(search_fixture_package('wide', wide)),
	]}
	if _ := malformed.solve([Dependency{id: 'wide'}]) { assert false } else {
		assert err.msg().contains('dependency limit'), err.msg()
		unsafe { err.free() }
	}
	unsafe { malformed.diagnostic.free() }
	config := search_fixture_config('aarch64')
	for oversized_catalog in [false, true] {
		catalog := Catalog{packages: if oversized_catalog { []Installed{len: 32769} } else { []Installed{} }}
		roots := if oversized_catalog { []string{} } else { []string{len: 4097, init: 'root'} }
		if _ := resolve(catalog, config, State{}, roots, true) { assert false } else {
			assert err.msg().contains('input limits'), err.msg()
			unsafe { err.free() }
		}
	}
}

fn test_backtracking_restores_branch_requirements_and_fixed_publisher_root() {
	old := search_fixture_package('app', [Dependency{id: 'good'}])
	new := Package{...old, version: '2.0.0', dependencies: [Dependency{id: 'bad'}]}
	mut search := Search{config: search_fixture_config('aarch64'), candidates: [
		search_fixture_candidate(new), search_fixture_candidate(old),
		search_fixture_candidate(search_fixture_package('good', [])),
		search_fixture_candidate(search_fixture_package('bad', [Dependency{id: 'missing'}])),
	]}
	result := search.solve([Dependency{id: 'app'}])!
	assert result.len == 2 && result[0].package.version == '1.0.0' && result[1].package.id == 'good'
	unsafe { (&array(&result)).free(); search.diagnostic.free() }
	search.diagnostic = ''
	// Publication of app 2.0.0 must fail even though the older app works.
	if _ := search.solve_fixed(new.dependencies, [0]) { assert false } else {
		assert err.msg().contains('missing'), err.msg()
		unsafe { err.free() }
	}
	unsafe { search.diagnostic.free() }
}

fn test_runtime_entrypoint_failure_backtracks_to_working_runtime() {
	runtime := Package{...search_fixture_package('runtime', []), architecture: 'aarch64', kind: 'runtime',
		files: [Payload{path: 'bin/run', sha256: '00'.repeat(32), bytes: 1, executable: true}]}
	broken := Package{...runtime, version: '2.0.0', files: [Payload{path: 'bin/other', sha256: '00'.repeat(32), bytes: 1, executable: true}]}
	app := Package{...search_fixture_package('app', [Dependency{id: 'runtime'}]), architecture: 'aarch64',
		kind: 'linux', runtime: 'runtime', entrypoint: 'bin/run'}
	mut search := Search{config: search_fixture_config('aarch64'), candidates: [
		search_fixture_candidate(app), search_fixture_candidate(broken), search_fixture_candidate(runtime),
	]}
	result := search.solve([Dependency{id: 'app'}])!
	assert result.len == 2 && result[1].package.version == '1.0.0'
	unsafe { (&array(&result)).free(); search.diagnostic.free() }
}

fn test_architecture_ties_and_installed_preference_are_deterministic() {
	all := search_fixture_candidate(search_fixture_package('data', []))
	for architecture in ['aarch64', 'x86_64'] {
		native := Installed{...all, package: Package{...all.package, architecture: architecture}}
		other := Installed{...all, package: Package{...all.package, architecture: if architecture == 'aarch64' { 'x86_64' } else { 'aarch64' }}}
		for reverse in [false, true] {
			catalog := Catalog{packages: if reverse { [native, other, all] } else { [all, other, native] }}
			config := search_fixture_config(architecture)
			for keep in [false, true] {
				plan := resolve(catalog, config, State{packages: [all]}, ['data'], !keep)!
				assert plan.packages.len == 1
				assert plan.packages[0].package.architecture == if keep { 'all' } else { architecture }
				unsafe { (&array(&plan.requested)).free(); (&array(&plan.packages)).free() }
			}
		}
	}
}

// A separate exhaustive oracle enumerates absent/old/new choices for four IDs.
// It checks reachability and constraints without making resolver decisions.
fn search_oracle_valid(candidates []Installed, choices [4]int, roots []Dependency) bool {
	mut reachable := [4]bool{}
	for root in roots {
		index := root.id[5] - `0`
		if choices[index] < 0 { return false }
		reachable[index] = true
	}
	for _ in 0 .. 4 {
		for id in 0 .. 4 {
			if !reachable[id] { continue }
			for dependency in candidates[choices[id]].package.dependencies {
				child := dependency.id[5] - `0`
				if choices[child] < 0 || !dependency.accepts(candidates[choices[child]].package) { return false }
				reachable[child] = true
			}
		}
	}
	for id in 0 .. 4 { if (choices[id] >= 0) != reachable[id] { return false } }
	return true
}

fn test_iterative_search_matches_exhaustive_small_graph_oracle() {
	mut random := u32(12345)
	for case in 0 .. 256 {
		mut candidates := []Installed{cap: 8}
		for id in 0 .. 4 {
			for version in 1 .. 3 {
				mut dependencies := []Dependency{}
				for child in 0 .. 4 {
					random = random * u32(1664525) + u32(1013904223)
					if random >> 28 < 6 {
						dependencies << Dependency{id: 'node-' + child.str(),
							minimum: if random & 1 == 0 { '2.0.0' } else { '' },
							before: if random & 3 == 3 { '2.0.0' } else { '' }}
					}
				}
				p := Package{...search_fixture_package('node-' + id.str(), dependencies), version: version.str() + '.0.0'}
				candidates << search_fixture_candidate(p)
			}
		}
		roots := if case % 2 == 0 { [Dependency{id: 'node-0'}] } else { [Dependency{id: 'node-0'}, Dependency{id: 'node-2'}] }
		mut expected := false
		for combination in 0 .. 81 {
			mut code := combination
			mut choices := [4]int{init: -1}
			for id in 0 .. 4 {
				value := code % 3; code /= 3
				if value > 0 { choices[id] = id * 2 + value - 1 }
			}
			if search_oracle_valid(candidates, choices, roots) { expected = true; break }
		}
		mut search := Search{config: search_fixture_config('aarch64'), candidates: candidates}
		mut actual := true
		result := search.solve(roots) or { actual = false; unsafe { err.free() }; []Installed{} }
		assert actual == expected, 'oracle disagreement in case ${case}'
		if actual {
			mut choices := [4]int{init: -1}
			for installed in result {
				id := int(installed.package.id[5] - `0`)
				choices[id] = id * 2 + int(installed.package.version[0] - `1`)
			}
			assert search_oracle_valid(candidates, choices, roots)
		}
		unsafe { (&array(&result)).free(); search.diagnostic.free() }
	}
}

fn test_version_comparison_preserves_numeric_boundaries_and_invalid_input() {
	versions := ['0.0.0', '0.0.1', '0.1.0', '1.0.0', '1.0.9', '1.0.10', '2.0.0', '999999999.999999999.999999999']
	for i, left in versions {
		for j, right in versions {
			assert compare_versions(left, right) == if i < j { -1 } else if i > j { 1 } else { 0 }
		}
	}
	for invalid in ['', '1', '1.2', '1.2.3.4', '.1.2', '1..2', '1.2.', '01.2.3', '1.00.3', '1.2.03',
		'1000000000.0.0', '1.2.-3', '1.2.3a', '1.2.٣'] {
		assert compare_versions(invalid, '1.2.3') == 0
		if _ := version_values(invalid) { assert false }
	}
}

fn test_search_work_buffers_retire_without_retained_allocations() {
	$if track_heap ? {
		mut candidates := []Installed{cap: 256}
		for i in 0 .. 256 {
			dependencies := if i == 255 { []Dependency{} } else { [Dependency{id: 'node-' + (i + 1).str(), minimum: '1.0.0', before: '3.0.0'}] }
			candidates << search_fixture_candidate(search_fixture_package('node-' + i.str(), dependencies))
		}
		config := search_fixture_config('aarch64')
		blocked := Config{...config, policy: Policy{allowed: ['another-app']}}
		roots := [Dependency{id: 'node-0'}]
		missing := [Dependency{id: 'absent'}]
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				mut search := Search{config: config, candidates: candidates}
				result := search.solve(roots)!
				assert result.len == 256
				unsafe { (&array(&result)).free(); search.diagnostic.free() }
				search.diagnostic = ''
				if _ := search.solve(missing) { assert false } else {
					message := err.msg()
					unsafe { message.free(); err.free() }
				}
				unsafe { search.diagnostic.free() }
				mut denied := Search{config: blocked, candidates: candidates}
				if _ := denied.solve(roots) { assert false } else {
					message := err.msg()
					assert message.contains('organization allowlist')
					unsafe { message.free(); err.free() }
				}
				unsafe { denied.diagnostic.free() }
			}
		}
		kept := C.vinix_heap_end()
		assert kept == 0, 'dependency search work buffers retained ${kept} bytes'
		println('Dependency search: 1000 successful 256-package chains and missing/policy refusals retain zero tracked bytes')
	}
}
