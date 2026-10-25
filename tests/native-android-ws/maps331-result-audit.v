// SPDX-License-Identifier: GPL-2.0-or-later
// Retain a repeat readback and the original Maps331 classifier and PNG evidence.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const bundle = state + '/maps331-2026-10-25'
const final_pin = 'f15440a9e0cf8f57b4cf9f1e1a18845c7afe9643840f41c3b1844916a8e80cf7'
const runner = repo + '/build/android-maps/maps331-run-recorded'
const runner_pin = '26eb66be3ffb5a70ce82b27ff57c53823e667e38d8851aeb2b6b108df8903bea'
const runner_source = state + '/maps331-generation-2026-10-25/maps331-run.v'
const runner_source_pin = '074fe84008f0e2443b09f111606354ea16b4268685d210ae5f841220f13f5e4d'
const compiler = repo + '/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const image_prefix = 'results/attempt331/google-maps/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn require_pin(path string, pin string) ! { assert hash(path)! == pin, 'wrong input pin: ' + path }

fn command(root string, label string, argv []string) !string {
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'program_sha256_before': json2.Any(hash(argv[0])!)
		'checker_source_sha256': json2.Any(hash(@FILE)!)
		'checker_binary_sha256': json2.Any(hash(os.executable())!)
	}
	if argv[0] == runner {
		receipt['runner_source_sha256'] = hash(runner_source)!
	}
	write_json(root + '/' + label + '-before.json', receipt)!
	mut stdout := os.create(root + '/' + label + '.stdout.log')!
	mut stderr := os.create(root + '/' + label + '.stderr.log')!
	mut child := os.new_process(argv[0])
	child.set_args(argv[1..])
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
	write_json(root + '/' + label + '.json', receipt)!
	assert receipt['program_sha256_before']! == receipt['program_sha256_after']!
	assert child.code == 0, 'recorded command failed: ' + label
	return os.read_file(root + '/' + label + '.stdout.log')!
}

fn closure(root string, label string) !map[string]string {
	listing := command(root, label, [compiler, '-print-v-files', '-nocache', '-cc', 'cc', root + '/result-audit.v'])!
	mut files := map[string]string{}
	for line in listing.split_into_lines() {
		path := line.trim_space()
		if path.ends_with('.v') {
			assert path.starts_with('/') && path !in files
			files[path] = hash(path)!
		}
	}
	assert files.len > 10
	write_json(root + '/' + label + '-hashes.json', files)!
	return files
}

fn inventory(root string, relative string, mut files map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		assert !os.is_link(path), 'receipt must contain ordinary entries'
		match os.lstat(path)!.get_filetype() {
			.directory { inventory(root, key, mut files)! }
			.regular { files[key] = hash(path)! }
			else { return error('nonregular evidence entry: ' + path) }
		}
	}
}

fn disk_gate(root string, label string) ! {
	r := os.exec(['/bin/df', '-k', state])
	os.write_file(root + '/' + label + '.txt', r.output)!
	assert r.exit_code == 0
	rows := r.output.trim_space().split_into_lines()
	assert rows.len == 2
	fields := rows[1].fields()
	assert fields.len >= 4 && fields[3].u64() >= u64(1536 * 1024), '1536 MiB headroom required before tooling build/readback'
}

fn sealed_file(expected map[string]string, relative string) !string {
	assert relative in expected, 'sealed file missing: ' + relative
	path := bundle + '/' + relative
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	require_pin(path, expected[relative])!
	return path
}

fn be32(bytes []u8) u32 {
	assert bytes.len == 4
	return u32(bytes[0]) << 24 | u32(bytes[1]) << 16 | u32(bytes[2]) << 8 | u32(bytes[3])
}

