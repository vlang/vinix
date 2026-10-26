// SPDX-License-Identifier: GPL-2.0-or-later
// Select one new Maps controller while retaining every other staged input.
module main

import crypto.sha256
import json2
import os

fn pin(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn read_bounded(path string, limit u64) !string {
	if path != os.real_path(path) || os.lstat(path)!.get_filetype() != .regular
		|| os.lstat(path)!.size > limit {
		return error('canonical bounded regular input required')
	}
	text := os.read_file(path)!
	if u64(text.len) > limit { return error('input grew beyond bound') }
	return text
}

fn refresh(original string, root string, seal string) !string {
	mut fields := json2.decode[map[string]json2.Any](original)!
	if fields['kind'] or { json2.Any('') } != json2.Any('vinix-maps-account-stage-request-v1') {
		return error('unexpected request kind')
	}
	old := fields['guest'] or { return error('missing guest reference') }
	if old !is map[string]json2.Any { return error('unexpected guest reference type') }
	old_ref := old.as_map()
	if old_ref.len != 2 || 'root' !in old_ref || 'seal' !in old_ref {
		return error('unexpected guest reference')
	}
	fields['guest'] = json2.Any({'root': json2.Any(root), 'seal': json2.Any(seal)})
	encoded := json2.encode(fields, prettify: true) + '\n'
	mut before := json2.decode[map[string]json2.Any](original)!
	mut after := json2.decode[map[string]json2.Any](encoded)!
	before.delete('guest')
	after.delete('guest')
	if before != after { return error('non-controller request fields differ') }
	return encoded
}

fn run() ! {
	if os.args.len != 6 {
		return error('usage: refresh-maps-account-request ORIGINAL ORIGINAL_SHA256 NEW_CONTROLLER_ROOT NEW_SEAL FRESH_REQUEST')
	}
	original := read_bounded(os.args[1], 32768)!
	if !pin(os.args[2]) || sha256.hexhash(original) != os.args[2] {
		return error('original request pin differs')
	}
	root := os.args[3]
	seal := os.args[4]
	if root != os.real_path(root) || !os.is_dir(root) || !pin(seal)
		|| sha256.hexhash(read_bounded(root + '/sha256.json', 32 * 1024 * 1024)!) != seal {
		return error('canonical controller bundle with pinned manifest required')
	}
	output := os.args[5]
	if output != os.real_path(os.dir(output)) + '/' + os.file_name(output)
		|| output.starts_with('/Users/alex/code/vinix/') || os.exists(output) || os.is_link(output) {
		return error('fresh canonical external output required')
	}
	updated := refresh(original, root, seal)!
	os.write_file(output, updated)!
	if os.read_file(output)! != updated || os.read_file(os.args[1])! != original {
		return error('request readback differs')
	}
	println('MAPS-ACCOUNT-REQUEST-REFRESH PASS only-guest-reference SHA256=' + sha256.hexhash(updated))
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
