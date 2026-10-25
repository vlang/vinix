// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve Maps314 commands attempted after its unchanged observation window.
module main

import crypto.sha256
import json2
import os
import time

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn inventory(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		info := os.lstat(path)!
		match info.get_filetype() {
			.regular { entries[key] = hash(path)! }
			.directory {
				entries[key] = 'directory'
				inventory(root, key, mut entries)!
			}
			else { return error('ordinary supplemental files required: ' + path) }
		}
		entries['@mode:' + key] = (info.mode & 0o7777).str()
	}
}

fn copy_checked(input string, output string) ! {
	assert os.lstat(input)!.get_filetype() == .regular
	assert !os.exists(output) && !os.is_link(output)
	os.cp(input, output)!
	assert hash(input)! == hash(output)!
}

fn verify(root string, pin string) !int {
	assert hash(root + '/sha256.json')! == pin
	expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	actual.delete('sha256.json')
	actual.delete('@mode:sha256.json')
	assert actual.len == expected.len
	for key, value in expected {
		assert actual[key]! == value
	}
	return actual.len
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	if os.args.len == 4 && os.args[1] == 'verify' {
		count := verify(os.args[2], os.args[3])!
		println('MAPS314-POST-STOP-READBACK-PASS typed=' + count.str())
		return
	}
	assert os.args.len == 1
	sealed := '/Users/alex/.local/state/vinix/android/maps314-2026-10-25'
	working := '/Users/alex/code/vinix/build/android-maps/attempt314/google-maps'
	root := '/Users/alex/.local/state/vinix/android/maps314-post-stop-supplement-v2-2026-10-25'
	receipt := root + '-receipt.json'
	manifest_pin := '36f69cfdcf35e81eb853e6a16ad31e31998e70c69a04d9b69d88ad5cdc2d73b7'
	assert hash(sealed + '/sha256.json')! == manifest_pin
	sealed_log := sealed + '/results/attempt314/google-maps/interaction.log'
	original := json2.decode[map[string]string](os.read_file(sealed + '/sha256.json')!)!
	assert hash(sealed_log)! == original['results/attempt314/google-maps/interaction.log']!
	sealed_text := os.read_file(sealed_log)!
	extended_text := os.read_file(working + '/interaction.log')!
	assert extended_text.starts_with(sealed_text), 'exact sealed interaction prefix required'
	suffix := extended_text[sealed_text.len..]
	assert suffix.trim_space().split_into_lines().len == 4
	assert suffix.count('2026-10-25 09:36:07 UTC BEGIN ') == 2
	assert suffix.count('2026-10-25 09:36:07 UTC END exit=1 ') == 2
	assert !os.exists(working + '/walking-preview-next-immediate.png')
	assert !os.exists(working + '/qmp.sock')
	commands := ['command-54157-1792920967288628000-28958', 'command-54160-1792920967346443000-29958']
	for command in commands {
		for stream in ['stdout', 'stderr'] {
			assert suffix.count(working + '/' + command + '.' + stream + '.log') == 2
		}
		assert os.read_file(working + '/' + command + '.stdout.log')! == ''
		assert os.read_file(working + '/' + command + '.stderr.log')! == 'No such file or directory\n'
	}
	assert !os.exists(root) && !os.is_link(root), 'fresh supplemental root required'
	assert !os.exists(receipt) && !os.is_link(receipt), 'fresh external receipt required'
	os.mkdir(root)!
	copy_checked(sealed + '/sha256.json', root + '/original-sealed-sha256.json')!
	copy_checked(sealed_log, root + '/sealed-interaction.log')!
	copy_checked(working + '/interaction.log', root + '/extended-working-interaction.log')!
	for command in commands {
		for stream in ['stdout', 'stderr'] {
			name := command + '.' + stream + '.log'
			copy_checked(working + '/' + name, root + '/' + name)!
		}
	}
	copy_checked('tests/native-android-ws/maps-post-stop-preserve.v', root + '/preserve.v')!
	copy_checked(os.executable(), root + '/preserve')!
	os.write_file(root + '/post-stop-suffix.log', suffix)!
	mut expected := map[string]string{}
	inventory(root, '', mut expected)!
	os.write_file(root + '/sha256.json', json2.encode(expected, prettify: true) + '\n')!
	pin := hash(root + '/sha256.json')!
	count := verify(root, pin)!
	assert hash(sealed + '/sha256.json')! == manifest_pin
	os.write_file(receipt, json2.encode({
		'completed_utc':               json2.Any(time.utc().str())
		'supplement_root':             json2.Any(root)
		'supplement_manifest_sha256':  json2.Any(pin)
		'typed_entries':               json2.Any(count)
		'sealed_root':                 json2.Any(sealed)
		'sealed_manifest_sha256':      json2.Any(manifest_pin)
		'sealed_interaction_sha256':   json2.Any(hash(sealed_log)!)
		'extended_interaction_sha256': json2.Any(hash(working + '/interaction.log')!)
		'exact_sealed_prefix':         json2.Any(true)
		'failed_commands':             json2.Any(2)
		'walking_next_qualified':      json2.Any(false)
		'walking_previous_qualified':  json2.Any(false)
	}, prettify: true) + '\n')!
	println('MAPS314-POST-STOP-PRESERVATION-PASS manifest=' + pin + ' typed=' + count.str())
}
