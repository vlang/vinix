// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the failed capture recorded after Maps370 copied its canonical results.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const raw = repo + '/build/android-maps/attempt370/google-maps'
const canonical = state + '/maps370-2026-10-26'
const retained = canonical + '/results/attempt370/google-maps'
const output = state + '/maps370-late-capture-2026-10-26'
const command = 'command-88662-1792986123285236000-43750'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn inputs(pin string) !map[string]string {
	mut result := map[string]string{}
	for path in [canonical + '/sha256.json', retained + '/interaction.log',
		raw + '/interaction.log', raw + '/' + command + '.stdout.log',
		raw + '/' + command + '.stderr.log'] {
		assert os.real_path(path) == path && !os.is_link(path)
		assert os.lstat(path)!.get_filetype() == .regular
		result[path] = hash(path)!
	}
	assert result[canonical + '/sha256.json'] == pin
	inventory := json2.decode[map[string]string](os.read_file(canonical + '/sha256.json')!)!
	assert inventory['results/attempt370/google-maps/interaction.log'] == result[retained + '/interaction.log']
	assert result[raw + '/' + command + '.stdout.log'] == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
	assert result[raw + '/' + command + '.stderr.log'] == '7833838098dff21a62433384c486ade9ca1da78ee9f7995fa051640e4a6db5e4'
	for extension in ['stdout.log', 'stderr.log'] {
		assert !os.exists(retained + '/' + command + '.' + extension)
	}
	assert !os.exists(raw + '/paris-preview-next.png') && !os.exists(retained + '/paris-preview-next.png')
	return result
}

fn collect(pin string) ! {
	assert !os.exists(output) && !os.is_link(output), 'fresh external output required'
	before := inputs(pin)!
	original := os.read_file(retained + '/interaction.log')!
	complete := os.read_file(raw + '/interaction.log')!
	assert original.len == 19176 && complete.len == 20027
	assert complete.starts_with(original)
	late := complete[original.len..]
	assert late.starts_with('2026-10-26 03:42:03 UTC BEGIN ')
	assert late.count('BEGIN ') == 1 && late.count('END exit=1 timed_out=false output_drain_capped=false') == 1
	assert late.contains("'screenshot'") && late.contains("'" + raw + "/paris-preview-next.png'")
	for extension in ['stdout.log', 'stderr.log'] {
		assert late.count(raw + '/' + command + '.' + extension) == 2
	}
	assert os.read_file(raw + '/' + command + '.stderr.log')! == 'No such file or directory\n'
	tool_source, tool_binary := hash(@FILE)!, hash(os.executable())!
	os.mkdir(output)!
	os.cp(@FILE, output + '/collector.v')!
	os.cp(os.executable(), output + '/collector')!
	os.cp(raw + '/interaction.log', output + '/raw-interaction.log')!
	os.cp(retained + '/interaction.log', output + '/canonical-interaction.log')!
	os.write_file(output + '/late-interaction.log', late)!
	for extension in ['stdout.log', 'stderr.log'] {
		os.cp(raw + '/' + command + '.' + extension, output + '/' + command + '.' + extension)!
	}
	assert inputs(pin)! == before
	assert hash(@FILE)! == tool_source && hash(os.executable())! == tool_binary
	assert hash(output + '/collector.v')! == tool_source && hash(output + '/collector')! == tool_binary
	mut record := map[string]json2.Any{}
	for path, value in before { record[path] = json2.Any(value) }
	os.write_file(output + '/receipt.json', json2.encode({
		'captured_utc': json2.Any(time.utc().str())
		'cwd': json2.Any(os.getwd())
		'argv': json2.Any(os.args)
		'input_pins_before_and_after': json2.Any(record)
		'canonical_interaction_bytes': json2.Any(original.len)
		'raw_interaction_bytes': json2.Any(complete.len)
		'late_interaction_bytes': json2.Any(late.len)
		'recorded_capture_exit_code': json2.Any(1)
		'collector_source_sha256': json2.Any(tool_source)
		'collector_binary_sha256': json2.Any(tool_binary)
		'scope': json2.Any('Preserve the already recorded 03:42:03 failed QMP screenshot command and logs separately. No command rerun, new screenshot, or canonical evidence change.')
	}, prettify: true) + '\n')!
	mut manifest := map[string]string{}
	for name in os.ls(output)! {
		assert os.lstat(output + '/' + name)!.get_filetype() == .regular
		manifest[name] = hash(output + '/' + name)!
	}
	os.write_file(output + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('MAPS370-LATE-CAPTURE-PRESERVED manifest=' + hash(output + '/sha256.json')!)
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.getwd() == repo && os.real_path(state) == state
	assert os.args.len in [2, 3]
	pin := os.args.last()
	assert pin.len == 64 && pin.bytes().all(it in '0123456789abcdef'.bytes())
	if os.args.len == 3 {
		assert os.args[1] == 'collect'
		collect(pin)!
		return
	}
	for suffix in ['-before.json', '-command.json', '.log'] { assert !os.exists(output + suffix) }
	argv := [os.executable(), 'collect', pin]
	mut receipt := {'argv': json2.Any(argv), 'cwd': json2.Any(os.getwd()),
		'started_utc': json2.Any(time.utc().str()), 'source_sha256': json2.Any(hash(@FILE)!),
		'executable_sha256_before': json2.Any(hash(os.executable())!)}
	os.write_file(output + '-before.json', json2.encode(receipt, prettify: true) + '\n')!
	result := os.exec(argv)
	os.write_file(output + '.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	receipt['executable_sha256_after'] = hash(os.executable())!
	receipt['output_sha256'] = hash(output + '.log')!
	os.write_file(output + '-command.json', json2.encode(receipt, prettify: true) + '\n')!
	print(result.output)
	assert result.exit_code == 0, result.output
	assert receipt['executable_sha256_after']!.str() == receipt['executable_sha256_before']!.str()
}
