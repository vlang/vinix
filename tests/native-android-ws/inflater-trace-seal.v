// SPDX-License-Identifier: GPL-2.0-or-later
// Seal retained inflater fixture evidence, including aborted preparation roots.
module main

import json2
import os
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const source = 'tests/native-android-ws/inflater-trace-seal.v'

fn hash(path string) !string {
	mut input := os.open(path)!
	defer { input.close() }
	mut buffer := []u8{len: 1024 * 1024}
	mut state := C.CC_SHA256_CTX{}
	if C.CC_SHA256_Init(unsafe { &state }) != 1 { return error('SHA256 initialization failed') }
	for {
		n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
		if n == 0 { break }
		if C.CC_SHA256_Update(unsafe { &state }, buffer.data, u32(n)) != 1 { return error('SHA256 update failed') }
	}
	mut sum := [32]u8{}
	if C.CC_SHA256_Final(unsafe { &sum[0] }, unsafe { &state }) != 1 { return error('SHA256 finalization failed') }
	return sum[..].hex()
}

fn inventory(root string, relative string, mut files map[string]string, mut special map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		path := root + '/' + key
		kind := os.lstat(path)!.get_filetype()
		match kind {
			.directory { inventory(root, key, mut files, mut special)! }
			.regular { files[key] = hash(path)! }
			else { special[key] = kind.str() }
		}
	}
}

fn seal(root string) ! {
	assert os.is_dir(root) && !os.is_link(root)
	assert !os.exists(root + '/sha256.json') && !os.exists(root + '/seal-metadata.json')
	mut files := map[string]string{}
	mut special := map[string]string{}
	inventory(root, '', mut files, mut special)!
	assert special.len == 0, json2.encode(special)
	mut stopped := map[string]json2.Any{}
	for path, _ in files {
		if !path.ends_with('/qemu.pid') { continue }
		pid := os.read_file(root + '/' + path)!.trim_space()
		assert pid.int() > 0 && pid.bytes().all(it >= `0` && it <= `9`), path
		probe := os.exec(['/bin/kill', '-0', pid])
		assert probe.exit_code != 0, 'guest PID remains live: ' + pid
		stopped[path] = json2.Any({'pid': json2.Any(pid), 'argv': json2.Any(['/bin/kill', '-0', pid]), 'exit_code': json2.Any(probe.exit_code), 'output': json2.Any(probe.output)})
	}
	metadata := {'argv': json2.Any(os.args), 'completed_utc': json2.Any(time.utc().str()), 'source_sha256': json2.Any(hash(source)!), 'tool_sha256': json2.Any(hash(os.executable())!), 'non_regular_entries': json2.Any([]string{}), 'stopped_qemu_pids': json2.Any(stopped)}
	os.write_file(root + '/seal-metadata.json', json2.encode(metadata, prettify: true) + '\n')!
	files['seal-metadata.json'] = hash(root + '/seal-metadata.json')!
	os.write_file(root + '/sha256.json', json2.encode(files, prettify: true) + '\n')!
	mut readback := map[string]string{}
	inventory(root, '', mut readback, mut special)!
	assert special.len == 0
	readback.delete('sha256.json')
	assert files == readback, root
	println('INFLATER-TRACE-BUNDLE-SEALED root=${root} files=${files.len} manifest=' + hash(root + '/sha256.json')!)
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 3 && os.args[1] == 'seal', 'seal ROOT'
	seal(os.abs_path(os.args[2]))!
}
