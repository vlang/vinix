// SPDX-License-Identifier: GPL-2.0-or-later
// Fresh receipts for pinned Maps replays after331; no implicit stage chaining.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const generator = repo + '/build/android-maps/maps-replay-generate314'
const generator_source = repo + '/tests/native-android-ws/maps-replay-generate.v'
const original_source = repo + '/tests/native-android-ws/maps298-run.v'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

struct Removed {
	key string
	value_empty bool
	value_sha256 string
}

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn canonical(pin string) bool { return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) }
fn forbidden(key string) bool { return key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' }

fn require_pin(path string, pin string) ! {
	assert canonical(pin) && !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	assert hash(path)! == pin, 'wrong pinned input: ' + path
}

fn clean(input map[string]string) (map[string]string, []Removed) {
	mut output := map[string]string{}
	mut removed := []Removed{}
	mut keys := input.keys()
	keys.sort()
	for key in keys {
		value := input[key]
		if forbidden(key) {
			removed << Removed{key: key, value_empty: value.len == 0, value_sha256: sha256.sum(value.bytes()).hex()}
		} else { output[key] = value }
	}
	assert output.keys().all(!forbidden(it))
	return output, removed
}

fn select_runner_pin(pins map[string]string, runner string, expected string) !string {
	if !runner.starts_with(repo + '/build/android-maps/') || runner !in pins {
		return error('absolute recorded runner key required')
	}
	pin := pins[runner]
	if !canonical(pin) || !canonical(expected) || pin != expected {
		return error('canonical matching runner pin required')
	}
	if os.is_link(runner) || os.lstat(runner)!.get_filetype() != .regular || hash(runner)! != pin {
		return error('recorded runner bytes differ')
	}
	return pin
}

fn inventory(root string, relative string, mut files map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		assert !os.is_link(path)
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut files)! }
			.regular { files[key] = hash(path)! }
			else { return error('nonregular receipt entry: ' + path) }
		}
	}
}

fn fresh(root string) ! {
	assert os.dir(root) == state && os.real_path(state) == state
	assert !os.exists(root) && !os.is_link(root), 'fresh external receipt root required'
	os.mkdir(root)!
	os.cp(@FILE, root + '/receipt.v')!
}

fn seal(root string) ! {
	mut files := map[string]string{}
	inventory(root, '', mut files)!
	write_json(root + '/sha256.json', files)!
	println('MAPS-REPLAY-RECEIPT seal=' + hash(root + '/sha256.json')!)
}

fn command(root string, argv []string, environment map[string]string, removed []Removed,
	inputs map[string]string) !int {
	os.write_file(root + '/disk-before.txt', os.exec(['/bin/df', '-k', state]).output)!
	write_json(root + '/removed-environment.json', removed)!
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'program_sha256_before': json2.Any(hash(argv[0])!)
		'wrapper_source_sha256': json2.Any(hash(@FILE)!)
		'wrapper_binary_sha256': json2.Any(hash(os.executable())!)
		'clean_environment_entries': json2.Any(environment.len)
		'forbidden_keys_remaining': json2.Any(environment.keys().filter(forbidden(it)))
		'removed_environment_sha256': json2.Any(hash(root + '/removed-environment.json')!)
	}
	assert environment.keys().all(!forbidden(it))
	write_json(root + '/input-pins.json', inputs)!
	write_json(root + '/started.json', receipt)!
	mut stdout := os.create(root + '/stdout.log')!
	mut stderr := os.create(root + '/stderr.log')!
	mut child := os.new_process(argv[0])
	child.set_args(argv[1..])
	child.set_environment(environment)
	child.set_redirect_stdio()
	child.set_stdin_path('/dev/null')
	child.run()
	for {
		stdout.write_string(child.stdout_read())!
		stderr.write_string(child.stderr_read())!
		if !child.is_alive() { break }
		time.sleep(10 * time.millisecond)
	}
	child.wait()
	for _ in 0 .. 32 {
		a, b := child.stdout_read(), child.stderr_read()
		stdout.write_string(a)!
		stderr.write_string(b)!
		if a == '' && b == '' { break }
	}
	stdout.close()
	stderr.close()
	mut unchanged := true
	for path, pin in inputs { if hash(path)! != pin { unchanged = false } }
	receipt['exit_code'] = json2.Any(child.code)
	receipt['completed_utc'] = time.utc().str()
	receipt['program_sha256_after'] = json2.Any(hash(argv[0])!)
	receipt['input_pins_unchanged'] = json2.Any(unchanged)
	write_json(root + '/receipt.json', receipt)!
	os.write_file(root + '/disk-after.txt', os.exec(['/bin/df', '-k', state]).output)!
	if !unchanged { return error('input pin changed; receipt retained') }
	return child.code
}

