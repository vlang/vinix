// SPDX-License-Identifier: GPL-2.0-or-later
// Receipts for Maps368 with exact Native351 and Framework367 identities.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const runner368 = repo + '/build/android-maps/maps368-run-recorded'
const source368 = state + '/maps368-generation-2026-10-26/maps368-run.v'

fn expected_replacements() map[string]string {
	return {
		'native_root': state + '/text-size351-native-build-2026-10-25'
		'native_manifest_sha256': 'eb0dfe0dd87ea7f5972bddd06ae4c0c45ba8b9e5ad56a39c074142847f4bccd9'
		'native_sha256': 'd3da7eefd58c8f1faf7a88dd0b6fa0839cebdba145d236bd5fe1ecc185e257a1'
		'framework_root': state + '/timing-logger367-framework-build-2026-10-26'
		'framework_manifest_sha256': '933baf6da303aebaf262e280e41769c89b61c2f050b481dd4075900a533ad23b'
		'framework_sha256': 'fece4cb639fb8745557032f872d13d45767768656ae879f065324696bbf99694'
	}
}

fn replacement_identity(pins map[string]string) ! {
	expected := expected_replacements()
	if pins.len != expected.len { return error('exact six replacement identities required') }
	for key, pin in expected {
		if pins[key] or { '' } != pin { return error('replacement identity differs: ' + key) }
	}
}

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
	replacement_identity(pins)!
	for label in ['native', 'framework'] {
		for suffix in ['_root', '_manifest_sha256', '_sha256'] { assert label + suffix in pins }
		root := pins[label + '_root']
		assert os.dir(root) == state && os.is_dir(root) && !os.is_link(root) && os.real_path(root) == root
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
	mut before := map[string]string{}
	inventory(root, '', mut before)!
	mut identities_rejected := 0
	for key, value in expected_replacements() {
		mut wrong := expected_replacements()
		wrong[key] = if key.ends_with('_root') { value + '-wrong' } else { '0'.repeat(64) }
		replacement_identity(wrong) or { identities_rejected += 1 }
	}
	mut extra := expected_replacements()
	extra['unexpected'] = 'value'
	replacement_identity(extra) or { identities_rejected += 1 }
	mut missing := expected_replacements()
	missing.delete('framework_root')
	replacement_identity(missing) or { identities_rejected += 1 }
	assert identities_rejected == 8
	replacement_identity(expected_replacements())!
	mut after := map[string]string{}
	inventory(root, '', mut after)!
	assert before == after, 'rejected replacement identities mutated receipt files'
	mut cli_rejected := 0
	for key, value in expected_replacements() {
		mut wrong := expected_replacements()
		wrong[key] = if key.ends_with('_root') { value + '-wrong' } else { '0'.repeat(64) }
		input := root + '-wrong-' + key + '.json'
		destination := root + '-rejected-' + key
		assert !os.exists(input) && !os.is_link(input)
		assert !os.exists(destination) && !os.is_link(destination)
		write_json(input, wrong)!
		input_pin := hash(input)!
		argv := [actual, 'prepare', '368', input, input_pin, '0'.repeat(64), '0'.repeat(64), destination]
		r := os.exec(argv)
		assert r.exit_code != 0 && r.output.contains('replacement identity differs: ' + key)
		assert hash(input)! == input_pin && !os.exists(destination) && !os.is_link(destination)
		evidence := root + '/rejections/' + key
		os.mkdir_all(evidence)!
		os.mv(input, evidence + '/pins.json')!
		os.write_file(evidence + '/output.log', r.output)!
		write_json(evidence + '/receipt.json', {
			'argv': json2.Any(argv)
			'exit_code': json2.Any(r.exit_code)
			'input_sha256_unchanged': json2.Any(input_pin)
			'receipt_destination_absent': json2.Any(true)
		})!
		cli_rejected += 1
	}
	assert cli_rejected == 6
	mut stages_rejected := 0
	for number in ['360', '362', '364', '366', '367', '0368', '368x'] {
		stage_identity('prepare', number) or { stages_rejected += 1 }
	}
	stage_identity('generate', '368') or { stages_rejected += 1 }
	assert stages_rejected == 8
	status := command(root, [actual, '--assert-clean'], environment, removed, {actual: pin, @FILE: hash(@FILE)!, compiler: compiler_pin})!
	os.mkdir(root + '/nonzero-child')!
	nonzero := command(root + '/nonzero-child', [actual, '--exit-seven'], environment, removed,
		{actual: pin, @FILE: hash(@FILE)!, compiler: compiler_pin})!
	assert nonzero == 7, 'child exit status must propagate unchanged'
	write_json(root + '/self-test-details.json', {
		'pass': json2.Any(status == 0)
		'canonical_absolute_runner_key': json2.Any(actual)
		'relative_noncanonical_and_mismatched_pins_rejected': json2.Any(rejected)
		'empty_and_nonempty_forbidden_entries_removed': json2.Any(true)
		'unrelated_names_preserved': json2.Any(true)
		'child_asserted_filtered_environment': json2.Any(status == 0)
		'wrong_root_pin_missing_extra_rejections': json2.Any(identities_rejected)
		'rejected_identity_receipt_inventory_unchanged': json2.Any(before == after)
		'wrong_root_and_pin_cli_rejected_before_receipt_creation': json2.Any(cli_rejected)
		'non368_and_generate_rejections': json2.Any(stages_rejected)
		'nonzero_child_exit_code': json2.Any(nonzero)
	})!
	seal(root)!
	assert status == 0
	println('MAPS368-REPLAY-RECEIPT-SELF-TEST-PASS')
}

