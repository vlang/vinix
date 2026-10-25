// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the actual preparer tar parser and its authoritative Maps283 input.
module main

import crypto.sha256
import json2
import os
import time

const root = '/Users/alex/.local/state/vinix/android/maps285-input-tests-final4-2026-10-25'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn quote(value string) string { return "'" + value.replace("'", r"'\''") + "'" }
fn write_json[T](path string, value T) ! { os.write_file(path, json2.encode(value, prettify: true) + '\n')! }
fn put(mut bytes []u8, offset int, value string) { for i, byte in value.bytes() { bytes[offset + i] = byte } }

fn header(path string, kind u8, size int, link string, mode string) []u8 {
	mut result := []u8{len: 512}
	put(mut result, 0, path)
	put(mut result, 100, mode)
	put(mut result, 124, '${size:011o}')
	put(mut result, 148, '        ')
	result[156] = kind
	put(mut result, 157, link)
	put(mut result, 257, 'ustar')
	mut sum := 0
	for byte in result { sum += int(byte) }
	put(mut result, 148, '${sum:06o}\x00 ')
	return result
}

fn tar_case(binary string, name string, bytes []u8, accepted bool) !string {
	input := root + '/' + name + '.tar'
	os.write_file_array(input, bytes)!
	argv := ['/bin/zsh', '-c', quote(binary) + ' --tar-tree-stdin < ' + quote(input)]
	mut receipt := {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()),
		'binary_sha256': json2.Any(hash(binary)!), 'input_sha256': json2.Any(hash(input)!), 'expected_accept': json2.Any(accepted)}
	write_json(root + '/' + name + '-before.json', receipt)!
	r := os.exec(argv)
	os.write_file(root + '/' + name + '.log', r.output)!
	receipt['completed_utc'] = time.utc().str()
	receipt['exit_code'] = r.exit_code
	receipt['output_sha256'] = hash(root + '/' + name + '.log')!
	write_json(root + '/' + name + '-receipt.json', receipt)!
	assert (r.exit_code == 0) == accepted, name + ': ' + r.output
	return r.output
}

fn tree(path string, relative string, mut entries map[string]string) ! {
	for name in os.ls(path + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		item := path + '/' + key
		stat := os.lstat(item)!
		entries['@mode:' + key] = (stat.mode & 0o7777).str()
		match stat.get_filetype() {
			.directory { entries[key] = 'directory'; tree(path, key, mut entries)! }
			.regular { entries[key] = hash(item)! }
			.symbolic_link { entries[key] = 'symlink:' + os.readlink(item)! }
			else { return error('unexpected module entry: ' + key) }
		}
	}
}

fn main() {
	$if prod { eprintln('Maps285 input tests require assertions'); exit(2) }
	if os.args.len != 3 { eprintln('usage: maps285-input-test PREPARER_BINARY SHA256'); exit(2) }
	binary := os.args[1]
	assert hash(binary)! == os.args[2]
	assert !os.exists(root)
	os.mkdir_all(root)!
	os.cp(@FILE, root + '/maps285-input-test.v')!
	os.cp(binary, root + '/preparer')!
	mut valid := header('./', `5`, 0, '', '0000755')
	valid << header('./bin/', `5`, 0, '', '0000750')
	valid << header('./bin/tool', `0`, 3, '', '0000751')
	valid << 'abc'.bytes()
	valid << []u8{len: 509}
	valid << header('./link', `2`, 0, 'bin/tool', '0000777')
	valid << []u8{len: 1024}
	decoded := json2.decode[map[string]string](tar_case(binary, 'valid', valid, true)!)!
	assert decoded['bin/tool']! == sha256.sum('abc'.bytes()).hex()
	assert decoded['@mode:bin/tool']! == '489' && decoded['@mode:bin']! == '488'
	assert decoded['link']! == 'symlink:bin/tool'
	mut bad := valid.clone()
	bad[101] = `9`
	tar_case(binary, 'checksum', bad, false)!
	for name, bytes in {
		'root-type': header('./', `0`, 0, '', '0000755'),
		'duplicate-root': [...header('./', `5`, 0, '', '0000755'), ...header('./', `5`, 0, '', '0000755')],
		'duplicate-path': [...header('file', `0`, 0, '', '0000644'), ...header('file', `0`, 0, '', '0000644')],
		'traversal': header('../escape', `0`, 0, '', '0000644'),
		'absolute': header('/escape', `0`, 0, '', '0000644'),
		'unsupported-type': header('device', `3`, 0, '', '0000644'),
		'truncated-header': valid[..200].clone(),
		'truncated-payload': [...header('file', `0`, 512, '', '0000644'), ...'short'.bytes()]
	} { tar_case(binary, name, bytes, false)! }
	sealed := '/Users/alex/.local/state/vinix/android/maps283-2026-10-25'
	boot := sealed + '/prelaunch/prelaunch/replica/build/android-maps/maps283/vm/boot.img'
	argv := ['/bin/zsh', '-c', 'set -o pipefail; ' + quote(os.find_abs_path_of_executable('mtype')!) + ' -i ' + quote(boot) + ' ::/boot/qemu-runtime.tar | ' + quote(binary) + ' --tar-tree-stdin']
	write_json(root + '/actual283-before.json', {'argv': json2.Any(argv), 'started_utc': json2.Any(time.utc().str()), 'sealed283_manifest_sha256': json2.Any(hash(sealed + '/sha256.json')!), 'preparer_sha256': json2.Any(hash(binary)!)})!
	r := os.exec(argv)
	os.write_file(root + '/actual283.log', r.output)!
	assert r.exit_code == 0, r.output
	actual := json2.decode[map[string]string](r.output)!
	mut expected := map[string]string{}
	tree('build/android-maps/maps283/module', '', mut expected)!
	write_json(root + '/actual283-module.json', expected)!
	assert actual.len == expected.len, 'typed original module entry count'
	for path, value in expected { assert actual[path]! == value, path }
	write_json(root + '/actual283-receipt.json', {'argv': json2.Any(argv), 'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code), 'typed_entries': json2.Any(actual.len), 'output_sha256': json2.Any(hash(root + '/actual283.log')!)})!
	println('MAPS285 INPUT TESTS PASS actual283 typed runtime; nine malformed tar negatives; executable modes and symlink targets')
}
