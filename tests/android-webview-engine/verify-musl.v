// SPDX-License-Identifier: GPL-2.0-or-later
// Reuse the production deployment ABI auditor for a replacement engine.
module main

import crypto.sha256
import json2
import muslabi
import os

fn main() {
	if os.args.len != 5 { panic('usage: verify-musl ENGINE TOOLCHAIN_LIBC DEPLOYED_LIBC FRESH_EXTERNAL_ROOT') }
	root := os.abs_path(os.args[4])
	if os.exists(root) || os.is_link(root) || root.starts_with(os.real_path(os.getwd()) + '/') {
		panic('fresh external audit output required')
	}
	mut bytes := [][]u8{}
	mut hashes := map[string]json2.Any{}
	mut paths := map[string]json2.Any{}
	for index, name in ['engine', 'toolchain-libc', 'deployed-libc'] {
		path := os.real_path(os.args[index + 1])
		if os.lstat(path)!.get_filetype() != .regular || os.file_size(path) > 16 * 1024 * 1024 {
			panic('bounded regular ABI input required')
		}
		input := os.read_bytes(path)!
		hashes[name] = json2.Any(sha256.sum(input).hex())
		paths[name] = json2.Any(path)
		bytes << input
	}
	verified := muslabi.verify(muslabi.inspect(bytes[0])!, muslabi.inspect(bytes[1])!, muslabi.inspect(bytes[2])!)!
	os.mkdir_all(root)!
	for index, name in ['engine', 'toolchain-libc', 'deployed-libc'] {
		os.write_file_array(root + '/' + name, bytes[index])!
		os.chmod(root + '/' + name, 0o444)!
		if sha256.sum(os.read_bytes(root + '/' + name)!).hex() != hashes[name]!.str() {
			panic('ABI input copy differs')
		}
	}
	os.write_file(root + '/audit.json', json2.encode({
		'inputs': json2.Any(paths), 'sha256': json2.Any(hashes),
		'symbols': json2.Any(verified.map(json2.Any(it)))
	}, prettify: true))!
	println('WEBVIEW-MUSL-ABI-PASS symbols=' + verified.len.str())
}
