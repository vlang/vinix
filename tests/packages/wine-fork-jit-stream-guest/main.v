// SPDX-License-Identifier: GPL-2.0-or-later
// Capture-only fixture. No VM/build/staging is performed by this source.
module main

import json2
import os
import time
import tools.packages.winejitstream

#include <unistd.h>

fn C.getpid() int
fn C.getuid() u32

fn run() ! {
	if C.getpid() != 1 || C.getuid() != 0 { return error('requires native guest PID 1') }
	directory := '/tmp/wine-jit-stream'
	os.mkdir(directory)!
	os.chmod(directory, 0o777)!
	// No -D and no tid: QEMU9.1.2 keeps default logging on stderr (fd2).
	command := ['/qemu-x86_64', '-B', '0x100000000', '-d', 'out_asm', '/fork-jit-stream-probe',
		directory + '/parent.log', directory + '/child.log']
	result := winejitstream.capture(command, directory, true, 10000)!
	if !result.startup.contains('JITSTREAM ORDINARY uid/gid=1000 groups=0 no-WX PASS\n') {
		return error('ordinary identity was not confirmed')
	}
	// One JSON record preserves role streams separately after confirmed cleanup.
	// Missing ready markers remain parse failures even if this capture completes.
	println('JITSTREAM CAPTURE ' + json2.encode(result))
	println('HWTEST COMPLETE jit-stream-capture (not workload qualification)')
}

fn main() {
	run() or { eprintln('HWTEST FAIL jit-stream-capture: ' + err.msg()) }
	for { time.sleep(time.second) }
}
