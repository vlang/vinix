// SPDX-License-Identifier: GPL-2.0-or-later
// Exact production source delta for the browser deadline correction.
module main

import crypto.sha256
import json2
import mapsaccountstage as stage
import os

const repository = '/Users/alex/code/vinix'
const state_root = '/Users/alex/.local/state/vinix/android/'
const baseline = state_root + 'current-browser-build-2026-10-26-r2'
const baseline_seal = 'af2373af972966cc72b2b8eb8ba90d73063fad5d24a4a76b29ce8daff78062f3'
const inputs_pin = '6cc3fee04505ee9f88ce80ee5a55bae25aecb56929ea3bce4a6d385d6f2d710a'
const changed_path = repository + '/build-support/android/browserclient/client.c.v'
const before_pin = '4713f03a07aba207f335e68b4dea486290851134525851b8f19206b579088e35'
const after_pin = '3d40120b6b3c8c3fd60d54fed64977476d588f88b39665e2766a132507a74513'
const producer_pin = 'c7b9b343ed51904075500d121d0cfe0a532f8eb81ff28638cc74b53fa21b24f9'
const bootstrap_pin = 'd13e16230e758444e0d70619cd524e4e297cb61c17f8a9c2583e386c1bf38896'
const max_bytes = 8 * 1024 * 1024

fn bounded_read(path string) !string {
	before := os.lstat(path)!
	if os.real_path(path) != path || before.get_filetype() != .regular || before.size < 0 || before.size > max_bytes {
		return error('canonical bounded regular input required: ' + path)
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 64 * 1024}
	mut bytes := []u8{cap: int(before.size)}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		if bytes.len + n > max_bytes { return error('source exceeded read bound') }
		bytes << buffer[..n]
	}
	after := os.lstat(path)!
	if after.get_filetype() != .regular || os.real_path(path) != path || before.size != bytes.len || after.size != bytes.len {
		return error('input changed during bounded read')
	}
	return bytes.bytestr()
}

fn compare(before map[string]string, after map[string]string) ! {
	if before.len != 347 || after.len != 347 || !stage.valid_pin(after_pin) || after_pin == before_pin {
		return error('exact reviewed 347-input profile required')
	}
	mut production := 0
	for path, pin in before {
		if !stage.valid_pin(pin) || !os.is_abs_path(path) || os.norm_path(path) != path { return error('invalid original input') }
		if path.starts_with(repository + '/') { production++ }
		expected := if path == changed_path { after_pin } else { pin }
		if after[path] or { '' } != expected { return error('unexpected browser input delta: ' + path) }
	}
	if production != 18 || before[changed_path] or { '' } != before_pin { return error('exact deployed browser closure differs') }
}

fn snapshot(bundle stage.Bundle) !map[string]string {
	for path, pin in {'builder-source.v': producer_pin, 'bootstrap-builder': bootstrap_pin} {
		if bundle.files[path] or { '' } != pin { return error('browser producer identity differs: ' + path) }
	}
	inputs := json2.decode[map[string]string](bounded_read(bundle.root + '/current-inputs.json')!)!
	closure := json2.decode[map[string]string](bounded_read(bundle.root + '/browser-closure.json')!)!
	if inputs != closure || inputs.len != 347 { return error('exact frozen browser closure differs') }
	mut actual := map[string]string{}
	for path, pin in bundle.files {
		if path.starts_with('closure/browser/') { actual['/' + path.all_after('closure/browser/')] = pin }
	}
	mut expected := inputs.clone()
	expected['/Users/alex/code/v-tccbin-bootstrap-20261026/v'] = stage.compiler_seal
	if actual != expected { return error('retained browser source membership or hashes differ') }
	if json2.decode[map[string]string](json2.encode(bundle.receipt['runtime_dependencies_sha256']!))!.len != 0 {
		return error('deadline correction must retain the empty browser runtime dependency set')
	}
	return inputs
}

