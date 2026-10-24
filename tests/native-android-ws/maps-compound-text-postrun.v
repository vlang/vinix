// Reproduce the exact Maps271 postrun wrappers. Their pinned historical
// workflows remain required by the emitted tools; no generated results live here.
module main

import os

fn main() {
	verify := os.args.len == 3 && os.args[1] == '--verify'
	if !(os.args.len == 2 || verify) { eprintln('usage: maps-compound-text-postrun [--verify] OUTPUT_DIRECTORY'); exit(2) }
	output := os.args[os.args.len - 1]
	assert output != ''
	if !verify { os.mkdir_all(output)! }
	for name, source in templates() {
		path := output + '/' + name
		if verify {
			assert os.lstat(path)!.get_filetype() == .regular
			assert os.read_file(path)! == source, path
		} else {
			assert !os.exists(path) && !os.is_link(path), path
			os.write_file(path, source)!
		}
	}
	println('MAPS271 POSTRUN WRAPPER SOURCES VERIFIED/GENERATED; no VM or audit executed')
}

fn templates() map[string]string {
	return {
		'maps271-collect-record.v': "module main

import crypto.sha256
import json2
import os
import time

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn require_frames(frames []string) ! {
	required := ['application', 'paris-result', 'route-ready', 'route-ready-loaded', 'route-first', 'route-next']
	if frames.len < required.len { return error('all six Maps271 captures required, including route-ready-loaded') }
	mut seen := map[string]bool{}
	for name in frames {
		if name == '' || name != os.base(name) || name in ['.', '..'] || name in seen { return error('unique frame basenames required') }
		seen[name] = true
	}
	for name in required { if name !in seen { return error('missing required Maps271 capture: ' + name) } }
}

fn frame_gate_selftest() ! {
	complete := ['application', 'paris-result', 'route-ready', 'route-ready-loaded', 'route-first', 'route-next']
	require_frames(complete)!
	mut rejected := false
	require_frames(complete.filter(it != 'route-ready-loaded')) or { rejected = true }
	assert rejected, 'original five alone must fail'
	rejected = false
	require_frames([...complete, 'route-ready-loaded']) or { rejected = true }
	assert rejected, 'duplicate capture must fail'
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { frame_gate_selftest()!; println('MAPS271 SIX FRAME GATE SELFTEST PASS'); return }
	if os.args.len < 5 { eprintln('usage: maps271-collect-record ROOT PRELAUNCH_PIN FRAME...'); exit(2) }
	require_frames(os.args[3..])!
	base := 'build/android-maps/'
	root := os.args[1]
	checker := base + 'maps-compound-text-evidence'
	workflow := '/Users/alex/.local/state/vinix/android/maps271-checker-2026-10-24/'
	assert os.is_abs_path(root) && os.real_path(root) == root
	assert hash(root + '/prelaunch-sha256.json')! == os.args[2]
	assert !os.exists(root + '/audit') && !os.is_link(root + '/audit')
	assert !os.exists(base + 'maps271-collect-before.json') && !os.is_link(base + 'maps271-collect-before.json')
	assert hash(workflow + 'sha256.json')! == 'a070198737d63ae792c8e480a3f9fd64dd3d1eacbfcbb2a6c84c452f633ea149'
	assert hash(checker)! == hash(workflow + 'maps-compound-text-evidence')!
	assert hash('tests/native-android-ws/maps-compound-text-evidence.v')! == hash(workflow + 'maps-compound-text-evidence.v')!
	argv := [checker, 'collect', root, os.args[2], ...os.args[3..]]
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()),
		'checker_sha256': json2.Any(hash(checker)!), 'checker_source_sha256': json2.Any(hash('tests/native-android-ws/maps-compound-text-evidence.v')!),
		'recorder_source_sha256': json2.Any(hash(@FILE)!), 'recorder_binary_sha256': json2.Any(hash(os.executable())!)}
	os.write_file(base + 'maps271-collect-before.json', json2.encode(receipt, prettify: true) + '\\n')!
	r := os.exec(argv)
	os.write_file(base + 'maps271-collect.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	os.write_file(base + 'maps271-collect-result.json', json2.encode(receipt, prettify: true) + '\\n')!
	if r.exit_code == 0 {
		for name in ['maps271-collect-record.v', 'maps271-collect-before.json', 'maps271-collect-result.json', 'maps271-collect.log'] {
			assert !os.exists(root + '/audit/' + name) && !os.is_link(root + '/audit/' + name)
			os.cp(base + name, root + '/audit/' + name)!
			assert hash(base + name)! == hash(root + '/audit/' + name)!
		}
	}
	print(r.output)
	exit(r.exit_code)
}
"
		'maps271-extra-audit.v': "module main

import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/'
const checker_workflow = '/Users/alex/.local/state/vinix/android/maps271-checker-2026-10-24'
const helper_workflow = '/Users/alex/.local/state/vinix/android/maps271-workflow-2026-10-24'
const preparation_workflow = '/Users/alex/.local/state/vinix/android/maps271-preparation-2026-10-24'
const checker_pin = 'a070198737d63ae792c8e480a3f9fd64dd3d1eacbfcbb2a6c84c452f633ea149'
const helper_pin = '19c0d2d8f11411ebb9091ea32a185e791982c8c73f4a66e3f9a676749ab9aae1'
const preparation_pin = '93aa5aa48a5300a9ab1486431c40d39f2f260bfa75c3b67a7837b14ca4859226'
const preparation_entries = 9
const contract_workflow = '/Users/alex/.local/state/vinix/android/maps271-prelaunch-contract-2026-10-24'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }

