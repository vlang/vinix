// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic PID 1: keep Maps/GMS and the native-WS process guard out of the
// isolated browser experiment. This is never installed in production media.
module main

import os
import time

#include <sys/wait.h>
fn C.waitpid(int, &int, int) int

const user_record = 'version=1\nname=564d\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=00000000000000000000000000000000\nhash=0000000000000000000000000000000000000000000000000000000000000000\n'

fn desktop_argv() []string {
	return ['/usr/bin/vinix-desktop', '--open=Terminal']
}

fn boot() ! {
	if os.getpid() != 1 { return error('diagnostic boot must run as PID 1') }
	os.setenv('HOME', '/root', true)
	os.setenv('PATH', '/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('LD_LIBRARY_PATH', '/usr/lib', true)
	os.write_file('/root/.vinix-user', user_record)!
	os.chmod('/root/.vinix-user', 0o600)!
	argv := desktop_argv()
	mut desktop := os.new_process(argv[0])
	desktop.set_args(argv[1..])
	desktop.run()
	if desktop.pid <= 0 { return error('desktop spawn failed') }
	desktop_pid := desktop.pid
	println('BROWSER-BOOT desktop_pid=' + desktop_pid.str() + ' startup=Terminal maps_autolaunch=absent')
	// PID 1 owns orphan reaping as well as its desktop child. Use one wait path
	// so os.Process cannot race waitpid for the desktop's exit status.
	for {
		for {
			mut status := 0
			pid := C.waitpid(-1, &status, 1) // WNOHANG
			if pid <= 0 { break }
			if pid == desktop_pid {
				eprintln('BROWSER-BOOT desktop_exited wait_status=' + status.str())
			}
		}
		time.sleep(time.second)
	}
}

fn self_test() {
	assert desktop_argv() == ['/usr/bin/vinix-desktop', '--open=Terminal']
	assert user_record.ends_with('\n')
	assert user_record.split_into_lines().len == 8
	assert user_record.contains('name=564d\n')
	if os.getpid() != 1 {
		if _ := boot() { panic('host execution accepted') }
	}
	println('BROWSER-BOOT SELF-TEST PASS terminal-startup test-user non-init-rejection')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test()
		return
	}
	if os.args.len != 1 { eprintln('diagnostic boot accepts no arguments'); exit(1) }
	boot() or {
		eprintln('BROWSER-BOOT failed: ' + err.msg())
		if os.getpid() != 1 { exit(1) }
		// Returning from PID 1 would end the guest before evidence collection.
		for { time.sleep(time.second) }
	}
}
