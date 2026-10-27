// SPDX-License-Identifier: GPL-2.0-or-later
// Exact source audit for the opt-in main-thread heartbeat native successor.
module main

import crypto.sha256
import json2
import os

const repository = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const baseline = state + 'current-native-build-2026-10-27-onboarding-r5'
const baseline_seal = '05baf5d011337d54aab26f6cc3c535f801221d51aceb966ebc9442d88b5fd6b8'
const origins_pin = '62d33100c4857ab98e8913a8ef21b057e2e125f6092c692b4bcfd694f2efc8dc'
const framework = state + 'combined-account-webview-broadcast-result-framework-2026-10-27-r1'
const framework_seal = '21d53cc9cd2ccd9c53fc7774a826d83673f3391d30c1757074e3edcba2c8b046'
const generated_pin = '852fbe4ba67832f5cebbf920cffaaed982a6c1fd47ab9ca0a8ad50771f0174a7'
const bindings_pin = '60b590a07c627bd3ff8d57f1edaf5c0bd2e06c44124c7f808c6f5701f5bb3bbe'
const maximum_bytes = 8 * 1024 * 1024

struct Snapshot {
	origins map[string]string
	sources map[string]string
	consumed map[string]string
}

fn old_changes() map[string]string {
	return {
		repository + '/build-support/android/nativews/diagnostics.v': 'dca8298349f52307542092707856e9bb472b7bd031b772d7003640e8003c0176'
		repository + '/build-support/android/nativews/runtime.v': '426f69ffc8e98a80ce02aaf63ff6c0ca9c0f00ffebbf2ab7821588200e71d370'
		repository + '/build-support/android/nativews/ws_views.v': '1b74f775e27f1c7a392b9fd659c0d7000993a1b23bb3857f8c5363d7e6b58901'
	}
}

fn new_changes() map[string]string {
	return {
		repository + '/build-support/android/nativews/diagnostics.v': '8633cd521d7ff971402543421b23e0571517632c2ed0ce09db8e92e7896c1f70'
		repository + '/build-support/android/nativews/runtime.v': '145c627c5d069c907fcb649650132e17e378508c122a18f22d0a37e3a8d3b1de'
		repository + '/build-support/android/nativews/ws_views.v': '2727d5a01d930993de645822aba70e561c82173998d1289a6ee53a8b88feb768'
	}
}

fn helper_pins() map[string]string {
	return {
		repository + '/tests/native-android-tools/androidtools/native_ws.v': '2725ddfc834aba66d052ecdd4d7de2b5ef5853c6280e7870e0ba8796fd24f751'
		repository + '/tests/linuxkpi/generate_module.v': '3a6a4402a3cd68f3a4acc2db6563e78b8191d41fd85a9b9c78882073c1b81a67'
		repository + '/build-support/find-v.sh': 'c0e16450ff419e4bea27345cdf85338f6aa73a65feb9ce6f98c87b6ef8bd8577'
	}
}