fn walk(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { entries[key] = 'directory'; walk(root, key, mut entries)! }
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(path)! }
			else { return error('unexpected workflow artifact type: ' + path) }
		}
	}
}

fn verify(root string, pin string) !int {
	assert os.is_abs_path(root) && os.real_path(root) == root
	assert hash(root + '/sha256.json')! == pin
	manifest := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut expected := map[string]string{}
	for name, value in manifest {
		key := if value == 'directory' { name.trim_right('/') } else { name }
		assert key != '' && key != 'sha256.json' && key !in expected
		expected[key] = value
	}
	mut actual := map[string]string{}
	walk(root, '', mut actual)!
	actual.delete('sha256.json')
	assert actual.len == expected.len
	for name, value in expected { assert actual[name]! == value, name }
	return actual.len
}

fn clone(from string, to string) ! {
	assert !os.exists(to) && !os.is_link(to)
	r := os.exec(['cp', '-c', '-R', '-P', from, to])
	if r.exit_code != 0 { return error('workflow retention failed: ' + r.output) }
}

fn require_frames(frames []string) ! {
	required := ['application', 'paris-result', 'route-ready', 'route-ready-loaded', 'route-first', 'route-next']
	if frames.len < required.len { return error('all six Maps271 captures required, including route-ready-loaded') }
	mut seen := map[string]bool{}
	for name in frames {
		if name == '' || name != os.base(name) || name in ['.', '..'] || name in seen { return error('unique frame basenames required') }
		seen[name] = true
	}
	for name in required { if name !in seen { return error('missing required Maps271 capture: ' + name) } }
}

fn frame_gate_selftest() ! {
	complete := ['application', 'paris-result', 'route-ready', 'route-ready-loaded', 'route-first', 'route-next']
	require_frames(complete)!
	mut rejected := false
	require_frames(complete.filter(it != 'route-ready-loaded')) or { rejected = true }
	assert rejected, 'original five alone must fail'
	rejected = false
	require_frames([...complete, 'route-ready-loaded']) or { rejected = true }
	assert rejected, 'duplicate capture must fail'
}

