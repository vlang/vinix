// SPDX-License-Identifier: GPL-2.0-or-later
// Metadata mutations keep all actual inputs present, exercising semantic checks.
module main

import crypto.sha256
import json2
import os

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn read_map(path string) !map[string]string { return json2.decode[map[string]string](os.read_file(path)!)! }

fn main() {
	$if prod { panic('requires live assertions; compile without -prod') }
	if os.args.len != 4 { panic('usage: maps-clean-launcher-negative BUNDLE MANIFEST_PIN FRESH_EXTERNAL_OUTPUT') }
	bundle, pinned, output := os.args[1], os.args[2], os.args[3]
	assert hash(bundle + '/sha256.json')! == pinned
	assert os.is_abs_path(output) && !os.exists(output) && !os.is_link(output)
	assert os.real_path(os.dir(output)) != os.real_path(os.getwd())
	assert !os.real_path(os.dir(output)).starts_with(os.real_path(os.getwd()) + '/')
	os.mkdir_all(output)!
	mut receipts := map[string]json2.Any{}
	for name, expected_error in {'missing-input': 'build closure length differs', 'changed-argv': 'unexpected launcher compile argv'} {
		root := output + '/' + name
		copy := os.exec(['cp', '-c', '-R', '-P', bundle, root])
		assert copy.exit_code == 0, copy.output
		mut manifest := read_map(root + '/sha256.json')!
		if name == 'missing-input' {
			mut inputs := read_map(root + '/input-sha256.json')!
			matches := inputs.keys().filter(it.ends_with('/libc.a'))
			assert matches.len == 1
			inputs.delete(matches[0])
			write_json(root + '/input-sha256.json', inputs)!
			manifest['input-sha256.json'] = hash(root + '/input-sha256.json')!
		} else {
			for suffix in ['-before.json', '-receipt.json'] {
				file := 'run-android-calculator' + suffix
				mut receipt := json2.decode[map[string]json2.Any](os.read_file(root + '/' + file)!)!
				mut argv := receipt['argv']!.as_array().map(it.str())
				index := argv.index('arm64')
				assert index > 0
				argv[index] = 'x86_64'
				receipt['argv'] = json2.Any(argv)
				write_json(root + '/' + file, receipt)!
				manifest[file] = hash(root + '/' + file)!
			}
		}
		write_json(root + '/sha256.json', manifest)!
		argv := [bundle + '/builder', 'check', root]
		result := os.exec(argv)
		os.write_file(output + '/' + name + '.log', result.output)!
		assert result.exit_code != 0 && result.output.contains(expected_error), result.output
		receipts[name] = json2.decode[json2.Any](json2.encode({'argv': json2.Any(argv),
			'exit_code': json2.Any(result.exit_code), 'expected_error': json2.Any(expected_error),
			'mutant_manifest_sha256': json2.Any(hash(root + '/sha256.json')!),
			'log_sha256': json2.Any(hash(output + '/' + name + '.log')!)}))!
	}
	os.cp(@FILE, output + '/maps-clean-launcher-negative.v')!
	write_json(output + '/receipt.json', {'original_manifest_sha256': json2.Any(pinned),
		'checker_sha256': json2.Any(hash(bundle + '/builder')!), 'test_source_sha256': json2.Any(hash(@FILE)!),
		'cases': json2.decode[json2.Any](json2.encode(receipts))!})!
	println('MAPS CLEAN LAUNCHER NEGATIVE PASS missing consumed input and coherently changed argv rejected')
}
