// SPDX-License-Identifier: GPL-2.0-or-later
// An executable guest init for --guest-init, built by --cross.
module main

import desktop.windowfb
import os
import time

#include <sys/reboot.h>

fn C.reboot(u32) int

fn check_window(iteration int) ! {
	mut window := windowfb.open('Framebuffer guest check', 320, 240)!
	defer { window.close() }
	mut event := windowfb.Message{}
	for frame in 0 .. 3 {
		color := u32(0x102030 + iteration * 0x10000 + frame)
		unsafe {
			for pixel in 0 .. 320 * 240 { window.surface.back[pixel] = color }
		}
		window.present()!
		for window.frame_pending {
			if !window.connection.wait(5000)! { return error('frame acknowledgement timed out') }
			for window.receive(unsafe { &event })! {
				if event.kind == .close { return error('window closed unexpectedly') }
			}
		}
		if window.event_fd() < 0 { return error('missing event descriptor') }
	}
	window.close()
	window.close()
}

fn check_frames() ! {
	deadline := time.sys_mono_now() + 90 * time.second
	path := windowfb.socket_path()
	defer { unsafe { path.free() } }
	for !os.exists(path) {
		if time.sys_mono_now() >= deadline { return error('desktop window socket did not appear') }
		time.sleep(20 * time.millisecond)
	}
	for iteration in 0 .. 10 {
		check_window(iteration)!
	}
}

fn main() {
	for directory in ['/tmp', '/run', '/root'] { os.mkdir_all(directory) or { panic(err) } }
	os.setenv('HOME', '/root', true)
	os.setenv('PATH', '/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('TERM', 'linux', true)
	os.write_file('/root/.vinix-user', 'version=1\nname=4672616d656275666665722054657374\nkdf=scrypt\nn=16384\nr=8\np=1\nsalt=00112233445566778899aabbccddeeff\nhash=00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\n') or { panic(err) }
	os.chmod('/root/.vinix-user', 0o600) or { panic(err) }
	os.rm('/root/.vinix-first-run-apps') or {}
	mut desktop := os.new_process('/usr/bin/vinix-desktop')
	// Explicit open suppresses the default startup applications so this tests
	// the standalone framebuffer boundary independently of utility startup.
	desktop.set_args(['--open=System'])
	desktop.run()
	check_frames() or {
		eprintln('FRAMEBUFFER GUEST FAIL: ' + err.msg())
		C.reboot(u32(0x4321fedc))
		return
	}
	println('FRAMEBUFFER GUEST PASS: 10 windows, 30 acknowledged shared frames, waitable events')
	desktop.signal_kill()
	desktop.wait()
	desktop.close()
	C.reboot(u32(0x4321fedc))
}