fn retain(root string, requested_preparation_pin string, contract_pin string) ! {
	assert os.is_abs_path(root) && os.real_path(root) == root
	assert !root.starts_with(os.real_path(os.getwd()) + '/')
	assert os.is_dir(root + '/audit') && !os.exists(root + '/sha256.json') && !os.is_link(root + '/sha256.json')
	require_frames(json2.decode[[]string](os.read_file(root + '/audit/required-frames.json')!)!)!
	assert preparation_pin.len == 64 && preparation_entries > 0, 'final preparation pin/count required'
	assert requested_preparation_pin == preparation_pin
	assert verify(contract_workflow, contract_pin)! == 10
	output := root + '/audit/build-validation'
	assert !os.exists(output) && !os.is_link(output)
	assert verify(checker_workflow, checker_pin)! == 32
	assert verify(helper_workflow, helper_pin)! == 42
	assert verify(preparation_workflow, preparation_pin)! == preparation_entries
	os.mkdir_all(output)!
	clone(checker_workflow, output + '/checker-workflow')!
	clone(helper_workflow, output + '/replay-workflow')!
	clone(preparation_workflow, output + '/preparation-workflow')!
	clone(contract_workflow, output + '/prelaunch-contract-workflow')!
	assert verify(output + '/prelaunch-contract-workflow', contract_pin)! == 10
	assert verify(output + '/checker-workflow', checker_pin)! == 32
	assert verify(output + '/replay-workflow', helper_pin)! == 42
	assert verify(output + '/preparation-workflow', preparation_pin)! == preparation_entries
	for name in ['maps-compound-text-evidence', 'maps-compound-text-evidence.v'] {
		assert hash(root + '/audit/' + name)! == hash(output + '/checker-workflow/' + name)!
	}
	for suffix in ['before.json', 'receipt.json', 'selftest.log', 'assertion.log', 'prod-guard.log'] {
		assert hash(root + '/audit/checker-' + suffix)! == hash(output + '/checker-workflow/maps271-checker-' + suffix)!
	}
	for source, retained in {'maps-styled-replay.v': 'tests/native-android-ws/maps-styled-replay.v',
		'maps-styled-replay271': base + 'maps-styled-replay271'} {
		assert hash(output + '/replay-workflow/' + source)! == hash(root + '/prelaunch/replica/' + os.abs_path(retained).trim_left('/'))!
	}
	before := object(output + '/checker-workflow/maps271-checker-before.json')!
	assert before['recorder_source_sha256']!.str() == hash(output + '/checker-workflow/maps271-checker-record.v')!
	preparation := output + '/preparation-workflow/'
	prepare_before := object(preparation + 'prepare-before.json')!
	prepared := object(preparation + 'prepare-completed.json')!
	for key, value in prepare_before { assert json2.encode(prepared[key]!) == json2.encode(value), key }
	assert prepared['exit_code']!.int() == 0
	assert prepared['completed_utc']!.str() >= prepare_before['recorded_before_launch_utc']!.str()
	assert prepared['prelaunch_pin']!.str() == hash(root + '/prelaunch-sha256.json')!
	assert prepared['scope']!.str() == 'prepare only; Maps271 VM not launched; compound270 fixed quick smoke PASS authorizes preparation; root launch remains full-pair gated'
	assert prepared['argv']!.as_array().map(it.str()) == [base + 'maps-styled-replay271', 'prepare', '/Users/alex/.local/state/vinix/android/maps256-2026-10-24', base + 'maps257/vm', root]
	prepare_hashes := prepared['sha256']!.as_map()
	assert prepare_hashes.len == 2
	assert prepare_hashes[base + 'maps-styled-replay271']!.str() == hash(output + '/replay-workflow/maps-styled-replay271')!
	assert prepare_hashes['tests/native-android-ws/maps-styled-replay.v']!.str() == hash(output + '/replay-workflow/maps-styled-replay.v')!
	assert os.read_file(preparation + 'prepare.log')!.contains('MAPS271 PREPARED external=' + root + ' prelaunch_pin=' + prepared['prelaunch_pin']!.str())
	check_before := object(preparation + 'full-check-before.json')!
	check_done := object(preparation + 'full-check-receipt.json')!
	for key, value in check_before { assert json2.encode(check_done[key]!) == json2.encode(value), key }
	assert check_done['exit_code']!.int() == 0
	assert check_done['completed_utc']!.str() >= check_before['started_utc']!.str()
	assert check_done['prelaunch_pin']!.str() == hash(root + '/prelaunch-sha256.json')!
	assert check_done['checker_binary_sha256']!.str() == hash(output + '/replay-workflow/maps-styled-replay271')!
	assert check_done['checker_workflow_pin']!.str() == helper_pin
	assert check_done['argv']!.as_array().map(it.str()) == [helper_workflow + '/maps-styled-replay271', 'check', root, check_done['prelaunch_pin']!.str()]
	assert check_done['scope']!.str() == 'independent full retained prelaunch inventory/media rehash; no VM launch or media mutation'
	assert check_done['inventory_entries']!.int() == 3672
	assert os.read_file(preparation + 'full-check.log')!.trim_space() == 'MAPS271 PRELAUNCH CHECK PASS entries=3672'
	handoff := object(preparation + 'handoff.json')!
	assert !handoff['owner_launched_vm']!.bool() && handoff['prelaunch_root']!.str() == root
	assert handoff['prelaunch_pin']!.str() == check_done['prelaunch_pin']!.str() && handoff['prelaunch_entries']!.int() == 3672
	assert handoff['workflow_root']!.str() == helper_workflow && handoff['workflow_pin']!.str() == helper_pin
	assert handoff['independent_full_prelaunch_check']!.str() == 'PASS'
	assert handoff['source_contract_bundle']!.str() == contract_workflow && handoff['source_contract_bundle_pin']!.str() == contract_pin
	contract := output + '/prelaunch-contract-workflow/'
	assert hash(contract + 'maps-compound-text-evidence')! == hash(root + '/audit/maps-compound-text-evidence')!
	assert hash(contract + 'maps-compound-text-evidence.v')! == hash(root + '/audit/maps-compound-text-evidence.v')!
	assert hash(contract + 'maps271-prelaunch-contract-record.v')! == hash(base + 'maps271-prelaunch-contract-record.v')!
	for label in ['wrong-pin', 'contract'] {
		prior := object(contract + label + '-before.json')!
		done := object(contract + label + '-receipt.json')!
		for key, value in prior { assert json2.encode(done[key]!) == json2.encode(value), key }
		assert done['completed_utc']!.str() >= prior['started_utc']!.str()
		assert done['prelaunch_root']!.str() == root && done['prelaunch_pin']!.str() == hash(root + '/prelaunch-sha256.json')!
		assert done['checker_workflow_manifest_sha256']!.str() == checker_pin && done['checker_workflow_entries']!.int() == 32
		assert done['checker_sha256']!.str() == hash(root + '/audit/maps-compound-text-evidence')!
		assert done['checker_source_sha256']!.str() == hash(root + '/audit/maps-compound-text-evidence.v')!
		assert done['recorder_source_sha256']!.str() == hash(contract + 'maps271-prelaunch-contract-record.v')!
		assert done['log_sha256']!.str() == hash(contract + label + '.log')! && !done['maps_vm_launched']!.bool()
		assert done['expected_success']!.bool() == (label == 'contract')
		if label == 'contract' { assert done['exit_code']!.int() == 0 } else { assert done['exit_code']!.int() != 0 }
		argv := done['argv']!.as_array().map(it.str())
		assert argv.len == 4 && argv[..3] == [base + 'maps-compound-text-evidence', 'prelaunch-contract', root]
		if label == 'contract' { assert argv[3] == done['prelaunch_pin']!.str() } else { assert argv[3] != done['prelaunch_pin']!.str() }
	}
	for name in ['maps271-extra-audit.v', 'maps271-extra-audit-selftest.log', 'prepare271-postrun-tools.v', 'maps271-seal-record.v', 'maps271-final-validation.v', 'maps271-prelaunch-contract-record.v'] {
		assert os.lstat(base + name)!.get_filetype() == .regular
		os.cp(base + name, output + '/' + name)!
		assert hash(base + name)! == hash(output + '/' + name)!
	}
	os.write_file(output + '/copied-after-run.json', json2.encode({'completed_utc': time.utc().str(),
		'recorder_source_sha256': hash(@FILE)!, 'recorder_binary_sha256': hash(os.executable())!,
		'checker_workflow': checker_workflow, 'checker_manifest_sha256': checker_pin,
		'replay_workflow': helper_workflow, 'replay_manifest_sha256': helper_pin,
		'preparation_workflow': preparation_workflow, 'preparation_manifest_sha256': preparation_pin,
		'prelaunch_contract_workflow': contract_workflow, 'prelaunch_contract_manifest_sha256': contract_pin,
		'scope': 'Complete immutable tool workflows; no mutable launch helper is used as provenance'}, prettify: true) + '\\n')!
	println('MAPS271 EXTRA AUDIT PASS complete checker=32 replay=42 preparation=' + preparation_entries.str() + ' contract=10')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		frame_gate_selftest()!
		assert verify(checker_workflow, checker_pin)! == 32
		assert verify(helper_workflow, helper_pin)! == 42
		println('MAPS271 EXTRA AUDIT SELFTEST PASS complete checker=32 replay=42; directory and symlink entries preserved')
		return
	}
	if os.args.len != 4 || os.args[2].len != 64 || os.args[3].len != 64 { eprintln('usage: maps271-extra-audit COLLECTED_ROOT PREPARATION_PIN CONTRACT_PIN'); exit(2) }
	retain(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}