fn stage_identity(mode string, number string) ! {
	if mode !in ['prepare', 'check', 'run'] || number != '368' {
		return error('only Maps368 prepare/check/run are supported')
	}
}

fn stage() !int {
	mode := os.args[1]
	assert os.args.len == 8
	stage_identity(mode, os.args[2])!
	root := os.abs_path(os.args.last())
	runner := runner368
	source := source368
	mut inputs := {
		compiler: compiler_pin
		@FILE: hash(@FILE)!
		os.executable(): hash(os.executable())!
	}
	mut argv := []string{}
	if mode == 'prepare' {
		path, pin := os.abs_path(os.args[3]), os.args[4]
		pins := replacement_pins(path, pin)!
		inputs[path] = pin
		inputs[runner], inputs[source] = os.args[5], os.args[6]
		argv = [runner, 'prepare', pins['native_root'], pins['native_manifest_sha256'], pins['native_sha256'],
			pins['framework_root'], pins['framework_manifest_sha256'], pins['framework_sha256']]
	} else {
		inputs[runner], inputs[source] = os.args[3], os.args[4]
		lp := repo + '/build/android-maps/maps368/launch-pins.json'
		pp := state + '/maps368-2026-10-26/prelaunch-sha256.json'
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

fn build_command(root string, label string, argv []string) !string {
	started := time.utc().str()
	program_pin := hash(argv[0])!
	r := os.exec(argv)
	os.write_file(root + '/' + label + '.log', r.output)!
	write_json(root + '/' + label + '.json', {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
		'program_sha256_before': json2.Any(program_pin)
		'program_sha256_after': json2.Any(hash(argv[0])!)
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VTMP': json2.Any(os.getenv('VTMP'))
	})!
	assert program_pin == hash(argv[0])! && r.exit_code == 0, r.output
	return r.output
}

fn build_closure(root string, label string, source string) !map[string]string {
	listing := build_command(root, label, [compiler, '-print-v-files', '-nocache', '-cc', 'cc', source])!
	mut files := map[string]string{}
	for path in listing.split_into_lines().map(it.trim_space()).filter(it.ends_with('.v')) {
		assert path.starts_with('/') && path !in files
		files[path] = hash(path)!
	}
	assert files.len > 10
	write_json(root + '/' + label + '-hashes.json', files)!
	return files
}

fn build(root string, output string) ! {
	assert os.dir(root) == state && os.real_path(state) == state
	assert os.dir(output) == repo + '/build/android-maps'
	selftest := root + '-selftest'
	for path in [root, output, selftest] {
		assert !os.exists(path) && !os.is_link(path), 'fresh build destination required: ' + path
	}
	require_pin(compiler, compiler_pin)!
	input_pin := hash(@FILE)!
	os.mkdir(root)!
	os.cp(@FILE, root + '/receipt.v')!
	os.cp(os.executable(), root + '/bootstrap')!
	os.cp(compiler, root + '/v_old276')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', root + '/generated-c', true)
	os.mkdir(root + '/generated-c')!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	build_command(root, 'disk-before', ['/bin/df', '-k', state])!
	before := build_closure(root, 'closure-before', root + '/receipt.v')!
	for path, pin in before {
		retained_path := root + '/closure/' + path.trim_left('/')
		os.mkdir_all(os.dir(retained_path))!
		os.cp(path, retained_path)!
		require_pin(retained_path, pin)!
	}
	build_command(root, 'recorded-build', [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc,
		'-o', output, root + '/receipt.v'])!
	after := build_closure(root, 'closure-after', root + '/receipt.v')!
	assert before == after
	for path, pin in before { require_pin(root + '/closure/' + path.trim_left('/'), pin)! }
	require_pin(@FILE, input_pin)!
	require_pin(root + '/receipt.v', input_pin)!
	require_pin(compiler, compiler_pin)!
	require_pin(cc, cc_pin)!
	os.cp(output, root + '/receipt-tool')!
	build_command(root, 'self-test', [output, 'self-test', selftest])!
	write_json(root + '/outputs.json', {
		'wrapper_source_sha256': json2.Any(input_pin)
		'wrapper_binary_sha256': json2.Any(hash(output)!)
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_path': json2.Any(cc)
		'cc_sha256': json2.Any(cc_pin)
		'closure_before_after_equal': json2.Any(before == after)
		'closure_files': json2.Any(before.len)
		'selftest_root': json2.Any(selftest)
		'selftest_manifest_sha256': json2.Any(hash(selftest + '/sha256.json')!)
		'scope': json2.Any('Recorded receipt wrapper build and host self-tests only; no guest, generation or replay stage.')
	})!
	seal(root)!
	println('MAPS368-REPLAY-RECEIPT-BUILD-PASS')
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
	if os.args.len == 2 && os.args[1] == '--exit-seven' { exit(7) }
	if os.args.len == 4 && os.args[1] == 'build' {
		build(os.abs_path(os.args[2]), os.abs_path(os.args[3])) or { panic(err) }
		return
	}
	if os.args.len == 3 && os.args[1] == 'self-test' {
		self_test(os.abs_path(os.args[2])) or { panic(err) }
		return
	}
	assert os.args.len == 8, 'usage: build ROOT OUTPUT | self-test ROOT | prepare 368 PINS_JSON PINS_SHA RUNNER_SHA SOURCE_SHA ROOT | check|run 368 RUNNER_SHA SOURCE_SHA LAUNCH_SHA PRELAUNCH_SHA ROOT'
	exit(stage() or { panic(err) })
}
