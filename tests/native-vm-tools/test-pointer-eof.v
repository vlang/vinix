// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import gamehost
import os
import vmhost

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}

fn run() ! {
	if os.args.len != 2 { exit(2) }
	mut pattern := ('/tmp/vinix-pointer-eof.XXXXXX\x00').bytes()
	assert C.mkdtemp(pattern.data) != unsafe { nil }
	root := pattern.bytestr().all_before('\x00')
	defer { gamehost.remove(root) or {} }
	baseline := os.ls('/dev/fd')!.len
	for index in 0 .. 100 {
		guard := cachecli.own_commands()
		directory := root + '/' + index.str()
		gamehost.mkdir(directory)!
		mut env := os.environ()
		env['VINIX_VM_CASE'] = directory
		mut failed := false
		vmhost.pointer_capture(vmhost.Launch{[os.args[1], 'mock', 'pointer', 'serial-eof'], env, directory}, directory + '/qmp.sock', directory + '/log', 5) or {
			failed = true
			assert err.msg().contains('POINTER_SCROLL') || err.msg().contains('QMP'), err.msg()
		}
		assert failed && os.is_file(directory + '/log'), directory
		pid := os.read_file(directory + '/child.pid')!.int()
		assert C.kill(i32(pid), 0) != 0 && C.errno == C.ESRCH
		assert os.ls('/dev/fd')!.len == baseline
		guard.close()
	}
	println('PASS 100 real serial-EOF/QMP races: exact PID/descriptor retirement and retained failure logs')
}