"
		'maps271-seal-record.v': "module main
import crypto.sha256
import json2
import os
import time

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	if os.args.len != 2 || os.args[1].len != 64 { eprintln('usage: maps271-seal-record PRELAUNCH_PIN'); exit(2) }
	base := 'build/android-maps/'
	root := '/Users/alex/.local/state/vinix/android/maps271-prelaunch-2026-10-24'
	assert !os.exists(root + '/sha256.json') && !os.is_link(root + '/sha256.json')
	assert !os.exists(base + 'maps271-seal-before.json') && !os.is_link(base + 'maps271-seal-before.json')
	checker := base + 'maps-compound-text-evidence'
	argv := [checker, 'seal', root, os.args[1]]
	assert hash(root + '/prelaunch-sha256.json')! == os.args[1]
	assert hash(checker)! == hash(root + '/audit/maps-compound-text-evidence')!
	assert hash('tests/native-android-ws/maps-compound-text-evidence.v')! == hash(root + '/audit/maps-compound-text-evidence.v')!
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()),
		'checker_sha256': json2.Any(hash(checker)!), 'checker_source_sha256': json2.Any(hash('tests/native-android-ws/maps-compound-text-evidence.v')!)}
	os.write_file(base + 'maps271-seal-before.json', json2.encode(receipt, prettify: true) + '\\n')!
	assert hash(@FILE)! == hash(root + '/audit/build-validation/maps271-seal-record.v')!
	assert !os.exists(root + '/audit/build-validation/maps271-seal-before.json') && !os.is_link(root + '/audit/build-validation/maps271-seal-before.json')
	os.cp(base + 'maps271-seal-before.json', root + '/audit/build-validation/maps271-seal-before.json')!
	r := os.exec(argv)
	os.write_file(base + 'maps271-seal.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	os.write_file(base + 'maps271-seal-result.json', json2.encode(receipt, prettify: true) + '\\n')!
	print(r.output)
	exit(r.exit_code)
}
"
		'maps271-final-validation.v': "module main

