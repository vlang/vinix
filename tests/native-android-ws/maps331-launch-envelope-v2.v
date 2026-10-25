module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/maps331-launch-envelope-v2-2026-10-25'
const launch_state = '/Users/alex/.local/state/vinix/android/maps331-launch-envelope-v2-run-2026-10-25'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source = state + '/launch-envelope.v'
const runner = repo + '/build/android-maps/maps331-run-recorded'
const launch_pins = repo + '/build/android-maps/maps331/launch-pins.json'
const prelaunch = '/Users/alex/.local/state/vinix/android/maps331-2026-10-25/prelaunch-sha256.json'

struct Removed {
	key string
	value_empty bool
	value_sha256 string
}

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn forbidden(key string) bool { return key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' }
fn canonical_pin(pin string) bool { return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) }

fn select_runner_pin(pins map[string]string) !string {
	if runner !in pins { return error('absolute recorded331 runner key missing') }
	pin := pins[runner]
	if !canonical_pin(pin) { return error('canonical recorded331 runner pin required') }
	if hash(runner)! != pin { return error('exact recorded331 runner required') }
	return pin
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
	assert output.keys().all(!forbidden(it)), 'forbidden environment key remains'
	return output, removed
}

fn command(label string, argv []string) !string {
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VMODULES': json2.Any(os.getenv('VMODULES'))
		'VTMP': json2.Any(os.getenv('VTMP'))
		'PATH': json2.Any(os.getenv('PATH'))
		'command_sha256_before': json2.Any(hash(os.real_path(argv[0]))!)
	}
	write_json(state + '/' + label + '-before.json', receipt)!
	r := os.exec(argv)
	os.write_file(state + '/' + label + '.log', r.output)!
	receipt['exit_code'] = json2.Any(r.exit_code)
	receipt['completed_utc'] = time.utc().str()
	receipt['command_sha256_after'] = json2.Any(hash(os.real_path(argv[0]))!)
	write_json(state + '/' + label + '.json', receipt)!
	assert receipt['command_sha256_before']! == receipt['command_sha256_after']!
	assert r.exit_code == 0, r.output
	return r.output
}

fn closure(label string) !map[string]string {
	listing := command(label, [compiler, '-print-v-files', '-nocache', '-cc', 'cc', '-cflags', '-O2', source])!
	mut result := map[string]string{}
	for line in listing.split_into_lines() {
		path := line.trim_space()
		if path.ends_with('.v') {
			assert path.starts_with('/') && path !in result
			result[path] = hash(path)!
		}
	}
	assert result.len > 10
	write_json(state + '/' + label + '-hashes.json', result)!
	return result
}

fn inventory(path string, prefix string, mut result map[string]string) ! {
	mut entries := os.ls(path)!
	entries.sort()
	for entry in entries {
		key := if prefix == '' { entry } else { prefix + '/' + entry }
		if key == 'sha256.json' { continue }
		file := path + '/' + entry
		assert !os.is_link(file), 'ordinary files only'
		match os.lstat(file)!.get_filetype() {
			.regular { result[key] = hash(file)! }
			.directory { inventory(file, key, mut result)! }
			else { return error('unexpected file type: ' + file) }
		}
	}
}