fn audit(root string, pin string) ! {
	assert os.getwd() == repo && os.dir(root) == state && os.is_dir(root) && !os.is_link(root)
	assert os.executable() == root + '/result-audit' && os.real_path(@FILE) == root + '/result-audit.v'
	assert pin == final_pin && !os.exists(root + '/audit.json') && !os.exists(root + '/sha256.json')
	started := time.utc().str()
	require_pin(bundle + '/sha256.json', pin)!
	require_pin(runner, runner_pin)!
	require_pin(runner_source, runner_source_pin)!
	output := command(root, 'completed-readback', [runner, 'verify', pin])!
	assert output.trim_space() == 'MAPS331-COMPLETED-READBACK-PASS entries=22898'
	expected := json2.decode[map[string]string](os.read_file(bundle + '/sha256.json')!)!
	assert expected.len == 22898
	mut images := []map[string]json2.Any{}
	for name in ['map-after-skip', 'paris-place-settled', 'route-first-result', 'route-preview-retry',
		'walking-route', 'route-options-settled', 'trip-option-toggle'] {
		relative := image_prefix + name + '.png'
		path := sealed_file(expected, relative)!
		mut file := os.open(path)!
		mut header := []u8{len: 24}
		assert file.read(mut header)! == 24
		file.close()
		assert header[..8] == [u8(137), 80, 78, 71, 13, 10, 26, 10]
		assert be32(header[8..12]) == 13 && header[12..16].bytestr() == 'IHDR'
		width, height := be32(header[16..20]), be32(header[20..24])
		assert width == 1024 && height == 768, 'unexpected PNG IHDR dimensions: ' + name
		images << {
			'path': json2.Any(path)
			'sealed_relative_path': json2.Any(relative)
			'sha256': json2.Any(expected[relative])
			'width': json2.Any(width)
			'height': json2.Any(height)
		}
	}
	mut originals := map[string]json2.Any{}
	for relative in ['results/attempt331/results.json', image_prefix + 'observation-before-capture.json'] {
		path := sealed_file(expected, relative)!
		name := os.file_name(path)
		os.cp(path, root + '/original-' + name)!
		require_pin(root + '/original-' + name, expected[relative])!
		originals[relative] = expected[relative]
	}
	observation := json2.decode[map[string]json2.Any](os.read_file(root + '/original-observation-before-capture.json')!)!
	mut classifier := map[string]json2.Any{}
	for key in ['backend_ready', 'failure_markers', 'functional_passed', 'launcher_entered',
		'native_maps_observed', 'observation_elapsed_seconds', 'outcome', 'process_exited',
		'qemu_alive_before_capture', 'startup_timeout_seconds'] {
		assert key in observation
		classifier[key] = observation[key]!
	}
	require_pin(bundle + '/sha256.json', pin)!
	require_pin(runner, runner_pin)!
	require_pin(runner_source, runner_source_pin)!
	write_json(root + '/audit.json', {
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'bundle_root': json2.Any(bundle)
		'manifest_sha256': json2.Any(pin)
		'readback_entries': json2.Any(expected.len)
		'runner_sha256': json2.Any(runner_pin)
		'runner_source_sha256': json2.Any(runner_source_pin)
		'audit_binary_sha256': json2.Any(hash(os.executable())!)
		'audit_source_sha256': json2.Any(hash(@FILE)!)
		'pngs': json2.Any(images)
		'original_json_sha256': json2.Any(originals)
		'classifier_from_original_observation': json2.Any(classifier)
		'classifier_policy': json2.Any('Preserved original JSON bytes; fields copied without rewriting functional_passed or inferring a functional pass.')
		'scope': json2.Any('Read-only repeat of root prior 22898-entry PASS to retain machine receipt; no guest launch or app interaction.')
		'pass': json2.Any(true)
	})!
	println('MAPS331-RESULT-AUDIT-PASS entries=22898 pngs=7 dimensions=1024x768')
}

fn bootstrap(root string, pin string) ! {
	assert os.getwd() == repo && pin == final_pin
	assert os.dir(root) == state && !os.exists(root) && !os.is_link(root), 'fresh external receipt root required'
	require_pin(compiler, compiler_pin)!
	os.mkdir(root)!
	disk_gate(root, 'disk-before-build')!
	os.cp(@FILE, root + '/result-audit.v')!
	os.cp(os.executable(), root + '/bootstrap')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('VTMP', root + '/generated-c', true)
	os.mkdir(root + '/generated-c')!
	before := closure(root, 'v-closure-before')!
	command(root, 'recorded-build', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-o', root + '/result-audit', root + '/result-audit.v'])!
	after := closure(root, 'v-closure-after')!
	assert before == after, 'consumed V sources changed during build'
	require_pin(compiler, compiler_pin)!
	disk_gate(root, 'disk-before-readback')!
	command(root, 'recorded-audit', [root + '/result-audit', '--audit', root, pin])!
	mut files := map[string]string{}
	inventory(root, '', mut files)!
	write_json(root + '/sha256.json', files)!
	println('MAPS331-RESULT-AUDIT-RECORDED seal=' + hash(root + '/sha256.json')!)
}

fn main() {
	assert os.args.len == 4, 'usage: maps331-result-audit --bootstrap|--audit FRESH_EXTERNAL_ROOT EXACT_FINAL_SHA256'
	root, pin := os.abs_path(os.args[2]), os.args[3]
	match os.args[1] {
		'--bootstrap' { bootstrap(root, pin) or { panic(err) } }
		'--audit' { audit(root, pin) or { panic(err) } }
		else { panic('unknown mode') }
	}
}
