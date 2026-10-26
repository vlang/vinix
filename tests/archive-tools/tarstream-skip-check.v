// SPDX-License-Identifier: GPL-2.0-only
module main

import os
import tarcore
import tarstream

// Run under -gc none and /usr/bin/time -l. Reuse a single small archive rather
// than staging one payload per iteration; actual reads touch the skip buffer.
fn run() ! {
	if os.args.len != 4 {
		return error('usage: tarstream-skip-check REPETITIONS success|body-eof|padding-eof FRESH_DIRECTORY')
	}
	repetitions := os.args[1].int()
	if repetitions < 1 || repetitions > 256 || repetitions.str() != os.args[1] {
		return error('repetitions must be a canonical integer from 1 to 256')
	}
	mode := os.args[2]
	if mode !in ['success', 'body-eof', 'padding-eof'] {
		return error('unknown skip case')
	}
	root := os.args[3]
	if os.exists(root) { return error('result directory must be fresh') }
	os.mkdir(root)!
	path := root + '/input.tar'
	create_input(path, mode)!
	mut file := os.open(path)!
	defer { file.close() }
	mut prefix := []u8{len: 257}
	defer { unsafe { prefix.free() } }
	mut tail := []u8{len: 5}
	defer { unsafe { tail.free() } }
	for index in 0 .. repetitions {
		file.seek(0, .start)!
		mut reader := tarstream.from_descriptor(file.fd)!
		assert reader.next()!.name == 'payload'
		if index % 2 == 1 {
			assert reader.read(mut prefix)! == prefix.len
			for offset, value in prefix { assert value == u8(offset * 67 + 11) }
		}
		if mode == 'success' {
			assert reader.next()!.name == 'after'
			assert reader.read(mut tail)! == tail.len
			for offset, value in tail { assert value == 'after'[offset] }
			mut ended := false
			reader.next() or { assert err is tarstream.End; ended = true }
			assert ended
		} else {
			mut refused := false
			reader.next() or {
				assert err !is tarstream.End && err.msg() == 'unexpected end of archive'
				refused = true
			}
			assert refused
		}
		reader.close()
	}
	println('PASS ${mode}: ${repetitions} repeated unread/partial skips')
}

fn create_input(path string, mode string) ! {
	mut writer := tarcore.create_stream(path)!
	defer { writer.close() }
	data := []u8{len: 1024 * 1024 + 513, init: u8(index * 67 + 11)}
	defer { unsafe { data.free() } }
	header := tarcore.header(tarcore.Member{ name: 'payload', size: data.len })!
	defer { unsafe { header.free() } }
	writer.write(header)!
	limit := if mode == 'body-eof' { 1024 * 1024 } else { data.len }
	portion := unsafe { data[..limit] }
	writer.write(portion)!
	if mode == 'success' {
		writer.padding(data.len)!
		writer.add(tarcore.Member{ name: 'after', size: 5 }, 'after'.bytes())!
		writer.finish()!
	}
	writer.close_checked()!
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