import crypto.sha256
import json2
import os
import time

const base = 'build/android-maps/'
const root = '/Users/alex/.local/state/vinix/android/maps271-prelaunch-2026-10-24'
const output = '/Users/alex/.local/state/vinix/android/maps271-validation-2026-10-24'
const checker = base + 'maps-compound-text-evidence'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\\n')! }

fn run(label string, argv []string) !string {
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()),
		'checker_sha256': json2.Any(hash(checker)!), 'checker_source_sha256': json2.Any(hash('tests/native-android-ws/maps-compound-text-evidence.v')!)}
	write(output + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	os.write_file(output + '/' + label + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = json2.Any(r.exit_code)
	write(output + '/' + label + '-receipt.json', receipt)!
	if r.exit_code != 0 { return error(label + ' failed: ' + r.output) }
	return r.output
}

fn walk(directory string, relative string, mut entries map[string]string) ! {
	for name in os.ls(directory + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := directory + '/' + key
		match os.lstat(path)!.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory { entries[key] = 'directory'; walk(directory, key, mut entries)! }
			else { return error('unexpected validation artifact type: ' + path) }
		}
	}
}

fn validate() ! {
	if os.exists(output) || os.is_link(output) { return error('fresh validation destination required') }
	assert hash(checker)! == hash(root + '/audit/maps-compound-text-evidence')!
	assert hash('tests/native-android-ws/maps-compound-text-evidence.v')! == hash(root + '/audit/maps-compound-text-evidence.v')!
	pin := hash(root + '/sha256.json')!
	os.mkdir_all(output)!
	os.cp(@FILE, output + '/maps271-final-validation.v')!
	os.cp(base + 'maps271-seal.log', output + '/seal.log')!
	for name in ['maps271-seal-record.v', 'maps271-seal-before.json', 'maps271-seal-result.json'] {
		os.cp(base + name, output + '/' + name)!
	}
	seal_before := json2.decode[map[string]json2.Any](os.read_file(output + '/maps271-seal-before.json')!)!
	seal_done := json2.decode[map[string]json2.Any](os.read_file(output + '/maps271-seal-result.json')!)!
	assert seal_done['exit_code']!.int() == 0
	for key, value in seal_before { assert json2.encode(seal_done[key]!) == json2.encode(value), key }
	assert seal_before['checker_sha256']!.str() == hash(checker)!
	assert seal_before['checker_source_sha256']!.str() == hash('tests/native-android-ws/maps-compound-text-evidence.v')!
	for name in ['maps271-seal-record.v', 'maps271-seal-before.json'] {
		assert hash(output + '/' + name)! == hash(root + '/audit/build-validation/' + name)!
	}
	print(run('check', [checker, 'check', root, pin])!)
	negative := run('negative', [checker, 'negative', root, pin])!
	print(negative)
	fixture := negative.all_after('logs=').trim_space()
	assert fixture.starts_with(os.temp_dir() + '/maps271-partial-')
	r := os.exec(['cp', '-c', '-R', '-P', fixture, output + '/partial-fixture'])
	if r.exit_code != 0 { return error('negative fixture retention failed: ' + r.output) }
	for label in ['wrong-pin', 'partial'] { os.cp(fixture + '-' + label + '.log', output + '/' + label + '.log')! }
	write(output + '/scope.json', {'completed_inventory_sha256': pin, 'complete_bundle': root,
		'negative_fixture_source': fixture, 'source_revision': os.exec(['git', 'rev-parse', 'HEAD']).output.trim_space()})!
	mut entries := map[string]string{}
	walk(output, '', mut entries)!
	write(output + '/sha256.json', entries)!
	println('MAPS271 FINAL VALIDATION PASS final_pin=' + pin + ' validation_pin=' + hash(output + '/sha256.json')! + ' entries=' + entries.len.str())
}

fn main() { validate() or { eprintln(err); exit(1) } }
"
	}
}