fn replacement_pins(path string, pin string) !map[string]string {
	assert os.dir(path) == state && os.real_path(path) == path
	require_pin(path, pin)!
	pins := json2.decode[map[string]string](os.read_file(path)!)!
	assert pins.len == 6
	for label in ['native', 'framework'] {
		for suffix in ['_root', '_manifest_sha256', '_sha256'] { assert label + suffix in pins }
		root := pins[label + '_root']
		assert os.dir(root) == state && os.is_dir(root) && !os.is_link(root) && os.real_path(root) == root
		assert os.base(root).ends_with('-' + label + '-build-2026-10-25')
		manifest_pin, payload_pin := pins[label + '_manifest_sha256'], pins[label + '_sha256']
		require_pin(root + '/sha256.json', manifest_pin)!
		manifest := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
		payload := if label == 'native' { 'native/libvinix-android-native.so' } else { 'framework/api-impl.jar' }
		assert payload in manifest && manifest[payload] == payload_pin
		require_pin(root + '/' + payload, payload_pin)!
	}
	return pins
}

fn self_test(root string) ! {
	require_pin(compiler, compiler_pin)!
	mut synthetic := os.environ()
	synthetic['VINIX_ANDROID_TRACE_'] = ''
	synthetic['VINIX_ANDROID_TRACE_TREE'] = '1'
	synthetic['ATL_UGLY_ENABLE_LOCATION'] = ''
	synthetic['VINIX_ANDROID_TRACE'] = 'keep'
	synthetic['ATL_UGLY_ENABLE_LOCATION_EXTRA'] = 'keep'
	environment, removed := clean(synthetic)
	assert removed.any(it.key == 'VINIX_ANDROID_TRACE_' && it.value_empty)
	assert removed.any(it.key == 'VINIX_ANDROID_TRACE_TREE' && !it.value_empty)
	assert removed.any(it.key == 'ATL_UGLY_ENABLE_LOCATION' && it.value_empty)
	assert environment['VINIX_ANDROID_TRACE'] == 'keep' && environment['ATL_UGLY_ENABLE_LOCATION_EXTRA'] == 'keep'
	// Exercise the real selector with this host tool, without requiring a guest runner.
	actual := repo + '/build/android-maps/' + os.file_name(os.executable())
	assert os.executable() == actual, 'self-test binary must be an ordinary build/android-maps file'
	pin := hash(actual)!
	assert select_runner_pin({actual: pin}, actual, pin)! == pin
	mut rejected := 0
	select_runner_pin({os.file_name(actual): pin}, actual, pin) or { rejected += 1 }
	select_runner_pin({actual: pin.to_upper()}, actual, pin) or { rejected += 1 }
	select_runner_pin({actual: '0'.repeat(64)}, actual, '0'.repeat(64)) or { rejected += 1 }
	select_runner_pin({actual: pin}, actual, pin.to_upper()) or { rejected += 1 }
	assert rejected == 4
	fresh(root)!
	status := command(root, [actual, '--assert-clean'], environment, removed, {actual: pin, @FILE: hash(@FILE)!, compiler: compiler_pin})!
	write_json(root + '/self-test-details.json', {
		'pass': json2.Any(status == 0)
		'canonical_absolute_runner_key': json2.Any(actual)
		'relative_noncanonical_and_mismatched_pins_rejected': json2.Any(rejected)
		'empty_and_nonempty_forbidden_entries_removed': json2.Any(true)
		'unrelated_names_preserved': json2.Any(true)
		'child_asserted_filtered_environment': json2.Any(status == 0)
	})!
	seal(root)!
	assert status == 0
	println('MAPS-REPLAY-RECEIPT-SELF-TEST-PASS')
}