fn valid_pin(pin string) bool {
	return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

// Cap the read itself, including a file that grows after lstat().
fn bounded_read(path string) !string {
	before := os.lstat(path)!
	if os.real_path(path) != path || before.get_filetype() != .regular
		|| before.size < 0 || before.size > maximum_bytes {
		return error('canonical bounded regular file required: ' + path)
	}
	mut file := os.open(path)!
	defer { file.close() }
	mut buffer := []u8{len: 64 * 1024}
	mut bytes := []u8{cap: int(before.size)}
	for {
		n := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if n == 0 { break }
		if bytes.len + n > maximum_bytes { return error('file exceeded read bound: ' + path) }
		bytes << buffer[..n]
	}
	after := os.lstat(path)!
	if after.get_filetype() != .regular || os.real_path(path) != path
		|| before.size != bytes.len || after.size != bytes.len {
		return error('file changed during bounded read: ' + path)
	}
	return bytes.bytestr()
}

fn checked_read(path string, pin string, mut checked map[string]string) !string {
	if !valid_pin(pin) { return error('invalid expected SHA256: ' + path) }
	text := bounded_read(path)!
	if sha256.sum(text.bytes()).hex() != pin { return error('file hash differs: ' + path) }
	if prior := checked[path] {
		if prior != pin { return error('conflicting input identity: ' + path) }
	}
	checked[path] = pin
	return text
}

fn relative_path(path string) bool {
	return path != '' && !path.starts_with('/') && os.norm_path(path) == path
		&& !path.contains('\\') && !path.contains('\x00') && !path.contains('\n')
		&& path.split('/').all(it != '' && it != '.' && it != '..')
}

fn manifest(root string, seal string, mut checked map[string]string) !map[string]string {
	if !root.starts_with(state) || os.real_path(root) != root || os.norm_path(root) != root {
		return error('canonical external bundle root required')
	}
	files := json2.decode[map[string]string](checked_read(root + '/sha256.json', seal, mut checked)!)!
	if files.len == 0 || files.len > 4096 { return error('bounded nonempty manifest required') }
	for path, pin in files {
		if !relative_path(path) || !valid_pin(pin) { return error('invalid manifest member: ' + path) }
	}
	return files
}

fn member(root string, files map[string]string, relative string, mut checked map[string]string) !string {
	return checked_read(root + '/' + relative, files[relative] or {
		return error('unsealed member: ' + relative)
	}, mut checked)
}

fn valid_origin(name string, path string) bool {
	return name.ends_with('.v') && name != 'ws_generated.v' && os.file_name(path) == name
		&& name == os.file_name(name) && name !in ['.', '..']
		&& os.dir(path) in [repository + '/build-support/android/atlframework', repository + '/build-support/android/nativews']
}

fn compare_sources(before map[string]string, after map[string]string) !map[string]map[string]string {
	if before.len != 87 || after.len != 87 { return error('exact 87 production sources required') }
	old := old_changes()
	new := new_changes()
	mut changes := map[string]map[string]string{}
	for path, pin in before {
		if !valid_origin(os.file_name(path), path) || !valid_pin(pin) { return error('invalid production source: ' + path) }
		current := after[path] or { return error('production source removed: ' + path) }
		if path in old {
			if pin != old[path]! || !valid_pin(new[path]!) || current != new[path]!
				|| current == pin { return error('reviewed heartbeat source delta differs: ' + path) }
			changes[path] = {'deployed_sha256': pin, 'current_sha256': current}
		} else if current != pin { return error('unreviewed native source delta: ' + path) }
	}
	if changes.len != 3 { return error('all three reviewed source changes required') }
	return changes
}

fn snapshot(root string, seal string, mut checked map[string]string) !Snapshot {
	files := manifest(root, seal, mut checked)!
	if (files['native/source-origins.json'] or { '' }) != origins_pin
		|| (files['native/bindings.txt'] or { '' }) != bindings_pin
		|| (files['native/atlframework/ws_generated.v'] or { '' }) != generated_pin {
		return error('retained origins, bindings or generated JNI identity differs')
	}
	origins := json2.decode[map[string]string](member(root, files, 'native/source-origins.json', mut checked)!)!
	if origins.len != 87 { return error('exact 87 sealed source origins required') }
	mut sources := map[string]string{}
	mut names := ['ws_generated.v']
	for name, origin in origins {
		if !valid_origin(name, origin) { return error('unexpected sealed source origin: ' + origin) }
		relative := 'native/atlframework/' + name
		member(root, files, relative, mut checked)!
		sources[origin] = files[relative]!
		names << name
	}
	names.sort()
	if os.ls(root + '/native/atlframework')!.sorted() != names {
		return error('copied native source membership differs')
	}
	sealed_names := files.keys().filter(it.starts_with('native/atlframework/')).map(it.all_after('native/atlframework/')).sorted()
	if sealed_names != names { return error('sealed native source membership differs') }
	member(root, files, 'native/atlframework/ws_generated.v', mut checked)!
	member(root, files, 'native/bindings.txt', mut checked)!
	mut expected_inputs := sources.clone()
	expected_inputs[repository + '/build-support/android/nativews/bindings.txt'] = bindings_pin
	if json2.decode[map[string]string](member(root, files, 'native/current-inputs.json', mut checked)!)! != expected_inputs {
		return error('exact source/input receipt differs')
	}
	for origin, pin in helper_pins() {
		label := if origin.ends_with('/generate_module.v') { 'native-generator' } else { 'builder' }
		relative := if origin.ends_with('/find-v.sh') { 'tools/find-v.sh' } else { 'closure/' + label + '/' + origin.trim_left('/') }
		if (files[relative] or { '' }) != pin { return error('sealed generator helper identity differs: ' + origin) }
		member(root, files, relative, mut checked)!
		if !origin.ends_with('/find-v.sh') {
			closure := json2.decode[map[string]string](member(root, files, label + '-closure.json', mut checked)!)!
			if (closure[origin] or { '' }) != pin { return error('generator helper closure identity differs') }
		}
	}
	build := json2.decode[map[string]string](member(root, files, 'build.json', mut checked)!)!
	if (build['framework'] or { '' }) != framework || (build['framework_sha256'] or { '' }) != framework_seal
		|| (files['framework-sha256.json'] or { '' }) != framework_seal {
		return error('native producer must consume the retained broadcast framework')
	}
	member(root, files, 'framework-sha256.json', mut checked)!
	consumed := json2.decode[map[string]string](member(root, files, 'framework/consumed-smali.json', mut checked)!)!
	if consumed.len == 0 || consumed.len > 512 { return error('bounded consumed framework set required') }
	mut actual_consumed := map[string]string{}
	for path, pin in consumed {
		if !relative_path(path) || !path.starts_with('smali/') || !path.ends_with('.smali') || !valid_pin(pin)
			|| (files['framework/' + path] or { '' }) != pin {
			return error('invalid consumed framework member')
		}
		member(root, files, 'framework/' + path, mut checked)!
	}
	for path, pin in files {
		if path.starts_with('framework/smali/') { actual_consumed[path.all_after('framework/')] = pin }
	}
	if actual_consumed != consumed { return error('sealed consumed framework set differs') }
	return Snapshot{origins: origins, sources: sources, consumed: consumed}
}

fn live_sources(origins map[string]string, mut checked map[string]string) !map[string]string {
	mut observed := map[string]string{}
	for directory in ['atlframework', 'nativews'] {
		for name in os.ls(repository + '/build-support/android/' + directory)!.filter(it.ends_with('.v')) {
			path := repository + '/build-support/android/' + directory + '/' + name
			if (origins[name] or { '' }) != path || name in observed { return error('live production source membership differs: ' + path) }
			observed[name] = path
		}
	}
	if observed != origins { return error('live production source membership differs') }
	mut pins := map[string]string{}
	for _, path in origins {
		pin := sha256.sum(bounded_read(path)!.bytes()).hex()
		if previous := checked[path] {
			if pin != previous { return error('live source changed during audit: ' + path) }
		}
		checked[path] = pin
		pins[path] = pin
	}
	return pins
}

fn fresh_report(path string) ! {
	if !path.starts_with(state) || os.norm_path(path) != path || os.real_path(os.dir(path)) != os.dir(path)
		|| os.exists(path) || os.is_link(path) || path.contains('\x00') || path.contains('\n') {
		return error('fresh canonical external report required')
	}
}

fn run(bundle string, seal string, destination string) ! {
	fresh_report(destination)!
	if destination.starts_with(baseline + '/') || (bundle != '' && destination.starts_with(bundle + '/')) {
		return error('report must remain outside the audited bundles')
	}
	if bundle != '' && (bundle == baseline || !bundle.starts_with(state + 'current-native-build-')) {
		return error('fresh current-native successor bundle required')
	}
	mut checked := map[string]string{}
	old := snapshot(baseline, baseline_seal, mut checked)!
	before := live_sources(old.origins, mut checked)!
	changes := compare_sources(old.sources, before)!
	checked_read(repository + '/build-support/android/nativews/bindings.txt', bindings_pin, mut checked)!
	for path, pin in helper_pins() { checked_read(path, pin, mut checked)! }
	checked_read(framework + '/sha256.json', framework_seal, mut checked)!
	if bundle != '' {
		current := snapshot(bundle, seal, mut checked)!
		if current.origins != old.origins || current.sources != before || current.consumed != old.consumed {
			return error('successor must retain exact origins, live source copies and consumed framework')
		}
		compare_sources(old.sources, current.sources)!
	}
	// Recheck all inspected bytes and both membership lists after the audit.
	for path in checked.keys() { checked_read(path, checked[path]!, mut checked)! }
	if live_sources(old.origins, mut checked)! != before { return error('live source snapshot changed') }
	for root in [baseline, bundle].filter(it != '') {
		mut expected := old.origins.keys()
		expected << 'ws_generated.v'
		expected.sort()
		if os.ls(root + '/native/atlframework')!.sorted() != expected { return error('copied source set changed during audit') }
	}
	fresh_report(destination)!
	os.write_file(destination, json2.encode({
		'kind': json2.Any('vinix-maps-native-heartbeat-source-delta-v1'),
		'scope': json2.Any('Exact source, generator helper and copied JNI/framework input audit only; no binary build, guest or login claim.'),
		'mode': json2.Any(if bundle == '' { 'live' } else { 'bundle' }),
		'baseline': json2.Any(baseline), 'baseline_sha256': json2.Any(baseline_seal),
		'bundle': json2.Any(bundle), 'bundle_sha256': json2.Any(seal),
		'checked_source_count': json2.Any(before.len), 'unchanged_source_count': json2.Any(before.len - changes.len),
		'changes': json2.decode[json2.Any](json2.encode(changes))!,
		'bindings_sha256': json2.Any(bindings_pin), 'generated_ws_sha256': json2.Any(generated_pin),
		'framework': json2.Any(framework), 'framework_sha256': json2.Any(framework_seal),
		'helper_sha256': json2.decode[json2.Any](json2.encode(helper_pins()))!,
		'checked_input_sha256': json2.decode[json2.Any](json2.encode(checked))!,
		'before_after_verified': json2.Any(true),
	}, prettify: true) + '\n')!
	mode := if bundle == '' { 'live' } else { 'bundle' }
	println('MAPS-NATIVE-HEARTBEAT-SOURCE-DELTA PASS sources=87 unchanged=84 changes=3 mode=' + mode + ' report=' + destination)
}

fn self_test() ! {
	mut before := old_changes()
	mut after := new_changes()
	for i in 0 .. 84 {
		path := repository + '/build-support/android/nativews/fixture_' + i.str() + '.v'
		before[path] = 'a'.repeat(64)
		after[path] = 'a'.repeat(64)
	}
	if compare_sources(before, after)!.len != 3 { return error('reviewed source fixture failed') }
	for path in before.keys() {
		mut bad := after.clone()
		bad[path] = 'b'.repeat(64)
		if _ := compare_sources(before, bad) { return error('unreviewed source hash accepted') }
		bad.delete(path)
		if _ := compare_sources(before, bad) { return error('missing source accepted') }
	}
	mut extra := after.clone()
	extra[repository + '/build-support/android/nativews/extra.v'] = 'a'.repeat(64)
	if _ := compare_sources(before, extra) { return error('extra production source accepted') }
	if _ := compare_sources(before, before) { return error('missing heartbeat changes accepted') }
	for path in old_changes().keys() {
		mut bad := before.clone()
		bad[path] = 'a'.repeat(64)
		if _ := compare_sources(bad, after) { return error('different deployed source accepted') }
	}
	for path in ['../escape', '/absolute', 'native//double', 'native/../escape', 'native/a\\b', 'native/a\n'] {
		if relative_path(path) { return error('malformed member accepted') }
	}
	for pin in ['', 'a'.repeat(63), 'A'.repeat(64), 'g'.repeat(64)] {
		if valid_pin(pin) { return error('invalid pin accepted') }
	}
	println('MAPS-NATIVE-HEARTBEAT-SOURCE-DELTA SELF-PASS exact-87 reviewed-three unchanged-84 membership old-new-pins paths')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
	} else if os.args.len == 3 && os.args[1] == '--live' {
		run('', '', os.args[2]) or { eprintln(err); exit(1) }
	} else if os.args.len == 5 && os.args[1] == '--bundle' {
		run(os.args[2], os.args[3], os.args[4]) or { eprintln(err); exit(1) }
	} else {
		eprintln('usage: maps-native-heartbeat-source-delta --self-test | --live FRESH_EXTERNAL_REPORT | --bundle EXACT_NEW_ROOT EXACT_NEW_SEAL FRESH_EXTERNAL_REPORT')
		exit(2)
	}
}