fn run(bundle_root string, seal string, output string) ! {
	if !output.starts_with(state_root) || os.norm_path(output) != output || os.real_path(os.dir(output)) != os.dir(output)
		|| os.exists(output) || os.is_link(output) || output.starts_with(baseline + '/')
		|| (bundle_root != '' && output.starts_with(bundle_root + '/')) {
		return error('fresh canonical external report required')
	}
	old := stage.load_bundle(baseline, baseline_seal)!
	if old.files['current-inputs.json'] or { '' } != inputs_pin { return error('baseline input map differs') }
	before := snapshot(old)!
	mut current := map[string]string{}
	for path in before.keys() { current[path] = sha256.sum(bounded_read(path)!.bytes()).hex() }
	compare(before, current)!
	if stage.hash(repository + '/tests/native-android-ws/build-current-launch.v')! != producer_pin {
		return error('live producer source differs from retained bootstrap')
	}
	mut new_seal := ''
	if bundle_root != '' {
		if !bundle_root.starts_with(state_root + 'current-browser-build-') || bundle_root == baseline {
			return error('fresh browser producer required')
		}
		new := stage.load_bundle(bundle_root, seal)!
		compare(before, snapshot(new)!)!
		for name in ['builder-closure.json', 'builder-source.v', 'baseline-sha256.json', 'tools/v'] {
			if (new.files[name] or { '' }) != (old.files[name] or { '' }) { return error('unrelated producer input differs: ' + name) }
		}
		stage.verify_browser_client(new, map[string]string{})!
		stage.recheck(new)!
		new_seal = seal
	}
	stage.recheck(old)!
	for path, pin in current { if sha256.sum(bounded_read(path)!.bytes()).hex() != pin { return error('live input changed during audit') } }
	for path in [repository + '/tests/native-android-ws/build-current-launch.v', os.real_path(os.executable())] {
		current[path] = stage.hash(path)!
	}
	os.write_file(output, json2.encode({
		'kind': json2.Any('vinix-maps-browser-poll-source-delta-v1'),
		'baseline_root': json2.Any(baseline), 'baseline_manifest_sha256': json2.Any(baseline_seal),
		'bundle_root': json2.Any(bundle_root), 'bundle_manifest_sha256': json2.Any(new_seal),
		'changed_path': json2.Any(changed_path), 'before_sha256': json2.Any(before_pin), 'after_sha256': json2.Any(after_pin),
		'input_count': json2.Any(347), 'production_input_count': json2.Any(18), 'unchanged_input_count': json2.Any(346),
		'checked_inputs_sha256': json2.decode[json2.Any](json2.encode(current))!,
	}, prettify: true) + '\n')!
	println('MAPS-BROWSER-POLL-SOURCE PASS exact347/1/346 production18 complete frozen closure and producer identity')
}

fn self_test() ! {
	mut before := map[string]string{}
	for i in 0 .. 17 { before[repository + '/fixture/' + i.str()] = before_pin }
	before[changed_path] = before_pin
	for i in 0 .. 329 { before['/compiler/' + i.str()] = before_pin }
	mut after := before.clone()
	after[changed_path] = after_pin
	compare(before, after)!
	if _ := compare(before, before) { return error('missing reviewed change accepted') }
	for path in before.keys() {
		mut bad := after.clone()
		bad[path] = bootstrap_pin
		if _ := compare(before, bad) { return error('unreviewed input mutation accepted') }
		bad = after.clone()
		bad.delete(path)
		if _ := compare(before, bad) { return error('missing input accepted') }
	}
	mut extra := after.clone()
	extra['/extra'] = before_pin
	if _ := compare(before, extra) { return error('added input accepted') }
	mut renamed := after.clone()
	renamed.delete('/compiler/0')
	renamed['/renamed'] = before_pin
	if _ := compare(before, renamed) { return error('same-count membership mutation accepted') }
	println('MAPS-BROWSER-POLL-SOURCE SELFTEST PASS missingchange347mutations347deletions extra rename')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
	if os.args.len == 3 && os.args[1] == '--live' { run('', '', os.args[2]) or { eprintln(err); exit(1) }; return }
	if os.args.len == 5 && os.args[1] == '--bundle' { run(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }; return }
	eprintln('usage: maps-browser-poll-source-delta --self-test | --live FRESH_REPORT | --bundle ROOT SEAL FRESH_REPORT')
	exit(2)
}