fn stage() !int {
	mode := os.args[1]
	assert mode in ['generate', 'prepare', 'check', 'run']
	assert os.args.len == if mode == 'generate' { 6 } else { 8 }
	number := os.args[2]
	assert number.int() >= 332 && number.int().str() == number, 'canonical fresh attempt332 or later required'
	name := 'maps' + number
	root := os.abs_path(os.args.last())
	runner := repo + '/build/android-maps/' + name + '-run-recorded'
	source := state + '/' + name + '-generation-2026-10-25/' + name + '-run.v'
	mut inputs := {
		compiler: compiler_pin
		generator: '75b69d07fdf23401b07ee8cad36d7ba2a47dfd5e48c13660c4307f91e882b453'
		generator_source: '39b9d763de6c5685021731ec877a276d2110f8cd457c4ff6bcf8bc1e399b6d84'
		original_source: '5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1'
		@FILE: hash(@FILE)!
	}
	mut argv := []string{}
	if mode in ['generate', 'prepare'] {
		path, pin := os.abs_path(os.args[3]), os.args[4]
		pins := replacement_pins(path, pin)!
		inputs[path] = pin
		if mode == 'generate' {
			for destination in [state + '/' + name + '-generation-2026-10-25', state + '/' + name + '-run-build-c-2026-10-25',
				runner, repo + '/build/android-maps/' + name, repo + '/build/android-maps/attempt' + number,
				repo + '/build/android-maps/attempt' + number + '.json', state + '/' + name + '-2026-10-25'] {
				assert !os.exists(destination) && !os.is_link(destination), 'fresh replay destination required: ' + destination
			}
			argv = [generator, number, path, '--minimum-free-mib=1536']
		} else {
			inputs[runner], inputs[source] = os.args[5], os.args[6]
			argv = [runner, 'prepare', pins['native_root'], pins['native_manifest_sha256'], pins['native_sha256'],
				pins['framework_root'], pins['framework_manifest_sha256'], pins['framework_sha256']]
		}
	} else {
		inputs[runner], inputs[source] = os.args[3], os.args[4]
		lp := repo + '/build/android-maps/' + name + '/launch-pins.json'
		pp := state + '/' + name + '-2026-10-25/prelaunch-sha256.json'
		inputs[lp], inputs[pp] = os.args[5], os.args[6]
		require_pin(lp, inputs[lp])!
		require_pin(pp, inputs[pp])!
		pins := json2.decode[map[string]string](os.read_file(lp)!)!
		select_runner_pin(pins, runner, inputs[runner])!
		assert source in pins && pins[source] == inputs[source], 'absolute generated-source launch pin differs'
		argv = [runner, mode, inputs[lp], inputs[pp]]
	}
	for path, pin in inputs { require_pin(path, pin)! }
	fresh(root)!
	environment, removed := clean(os.environ())
	status := command(root, argv, environment, removed, inputs) or {
		seal(root)!
		return err
	}
	seal(root)!
	return status
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo, 'run from exact repository root'
	if os.args.len == 2 && os.args[1] == '--assert-clean' {
		assert os.environ().keys().all(!forbidden(it))
		assert os.getenv('VINIX_ANDROID_TRACE') == 'keep' && os.getenv('ATL_UGLY_ENABLE_LOCATION_EXTRA') == 'keep'
		println('MAPS-REPLAY-RECEIPT-CHILD-CLEAN-PASS')
		return
	}
	if os.args.len == 3 && os.args[1] == 'self-test' {
		self_test(os.abs_path(os.args[2])) or { panic(err) }
		return
	}
	assert os.args.len in [6, 8], 'usage: self-test ROOT | generate NUMBER PINS_JSON PINS_SHA ROOT | prepare NUMBER PINS_JSON PINS_SHA RUNNER_SHA SOURCE_SHA ROOT | check|run NUMBER RUNNER_SHA SOURCE_SHA LAUNCH_SHA PRELAUNCH_SHA ROOT'
	exit(stage() or { panic(err) })
}