fn self_test() ! {
	actual_pins := json2.decode[map[string]string](os.read_file(launch_pins)!)!
	actual_runner_pin := select_runner_pin(actual_pins)!
	assert actual_runner_pin == '26eb66be3ffb5a70ce82b27ff57c53823e667e38d8851aeb2b6b108df8903bea'
	assert runner in actual_pins
	assert 'build/android-maps/maps331-run-recorded' !in actual_pins
	mut accepted_relative := true
	select_runner_pin({'build/android-maps/maps331-run-recorded': actual_runner_pin}) or { accepted_relative = false }
	assert !accepted_relative, 'relative runner key accepted'
	mut accepted_noncanonical := true
	select_runner_pin({runner: actual_runner_pin.to_upper()}) or { accepted_noncanonical = false }
	assert !accepted_noncanonical, 'noncanonical runner hash accepted'
	mut accepted_mismatch := true
	select_runner_pin({runner: '0'.repeat(64)}) or { accepted_mismatch = false }
	assert !accepted_mismatch, 'mismatched runner hash accepted'
	mut synthetic := os.environ()
	synthetic['VINIX_ANDROID_TRACE_'] = ''
	synthetic['VINIX_ANDROID_TRACE_TREE'] = '1'
	synthetic['ATL_UGLY_ENABLE_LOCATION'] = ''
	synthetic['VINIX_ANDROID_TRACE'] = 'keep'
	synthetic['ATL_UGLY_ENABLE_LOCATION_EXTRA'] = 'keep'
	filtered, removed := clean(synthetic)
	assert removed.any(it.key == 'VINIX_ANDROID_TRACE_' && it.value_empty)
	assert removed.any(it.key == 'VINIX_ANDROID_TRACE_TREE' && !it.value_empty)
	assert removed.any(it.key == 'ATL_UGLY_ENABLE_LOCATION' && it.value_empty)
	assert filtered['VINIX_ANDROID_TRACE'] == 'keep'
	assert filtered['ATL_UGLY_ENABLE_LOCATION_EXTRA'] == 'keep'
	mut child := os.new_process(os.executable())
	child.set_args(['--assert-clean'])
	child.set_environment(filtered)
	child.run()
	child.wait()
	assert child.code == 0
	write_json(state + '/self-test.json', {
		'utc': json2.Any(time.utc().str())
		'pass': json2.Any(true)
		'empty_and_nonempty_removed': json2.Any(true)
		'unrelated_names_preserved': json2.Any(true)
		'child_process_environment_absence_assertion': json2.Any(true)
		'actual_absolute_runner_key': json2.Any(runner)
		'actual_runner_sha256': json2.Any(actual_runner_pin)
		'relative_key_rejected': json2.Any(true)
		'noncanonical_and_mismatched_pins_rejected': json2.Any(true)
	})!
	println('MAPS331-LAUNCH-ENVELOPE-SELF-TEST-PASS')
}

