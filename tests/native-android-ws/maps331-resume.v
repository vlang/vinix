// SPDX-License-Identifier: GPL-2.0-or-later
// Resume Maps331 generation/preparation, or read back a complete receipt bundle.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const generator = repo + '/build/android-maps/maps-replay-generate314'
const pins = state + '/maps331-replacement-build-pins-2026-10-25.json'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const runner = repo + '/build/android-maps/maps331-run-recorded'
const runner_source = state + '/maps331-generation-2026-10-25/maps331-run.v'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, data T) ! { os.write_file(path, json2.encode(data, prettify: true) + '\n')! }
fn inventory(root string, relative string, mut files map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		assert !os.is_link(path), path
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut files)! }
			.regular { files[key] = hash(path)! }
			else { panic('nonregular evidence entry: ' + path) }
		}
	}
}

fn verify_receipt(root string, pin string, output string) ! {
	assert os.dir(root) == state && os.is_dir(root) && !os.is_link(root)
	assert pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
	assert os.dir(output) == state && !os.exists(output) && !os.is_link(output)
	started := time.utc().str()
	assert hash(root + '/sha256.json')! == pin
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	assert expected == actual, 'complete receipt inventory differs'
	os.mkdir(output)!
	os.cp(@FILE, output + '/resume.v')!
	write_json(output + '/readback.json', {
		'argv': json2.Any(os.args)
		'bundle_root': json2.Any(root)
		'manifest_sha256': json2.Any(pin)
		'files_checked': json2.Any(actual.len)
		'pass': json2.Any(true)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'checker_source_sha256': json2.Any(hash(@FILE)!)
		'checker_binary_sha256': json2.Any(hash(os.executable())!)
	})!
	mut receipt_files := map[string]string{}
	inventory(output, '', mut receipt_files)!
	write_json(output + '/sha256.json', receipt_files)!
	println('MAPS331-RECEIPT-READBACK-PASS entries=' + actual.len.str() + ' seal=' + hash(output + '/sha256.json')!)
}

fn main() {
	if os.args.len == 5 && os.args[1] == '--verify' {
		verify_receipt(os.abs_path(os.args[2]), os.args[3], os.abs_path(os.args[4])) or { panic(err) }
		return
	}
	assert os.args.len in [2, 3], 'usage: maps331-resume FRESH_EXTERNAL_RECEIPT_ROOT [prepare]'
	prepare := os.args.len == 3
	if prepare { assert os.args[2] == 'prepare' }
	assert os.getwd() == repo
	root := os.abs_path(os.args[1])
	assert os.dir(root) == state && !os.exists(root) && !os.is_link(root), 'fresh external receipt root required'
	assert hash(generator)! == '75b69d07fdf23401b07ee8cad36d7ba2a47dfd5e48c13660c4307f91e882b453'
	assert hash(compiler)! == '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
	assert hash(pins)! == 'f83ba17c15d0715e5d3d268056a72e214163682fb2a1372e2a8263cdc4cf126d'
	assert hash(repo + '/tests/native-android-ws/maps-replay-generate.v')! == '39b9d763de6c5685021731ec877a276d2110f8cd457c4ff6bcf8bc1e399b6d84'
	assert hash(repo + '/tests/native-android-ws/maps298-run.v')! == '5d220b06590bc0823f12c6d5071dc60af51a9dc284a383afb77cb907c1f17ed1'
	os.mkdir_all(root)!
	os.cp(@FILE, root + '/resume.v')!
	os.cp(pins, root + '/replacement-build-pins.json')!
	mut argv := [generator, '331', pins, '--minimum-free-mib=1536']
	if prepare {
		assert hash(runner)! == '26eb66be3ffb5a70ce82b27ff57c53823e667e38d8851aeb2b6b108df8903bea'
		assert hash(runner_source)! == '074fe84008f0e2443b09f111606354ea16b4268685d210ae5f841220f13f5e4d'
		selected := json2.decode[map[string]string](os.read_file(pins)!)!
		argv = [runner, 'prepare', selected['native_root'], selected['native_manifest_sha256'],
			selected['native_sha256'], selected['framework_root'], selected['framework_manifest_sha256'],
			selected['framework_sha256']]
	}
	mode := if prepare { 'prepare' } else { 'generator' }
	mut environment := os.environ()
	mut removed := []string{}
	for key in environment.keys() {
		if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' {
			removed << key
			environment.delete(key)
		}
	}
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'program_sha256_before': json2.Any(hash(argv[0])!)
		'compiler_sha256': json2.Any(hash(compiler)!)
		'wrapper_source_sha256': json2.Any(hash(@FILE)!)
		'wrapper_binary_sha256': json2.Any(hash(os.executable())!)
		'replacement_build_pins_sha256': json2.Any(hash(pins)!)
		'removed_environment_keys': json2.Any(removed)
		'scope': json2.Any('One pinned ' + mode + ' invocation only; no guest launch')
	}
	if prepare { receipt['runner_source_sha256'] = hash(runner_source)! }
	os.write_file(root + '/disk-before.txt', os.exec(['/bin/df', '-k', state]).output)!
	write_json(root + '/started.json', receipt)!
	mut stdout := os.create(root + '/' + mode + '.stdout.log')!
	mut stderr := os.create(root + '/' + mode + '.stderr.log')!
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
		a := child.stdout_read()
		b := child.stderr_read()
		stdout.write_string(a)!
		stderr.write_string(b)!
		if a == '' && b == '' { break }
	}
	stdout.close()
	stderr.close()
	receipt['exit_code'] = json2.Any(child.code)
	receipt['completed_utc'] = time.utc().str()
	receipt['program_sha256_after'] = json2.Any(hash(argv[0])!)
	assert receipt['program_sha256_before']! == receipt['program_sha256_after']!
	write_json(root + '/receipt.json', receipt)!
	os.write_file(root + '/disk-after.txt', os.exec(['/bin/df', '-k', state]).output)!
	mut files := map[string]string{}
	inventory(root, '', mut files)!
	write_json(root + '/sha256.json', files)!
	println('MAPS331-RESUME ' + mode + '_exit=' + child.code.str() + ' manifest=' + hash(root + '/sha256.json')!)
	exit(child.code)
}
