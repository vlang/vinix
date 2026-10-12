// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import os
import sourcecommand

fn emit() ! {
	mut output := os.stdout()
	mut diagnostic := os.stderr()
	data := 'stdout block\n'.repeat(20000)
	errors := 'stderr block\n'.repeat(20000)
	unsafe {
		output.write_full_buffer(data.str, usize(data.len))!
		diagnostic.write_full_buffer(errors.str, usize(errors.len))!
	}
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--emit' {
		emit() or { panic(err) }
		return
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len != 2 { exit(2) }
	work := os.args[1]
	gamehost.mkdir(work) or { panic(err) }
	before := os.ls('/dev/fd') or { panic(err) }.len
	for _ in 0 .. 10 {
		result := sourcecommand.capture_full([os.executable(), '--emit'], os.environ(), 10, 512 * 1024, cachecli.cancelled) or { panic(err) }
		assert result.status == 0 && result.stdout == 'stdout block\n'.repeat(20000) && result.stderr == 'stderr block\n'.repeat(20000)
	}
	original := sourcecommand.capture([os.executable(), '--emit'], os.environ(), 10, 512 * 1024, cachecli.cancelled) or { panic(err) }
	assert original.stdout == 'stdout block\n'.repeat(20000) && original.stderr.len == 64 * 1024
	for limit in [1024, 64 * 1024] {
		mut refused := false
		sourcecommand.capture_full(['/bin/sh', '-c', 'head -c 80000 /dev/zero >&2'], os.environ(), 10, limit, cachecli.cancelled) or {
			refused = true
			assert err.msg() == 'command stderr exceeds limit'
		}
		assert refused
	}
	assert os.ls('/dev/fd') or { panic(err) }.len == before
	os.write_file(work + '/passed', 'PASS\n') or { panic(err) }
	println('COMPLETE SDK CAPTURE / both 260000-byte streams, legacy 64 KiB diagnostic prefix, both bound errors and repeated FD ownership: PASS')
}
