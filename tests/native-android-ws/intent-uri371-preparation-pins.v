// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded read-only pin capture after the recorded prepare action completes.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/intent-uri371-fixture-2026-10-26'
const output = '/Users/alex/.local/state/vinix/android/intent-uri371-preparation-pins-2026-10-26'
const action = '/Users/alex/.local/state/vinix/android/intent-uri371-fixture-prepare-2026-10-26'
const action_peer = '/Users/alex/.local/state/vinix/android/intent-uri371-action-recorder-peer-readback-2026-10-26/receipt.json'
const source_pin = 'e6de49d024b706ffc34f6169b3a1a31f725708d3bbfd7425657513d9c6d2e707'
const apk_pin = '710eeaa6cc2b5f0d5ddd0fde5b3b62e71e844220c20584846f121dbbe13eec85'

fn hash(path string) !string {
	assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn main() {
	assert os.args.len == 1 && !os.exists(output) && !os.is_link(output)
	started := time.utc().str()
	command := json2.decode[map[string]json2.Any](os.read_file(action + '-command.json')!)!
	assert command['exit_code']!.int() == 0
	assert command['argv']!.as_array()[1].str() == 'prepare'
	assert command['executable_sha256_before']! == command['executable_sha256_after']!
	assert command['executable_sha256_before']!.str() == '4c192b967eb30a27caa5fa08d5d5c0ff15e4136e89134390d91c7704ef4488b6'
	assert command['output_sha256']!.str() == hash(action + '.log')!
	assert hash(action_peer)! == '95eb1d7041786b34827b70b238cc11cd4bddb00fed5a95d58f50e704a0d7569f'
	peer := json2.decode[map[string]json2.Any](os.read_file(action_peer)!)!
	assert peer['exit_code']!.int() == 0 && peer['closure_count']!.int() == 270
	assert peer['recorded_commands_checked']!.int() == 4
	assert !peer['guest_invoked']!.bool() && !peer['original290_invoked']!.bool()
	pins := json2.decode[map[string]string](os.read_file(state + '/build-pins.json')!)!
	shared := json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
	assert hash(state + '/tools/checked-runner')! == pins['runner']!
	assert hash(state + '/apk/probe.apk')! == pins['apk']! && pins['apk']! == apk_pin
	assert hash(state + '/source/intent-uri371-run.v')! == source_pin
	assert hash(state + '/frozen/vroot/intent-uri371-run.v')! == source_pin
	for key in ['build-pins.json', 'tools/checked-runner', 'apk/probe.apk',
		'source/intent-uri371-run.v', 'frozen/vroot/intent-uri371-run.v'] {
		assert hash(state + '/' + key)! == shared[key]!, key
	}
	mut selected := map[string]string{}
	for key in ['build-pins.json', 'shared-inputs.json', 'tools/checked-runner',
		'source/intent-uri371-run.v', 'apk/probe.apk', 'old-semantic-check.json',
		'control-origin.json', 'control-sha256.json', 'control-origin-inventory.json',
		'control-failure-receipt.json'] {
		selected[key] = hash(state + '/' + key)!
	}
	for suffix in ['-before.json', '-command.json', '.log'] {
		selected[action + suffix] = hash(action + suffix)!
	}
	selected[action_peer] = hash(action_peer)!
	os.mkdir(output)!
	os.cp(@FILE, output + '/reader.v')!
	os.cp(os.executable(), output + '/reader')!
	os.write_file(output + '/pins.json', json2.encode(selected, prettify: true) + '\n')!
	os.write_file(output + '/receipt.json', json2.encode({
		'argv': json2.Any(os.args), 'cwd': json2.Any(os.getwd()),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'original_root': json2.Any(state), 'pins_sha256': json2.Any(hash(output + '/pins.json')!),
		'reader_source_sha256': json2.Any(hash(output + '/reader.v')!),
		'reader_binary_sha256': json2.Any(hash(output + '/reader')!),
		'status': json2.Any('bounded-preparation-pin-capture-pass'),
		'scope': json2.Any('Read-only selected preparation pins and actual prepare exit0. No guest, full inventory, original290 audit or runtime semantic validation.')
	}, prettify: true) + '\n')!
	println('INTENT371-PREPARE-PINS-PASS runner=' + pins['runner']! +
		' shared=' + selected['shared-inputs.json']! + ' build=' + selected['build-pins.json']! +
		' action-peer=' + selected[action_peer]!)
}
