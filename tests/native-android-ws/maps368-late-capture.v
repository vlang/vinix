// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the failed capture recorded after Maps368 copied its canonical results.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android'
const raw = repo + '/build/android-maps/attempt368/google-maps'
const canonical = state + '/maps368-2026-10-26'
const retained = canonical + '/results/attempt368/google-maps'
const output = state + '/maps368-late-capture-2026-10-26'
const command = 'command-50987-1792982360068093000-250791'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn inputs() map[string]string {
	return {
		canonical + '/sha256.json': '55a87064ab2a9706ae42f09afee79dcf141e9be69edc240de75750bd32735c3a'
		retained + '/interaction.log': '93474f99987b9a8bc91ede77daa94d627d5bc47adf4f16035966f203d674b1cc'
		raw + '/interaction.log': 'daca519d1594a9b917e0db971db16508d26326d9b1efd4fefbf7ec96dc4ef147'
		raw + '/' + command + '.stdout.log': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
		raw + '/' + command + '.stderr.log': '7833838098dff21a62433384c486ade9ca1da78ee9f7995fa051640e4a6db5e4'
	}
}
fn qualify() ! {
	for path, pin in inputs() {
		assert os.real_path(path) == path && !os.is_link(path)
		assert os.lstat(path)!.get_filetype() == .regular && hash(path)! == pin
	}
	for extension in ['stdout.log', 'stderr.log'] {
		assert !os.exists(retained + '/' + command + '.' + extension)
	}
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1 && os.getwd() == repo
	assert os.real_path(state) == state
	assert !os.exists(output) && !os.is_link(output), 'fresh external output required'
	qualify()!
	original := os.read_file(retained + '/interaction.log')!
	complete := os.read_file(raw + '/interaction.log')!
	assert original.len == 11032 && complete.len == 11883
	assert complete.starts_with(original)
	late := complete[original.len..]
	assert late.starts_with('2026-10-26 02:39:20 UTC BEGIN ')
	assert late.count('BEGIN ') == 1 && late.count('END exit=1 timed_out=false') == 1
	assert late.contains("'screenshot'") && late.contains("'" + raw + "/oasis-selected.png'")
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
	qualify()!
	assert hash(@FILE)! == tool_source && hash(os.executable())! == tool_binary
	assert hash(output + '/collector.v')! == tool_source && hash(output + '/collector')! == tool_binary
	mut record := map[string]json2.Any{}
	for path, pin in inputs() { record[path] = json2.Any(pin) }
	os.write_file(output + '/receipt.json', json2.encode({
		'captured_utc': json2.Any(time.utc().str())
		'cwd': json2.Any(os.getwd())
		'input_pins_before_and_after': json2.Any(record)
		'canonical_interaction_bytes': json2.Any(original.len)
		'raw_interaction_bytes': json2.Any(complete.len)
		'late_interaction_bytes': json2.Any(late.len)
		'recorded_capture_exit_code': json2.Any(1)
		'collector_source_sha256': json2.Any(tool_source)
		'collector_binary_sha256': json2.Any(tool_binary)
		'scope': json2.Any('Preserve the already recorded 02:39:20 failed QMP screenshot command and logs separately. No command rerun, new screenshot, or canonical evidence change.')
	}, prettify: true) + '\n')!
	mut manifest := map[string]string{}
	for name in os.ls(output)! {
		assert os.lstat(output + '/' + name)!.get_filetype() == .regular
		manifest[name] = hash(output + '/' + name)!
	}
	os.write_file(output + '/sha256.json', json2.encode(manifest, prettify: true) + '\n')!
	println('MAPS368-LATE-CAPTURE-PRESERVED manifest=' + hash(output + '/sha256.json')!)
}