fn build() ! {
	assert hash(compiler)! == compiler_pin
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', state + '/generated-c', true)
	os.mkdir_all(state + '/generated-c')!
	before := closure('v-closure-before')!
	command('recorded-build', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-cflags', '-O2', '-o', state + '/launch-envelope', source])!
	after := closure('v-closure-after')!
	assert before == after, 'consumed V sources changed during build'
	assert hash(compiler)! == compiler_pin
	command('self-test', [state + '/launch-envelope', '--self-test'])!
	mut pins := map[string]string{}
	inventory(state, '', mut pins)!
	write_json(state + '/sha256.json', pins)!
	println('MAPS331-LAUNCH-ENVELOPE-BUILD-PASS seal=' + hash(state + '/sha256.json')!)
}

fn bootstrap() ! {
	assert !os.exists(state) && !os.is_link(state), 'fresh v2 build directory required'
	old_launch_state := '/Users/alex/.local/state/vinix/android/maps331-launch-envelope-run-2026-10-25'
	assert !os.exists(old_launch_state) && !os.is_link(old_launch_state)
	old_state := '/Users/alex/.local/state/vinix/android/maps331-launch-envelope-2026-10-25'
	assert hash(old_state + '/sha256.json')! == 'fa9162d8a0cd261560f38f9548bc4dffd728566c93ca9d413fff9545eb27133e'
	os.mkdir(state)!
	os.cp(@FILE, source)!
	os.cp(os.executable(), state + '/bootstrap')!
	write_json(state + '/prior-envelope-failure.json', {
		'metadata_recorded_utc': json2.Any(time.utc().str())
		'original_failure_utc': json2.Any('not recorded')
		'evidence_source': json2.Any('Root tool transcript relayed to this agent; original output was not retained as a process log')
		'original_tool_output': json2.Any('V panic: map key does not exist\n v hash: b5bcdbb\n    pid: 0xc65b\n    tid: 0xc65b\n0   dyld                                0x000000018eaf3e00 start + 6992\n')
		'original_exit_code': json2.Any(1)
		'root_reported_order': json2.Any('After Maps331 runner check passed; before root followup requesting v2')
		'root_reported_guest_launched': json2.Any(false)
		'root_reported_immediate_launch_state_exists_check_exit_code': json2.Any(1)
		'old_launch_state_absent_at_metadata_recording': json2.Any(true)
		'old_build_manifest_sha256': json2.Any(hash(old_state + '/sha256.json')!)
		'old_source_sha256': json2.Any(hash(old_state + '/launch-envelope.v')!)
		'old_binary_sha256': json2.Any(hash(old_state + '/launch-envelope')!)
		'fix': json2.Any('Select the canonical runner pin by the absolute runner path used in the actual launch-pins map')
		'reproduction_performed': json2.Any(false)
	})!
	build()!
}

fn launch(lp string, pp string) !int {
	assert canonical_pin(lp) && canonical_pin(pp)
	assert os.getwd() == repo, 'run from exact repository root'
	assert hash(launch_pins)! == lp && hash(prelaunch)! == pp, 'supplied331 manifest pins differ'
	pins := json2.decode[map[string]string](os.read_file(launch_pins)!)!
	runner_pin := select_runner_pin(pins)!
	assert !os.exists(launch_state) && !os.is_link(launch_state), 'fresh launch envelope receipt directory required'
	os.mkdir(launch_state)!
	filtered, removed := clean(os.environ())
	argv := [runner, 'run', lp, pp]
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'launch_pins_sha256': json2.Any(lp)
		'prelaunch_sha256': json2.Any(pp)
		'runner_sha256_before': json2.Any(runner_pin)
		'envelope_sha256': json2.Any(hash(os.executable())!)
		'envelope_source_sha256': json2.Any(hash(source)!)
		'clean_environment_assertion': json2.Any(true)
		'forbidden_keys_remaining': json2.Any([]string{})
		'clean_environment_entries': json2.Any(filtered.len)
		'policy': json2.Any('Exact custom child environment; every VINIX_ANDROID_TRACE_* and ATL_UGLY_ENABLE_LOCATION key removed, including empty values. Other entries preserved. No trace/location setters.')
	}
	write_json(launch_state + '/removed-environment.json', removed)!
	receipt['removed_environment_sha256'] = json2.Any(hash(launch_state + '/removed-environment.json')!)
	write_json(launch_state + '/launch-before.json', receipt)!
	mut process := os.new_process(runner)
	process.set_args(argv[1..])
	process.set_environment(filtered)
	process.run()
	process.wait()
	receipt['exit_code'] = json2.Any(process.code)
	receipt['completed_utc'] = time.utc().str()
	receipt['runner_sha256_after'] = json2.Any(hash(runner)!)
	write_json(launch_state + '/launch.json', receipt)!
	assert hash(runner)! == runner_pin, 'runner changed during launch'
	mut final_pins := map[string]string{}
	inventory(launch_state, '', mut final_pins)!
	write_json(launch_state + '/sha256.json', final_pins)!
	println('MAPS331-LAUNCH-ENVELOPE-RECORDED seal=' + hash(launch_state + '/sha256.json')!)
	return process.code
}

fn main() {
	$if prod { panic('assertions required') }
	if os.args.len == 2 && os.args[1] == '--bootstrap' { bootstrap() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == '--build' { build() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { panic(err) }; return }
	if os.args.len == 2 && os.args[1] == '--assert-clean' {
		assert os.environ().keys().all(!forbidden(it))
		assert os.getenv('VINIX_ANDROID_TRACE') == 'keep'
		assert os.getenv('ATL_UGLY_ENABLE_LOCATION_EXTRA') == 'keep'
		println('MAPS331-CHILD-ENV-ABSENT-PASS')
		return
	}
	if os.args.len == 3 && os.args[1] == '--verify-build' {
		assert canonical_pin(os.args[2]) && hash(state + '/sha256.json')! == os.args[2]
		expected := json2.decode[map[string]string](os.read_file(state + '/sha256.json')!)!
		mut actual := map[string]string{}
		inventory(state, '', mut actual) or { panic(err) }
		assert actual == expected
		println('MAPS331-LAUNCH-ENVELOPE-READBACK-PASS entries=' + actual.len.str())
		return
	}
	if os.args.len == 3 { exit(launch(os.args[1], os.args[2]) or { panic(err) }) }
	panic('usage: launch-envelope LAUNCH_PINS_SHA PRELAUNCH_SHA | --verify-build BUILD_SEAL')
}
