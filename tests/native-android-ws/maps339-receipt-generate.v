// SPDX-License-Identifier: GPL-2.0-or-later
// Derive the339 preparation envelope without changing the historical332 tool.
module main

import crypto.sha256
import json2
import os
import time

const state = '/Users/alex/.local/state/vinix/android/'
const original = state + 'maps-replay-receipt332-build-2026-10-25/receipt.v'
const original_pin = 'ef464fa8ea251493bc2e9a907a0635e2412074a6e91a5837f9bf11d7c512aee3'
const root = state + 'maps339-receipt-build-2026-10-25'
const source = 'tests/native-android-ws/maps339-receipt.v'
const binary = 'build/android-maps/maps339-receipt'
const compiler = 'build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn once(text string, before string, after string) string {
	assert text.count(before) == 1, before
	return text.replace(before, after)
}
fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 1 && hash(original)! == original_pin && hash(compiler)! == compiler_pin
	for path in [root, source, binary] { assert !os.exists(path) && !os.is_link(path), path }
	mut text := os.read_file(original)!
	text = once(text, "assert os.base(root).ends_with('-' + label + '-build-2026-10-25')", "if label == 'framework' {\n\t\t\tassert root == state + '/layout-parent-dispatch336-v3-2026-10-25'\n\t\t\tassert pins['framework_manifest_sha256'] == 'a583f89a37bc7d59a275fef01396a864efe04915dd070227631599058ae46762'\n\t\t\tassert pins['framework_sha256'] == 'c9d7d096d763730ed9f3eed1735272ef11a65e88da3d297731f832a434c6c788'\n\t\t} else {\n\t\t\tassert root == state + '/layout-request332-native-build-2026-10-25'\n\t\t\tassert pins['native_manifest_sha256'] == '40b1099c58abe7fb3729ee2b48fd13d171f9ebaf70d1b83e26b5ad9f93aac163'\n\t\t\tassert pins['native_sha256'] == '2231ee3def626a72119cd80d646966ec5ba2fa6cd7dd74a790fe9bcb9db5869b'\n\t\t}")
	text = once(text, "assert mode in ['generate', 'prepare', 'check', 'run']", "assert mode == 'prepare', 'this339 derivative records preparation only'")
	text = once(text, "assert number.int() >= 332 && number.int().str() == number, 'canonical fresh attempt332 or later required'", "assert number == '339', 'exact attempt339 required'")
	os.mkdir(root)!
	os.write_file(source, text)!
	os.cp(source, root + '/receipt.v')!
	os.cp(original, root + '/receipt332-input.v')!
	os.cp(@FILE, root + '/generator.v')!
	os.cp(os.executable(), root + '/generator')!
	os.cp(compiler, root + '/v_old276')!
	os.setenv('VROOT', '/Users/alex/code/v', true)
	os.setenv('COPYFILE_DISABLE', '1', true)
	os.mkdir(root + '/generated-c')!
	os.setenv('VTMP', root + '/generated-c', true)
	listing_argv := [compiler, '-print-v-files', source]
	listing_started := time.utc().str()
	listing := os.exec(listing_argv)
	os.write_file(root + '/closure-v-files.txt', listing.output)!
	write_json(root + '/closure-receipt.json', {
		'argv': json2.Any(listing_argv)
		'started_utc': json2.Any(listing_started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(listing.exit_code)
		'compiler_sha256': json2.Any(compiler_pin)
	})!
	assert listing.exit_code == 0, listing.output
	mut before := map[string]string{}
	for path in listing.output.split_into_lines().filter(it.ends_with('.v')) {
		before[path] = hash(path)!
		dest := root + '/closure/' + os.abs_path(path).trim_left('/')
		os.mkdir_all(os.dir(dest))!
		os.cp(path, dest)!
	}
	assert before.len >= 10
	write_json(root + '/closure-before.json', before)!
	cc := os.find_abs_path_of_executable('cc')!
	cc_pin := hash(cc)!
	argv := [compiler, '-nocache', '-keepc', '-showcc', '-cc', cc, '-cflags', '-O2', '-o', binary, source]
	mut receipt := {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(time.utc().str())
		'VROOT': json2.Any(os.getenv('VROOT'))
		'compiler_sha256': json2.Any(compiler_pin)
		'cc_path': json2.Any(cc)
		'cc_sha256': json2.Any(cc_pin)
		'source_sha256': json2.Any(hash(source)!)
		'original_source_sha256': json2.Any(original_pin)
		'closure_before_sha256': json2.Any(hash(root + '/closure-before.json')!)
	}
	write_json(root + '/build-before.json', receipt)!
	result := os.exec(argv)
	os.write_file(root + '/build.log', result.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = result.exit_code
	mut after := map[string]string{}
	for path, pin in before {
		after[path] = hash(path)!
		assert after[path] == pin && hash(root + '/closure/' + os.abs_path(path).trim_left('/'))! == pin
	}
	write_json(root + '/closure-after.json', after)!
	receipt['closure_after_sha256'] = hash(root + '/closure-after.json')!
	assert hash(compiler)! == compiler_pin && hash(cc)! == cc_pin
	if result.exit_code == 0 {
		receipt['binary_sha256'] = hash(binary)!
		os.cp(binary, root + '/receipt')!
	}
	write_json(root + '/build-receipt.json', receipt)!
	assert result.exit_code == 0, result.output
	mut files := map[string]string{}
	for path in os.walk_ext(root, '') { if os.is_file(path) { files[path.all_after(root + '/')] = hash(path)! } }
	write_json(root + '/sha256.json', files)!
	println('MAPS339-RECEIPT-BUILD source=' + hash(source)! + ' binary=' + hash(binary)! + ' seal=' + hash(root + '/sha256.json')!)
}
