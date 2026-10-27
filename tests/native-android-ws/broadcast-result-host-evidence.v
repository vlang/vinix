// SPDX-License-Identifier: GPL-2.0-or-later
// Post-execution source/input capture; this does not reconstruct a historical build receipt.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const checks = state + '/broadcast-result-executable-checks-2026-10-27-r1'
const fixture = state + '/broadcast-result-fixture-2026-10-27-r1'
const baseline = state + '/combined-account-webview-credential-storage-framework-2026-10-27-r1'
const output = state + '/broadcast-result-host-evidence-plan-2026-10-27-r1'
const capture_build = state + '/broadcast-result-host-evidence-build-2026-10-27-r1'
const tested_revision = 'e82ca648198b9e412a5c4defb8e2724503abf01c'
const tools = repo + '/build/android-framework/tools'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const search_path = '@vlib|tests/native-android-tools|build-support|build-support/android'
const max_output_bytes = u64(32 * 1024 * 1024)
const reserve_bytes = u64(512 * 1024 * 1024)

struct FixtureBuild {
	argv []string
	source_revision string
	inputs_sha256 map[string]string
	apks_sha256 map[string]string
	pass_marker string
}

fn digest(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular { return error('regular input required: ' + path) }
	mut file := os.open(path)!
	defer { file.close() }
	mut sum := sha256.new()
	mut bytes := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut bytes) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		sum.write(bytes[..n])!
	}
	return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn json_pins(pins map[string]string) json2.Any {
	mut values := map[string]json2.Any{}
	for path, pin in pins { values[path] = json2.Any(pin) }
	return json2.Any(values)
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	mut names := os.ls(root + '/' + prefix)!
	names.sort()
	for name in names {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = digest(root + '/' + key)! }
			else { return error('nonregular bundle entry: ' + key) }
		}
	}
}

fn sealed(root string, pin string) ! {
	assert digest(root + '/sha256.json')! == pin, root
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	assert actual == expected, 'complete bundle inventory differs: ' + root
}

fn available() !u64 {
	r := os.exec(['/usr/bin/env', 'LC_ALL=C', '/bin/df', '-kP', state])
	assert r.exit_code == 0
	lines := r.output.trim_space().split_into_lines()
	assert lines.len == 2
	fields := lines[1].fields()
	assert fields.len >= 6
	return fields[3].u64() * 1024
}

fn guard(start u64) ! {
	now := available()!
	assert now >= reserve_bytes && (now >= start || start - now <= max_output_bytes), 'disk reserve/growth guard'
}

fn main() {
	assert os.args.len == 1, 'no arguments; captures only the pinned fresh evidence plan'
	os.chdir(repo)!
	assert !os.exists(output) && !os.is_link(output), 'fresh output required'
	start := available()!
	assert start >= reserve_bytes + max_output_bytes, '512 MiB reserve plus 32 MiB output allowance required'
	assert digest(compiler)! == compiler_pin
	sealed(baseline, 'cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691')!
	sealed(fixture, '93146d2bff516752ca62ea21cfb7bd532ced9abfe81345beb61e40a0b5d9b77d')!
	build := json2.decode[FixtureBuild](os.read_file(fixture + '/build.json')!)!
	assert build.source_revision == tested_revision
	assert build.pass_marker.ends_with(' credential-context broadcast-results')
	for path, pin in build.inputs_sha256 { assert digest(path)! == pin, path }
	for path, pin in build.apks_sha256 { assert digest(fixture + '/' + path)! == pin, path }
	assert build.apks_sha256['client/probe.apk'] == '44f6c4356a5d031cf68191476bb0d2fb0fc2ceec8ecea26ffd395024d19321e7'
	assert build.apks_sha256['disabled/probe.apk'] == '5293215a5899d2adb3ca9c6a52248c10874a2ad5b2e9cf08168935e829527966'
	assert digest(repo + '/build-support/android/nativews/bindings.txt')! == '60b590a07c627bd3ff8d57f1edaf5c0bd2e06c44124c7f808c6f5701f5bb3bbe'
	old_sources := state + '/broadcast-result-host-tools-2026-10-27-r1'
	corrected_sources := state + '/broadcast-result-initial-code-2026-10-27-r1'
	assert digest(old_sources + '/sha256.txt')! == '12ded9462ada61afc1a945fa955ac00fe5394772e65b6e889e818ff2a236b234'
	assert digest(corrected_sources + '/sha256.txt')! == 'e500ba05f9afdb666a0e1ac1cfcd530b5ccf758cafddd9361a39370860cfafcc'
	source_paths := ['tests/native-android-tools/check-broadcast-result.v', 'tests/native-android-tools/check-native-bindings.v',
		'tests/native-android-ws/combined-account-webview-build.v', 'tests/native-android-ws/service-query-fixture.v']
	mut relevant_sources := map[string]string{}
	mut relevant_paths := source_paths.clone()
	relevant_paths << ['tests/native-android-tools/androidtools/framework.v',
		'tests/native-android-tools/androidtools/framework_broadcast_result.v', 'tests/native-android-tools/androidtools/native_ws.v']
	for path in relevant_paths {
		corrected := os.base(path) in ['check-broadcast-result.v', 'framework_broadcast_result.v', 'service-query-fixture.v']
		snapshot := (if corrected { corrected_sources } else { old_sources }) + '/source/' + os.base(path)
		assert digest(repo + '/' + path)! == digest(snapshot)!, 'relevant source changed: ' + path
		relevant_sources[repo + '/' + path] = digest(snapshot)!
	}
	bin_names := ['check-broadcast-result', 'check-native-bindings', 'framework-builder', 'fixture-builder']
	bin_pins := ['4983ffd1df9c3b8698b529b87179c76977f7a51b9a89f88ec048df19a9d46d17',
		'cb01f8ec5b90ed4f83896cd4c443ba9a8ffb289da8ced211203ec26f0624b20e',
		'884edde7c60b43d7aba92f6fdb67effaba25705aa1f7b5d2dc9a86783ac4bb63',
		'2a47b8d0bdafcce4d3c76a90710c420ff3567ee52808f2c8beec9f3f9a1c324c']
	for i, name in bin_names { assert digest(checks + '/' + name)! == bin_pins[i], name }
	for name, marker in {
		'checker-run.log': 'ANDROID-BROADCAST-RESULT-ASSEMBLY-PASS four classes produce DEX; ART not executed'
		'bindings-run.log': 'NATIVE-BINDINGS-PASS entries=628 exports=629 spec_sha256=60b590a07c627bd3ff8d57f1edaf5c0bd2e06c44124c7f808c6f5701f5bb3bbe'
		'producer-selftest.log': 'COMBINED-FRAMEWORK-SELF-TEST-PASS'
		'fixture-run.log': 'SERVICE-QUERY-FIXTURE-SEAL 93146d2bff516752ca62ea21cfb7bd532ced9abfe81345beb61e40a0b5d9b77d'
	} { assert os.read_file(checks + '/' + name)!.contains(marker), name }
	mut host_pins := map[string]string{}
	inventory(checks, '', mut host_pins)!
	assert host_pins.len == 12, 'unexpected host evidence entry set'
	guard(start)!
	os.mkdir_all(output + '/commands')!
	mut source_union := map[string]string{}
	mut historical := []json2.Any{}
	mut observed := []json2.Any{}
	for i, path in source_paths {
		mut common := [compiler, '-new-compiler', '-gc', 'boehm', '-nocache', '-cc', 'cc']
		if i < 3 { common << ['-path', search_path] }
		mut listing_argv := common.clone()
		listing_argv << ['-print-v-files', path]
		r := os.exec(listing_argv)
		assert r.exit_code == 0, r.output
		assert r.output.len < 1024 * 1024, 'unexpected closure output size'
		os.write_file(output + '/commands/' + bin_names[i] + '.log', r.output)!
		mut closure := []string{}
		for line in r.output.split_into_lines() {
			if !line.trim_space().ends_with('.v') { continue }
			original := os.real_path(os.abs_path(line.trim_space()))
			closure << original
			source_union[original] = digest(original)!
		}
		assert repo + '/' + path in closure && closure.len > 1, path
		observed << json2.Any({'argv': json2.Any(listing_argv), 'exit_code': json2.Any(r.exit_code),
			'sources': json2.Any(closure), 'provenance': json2.Any('Observed post-execution; not proof of historical compiler inputs.')})
		mut build_argv := common.clone()
		build_argv << ['-o', checks + '/' + bin_names[i], path]
		run_argv := match i {
			0 { [checks + '/' + bin_names[i], baseline + '/smali', tools, os.real_path(java)] }
			1 { [checks + '/' + bin_names[i], baseline + '/smali'] }
			2 { [checks + '/' + bin_names[i], '--self-test'] }
			else { build.argv }
		}
		historical << json2.Any({'build_argv': json2.Any(build_argv), 'run_argv': json2.Any(run_argv),
			'timing_prefix': json2.Any(['/usr/bin/time', '-l']), 'cpu_limit_seconds': json2.Any(45),
			'zsh_file_limit_blocks': json2.Any(65536), 'zsh_file_limit_bytes': json2.Any(33554432),
			'run_JAVA_TOOL_OPTIONS': json2.Any(if i == 0 { '-Xmx256m -XX:ActiveProcessorCount=2' } else { 'unset' }),
			'provenance': json2.Any(if i == 3 { 'Build argv/limits reconstructed from session; run argv observed in sealed build.json. Inherited environment not captured.' }
				else { 'Build/run argv and limits reconstructed from session; not contemporaneous command receipts. Inherited environment not captured.' })})
		guard(start)!
	}
	source_union[repo + '/build-support/android/nativews/bindings.txt'] = digest(repo + '/build-support/android/nativews/bindings.txt')!
	source_union[os.real_path(@FILE)] = digest(os.real_path(@FILE))!
	for path, pin in relevant_sources { assert source_union[path] == pin, 'closure differs from retained source: ' + path }
	mut copied := u64(0)
	for path, pin in source_union {
		copied += os.file_size(path)
		assert copied < max_output_bytes - 2 * 1024 * 1024, 'source snapshot exceeds bounded allowance'
		guard(start)!
		target := output + '/source/' + path.trim_left('/')
		os.mkdir_all(os.dir(target))!
		os.cp(path, target)!
		assert digest(target)! == pin && digest(path)! == pin, path
	}
	assert os.is_dir(capture_build) && !os.is_link(capture_build)
	mut archive_roots := [output, checks, fixture, baseline, tools, compiler, old_sources, corrected_sources, capture_build]
	for path, _ in build.inputs_sha256 {
		if path.starts_with(tools + '/') || path.starts_with(checks + '/') || path.starts_with(repo + '/tests/') { continue }
		archive_roots << path
	}
	archive_roots = archive_roots.map(os.real_path(it))
	archive_roots.sort()
	mut roots := []string{}
	for path in archive_roots {
		assert os.exists(path) && !os.is_link(path), path
		if roots.any(path == it || path.starts_with(it + '/')) { continue }
		roots << path
	}
	os.write_file(output + '/roots.txt', roots.join('\n') + '\n')!
	revision := os.exec(['git', 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	write_json(output + '/plan.json', {
		'kind': json2.Any('broadcast-result-host-post-execution-evidence-plan'), 'captured_utc': json2.Any(time.utc().str()),
		'tested_source_revision': json2.Any(tested_revision), 'capture_source_revision': json2.Any(revision.output.trim_space()),
		'compiler': json2.Any(compiler), 'compiler_sha256': json2.Any(compiler_pin),
		'capture_executable_sha256': json2.Any(digest(os.real_path(os.executable()))!),
		'observed_post_execution_closures': json2.Any(observed), 'reconstructed_historical_commands': json2.Any(historical),
		'source_union_sha256': json_pins(source_union), 'host_evidence_sha256': json_pins(host_pins),
		'fixture_inputs_sha256': json_pins(build.inputs_sha256), 'archive_roots': json2.Any(roots),
		'baseline_inventory_sha256': json2.Any('cb07c656d6c63e9713926a0c2fac15f14060098baf8efb56d12fa7d1fd8c2691'),
		'fixture_inventory_sha256': json2.Any('93146d2bff516752ca62ea21cfb7bd532ced9abfe81345beb61e40a0b5d9b77d'),
		'output_limit_bytes': json2.Any(max_output_bytes), 'disk_reserve_bytes': json2.Any(reserve_bytes),
		'scope': json2.Any('Complete retained host checks, signed fixture, CE baseline and selected post-execution V closure/tool inputs for streaming archive. Not a hermetic SDK/C toolchain/runtime shared-library closure; no full successor framework, ART execution or Google login proof.')
	})!
	mut pins := map[string]string{}
	inventory(output, '', mut pins)!
	write_json(output + '/sha256.json', pins)!
	guard(start)!
	assert digest(compiler)! == compiler_pin
	for path, pin in source_union { assert digest(path)! == pin, 'source changed during capture: ' + path }
	println('BROADCAST-RESULT-HOST-EVIDENCE-PLAN-PASS ' + output + ' seal=' + digest(output + '/sha256.json')!)
}
