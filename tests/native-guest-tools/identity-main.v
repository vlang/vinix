// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import hosttest
import os

fn main() {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{name: '--arch', value: true, choices: ['aarch64', 'x86_64']},
		hosttest.Option{name: '--kernel-dir', value: true},
		hosttest.Option{name: '--sysroot', value: true},
		hosttest.Option{name: '--state-dir', value: true},
		hosttest.Option{name: '--timeout', value: true},
		hosttest.Option{name: '--audit'},
	], []string{}, 'run --arch aarch64|x86_64 --kernel-dir DIR --sysroot DIR --state-dir DIR [--audit] [--timeout SECONDS]') or { eprintln(err); exit(2) }
	for name in ['--arch', '--kernel-dir', '--sysroot', '--state-dir'] {
		if !options.has(name) { eprintln('missing ' + name); exit(2) }
	}
	run(options) or { eprintln(err); exit(1) }
}

fn run(options guesthost.Options) ! {
	root := os.dir(os.dir(os.dir(@FILE)))
	arch := options.value('--arch', '')
	state := os.abs_path(options.value('--state-dir', ''))
	sdk := os.abs_path(options.value('--sysroot', ''))
	if os.exists(state) { return error('state directory must be fresh') }
	fs := state + '/rootfs'
	for name in ['bin', 'lib', 'usr/bin', 'etc', 'sbin', 'proc', 'sys', 'dev', 'tmp', 'root'] { os.mkdir_all(fs + '/' + name)! }
	loader := if arch == 'aarch64' { 'ld-musl-aarch64.so.1' } else { 'ld-musl-x86_64.so.1' }
	os.cp(sdk + '/bin/busybox', fs + '/bin/busybox')!
	os.chmod(fs + '/bin/busybox', 0o755)!
	os.cp(sdk + '/lib/' + loader, fs + '/lib/' + loader)!
	os.chmod(fs + '/lib/' + loader, 0o755)!
	os.symlink('busybox', fs + '/bin/sh')!
	if options.has('--audit') {
		os.cp(root + '/build-support/uname', fs + '/bin/uname')!
		os.chmod(fs + '/bin/uname', 0o755)!
		os.symlink('../../bin/uname', fs + '/usr/bin/uname')!
		for name in ['os-release', 'issue', 'motd'] { os.cp(sdk + '/etc/' + name, fs + '/etc/' + name)! }
		os.mkdir_all(fs + '/usr/lib')!
		os.cp(sdk + '/usr/lib/os-release', fs + '/usr/lib/os-release')!
		os.write_file(fs + '/etc/identity-audit', '')!
	} else {
		mut process := os.new_process(root + '/build-support/stage-uname.sh')
		process.set_args([fs])
		process.run()
		process.wait()
		if process.code != 0 { return error('identity staging failed') }
	}
	init := guesthost.compile_init(root + '/tests/userland-identity/guestfixture/core.v', state, arch, false)!
	archive := guesthost.image(init, state)!
	launch := guesthost.launch(init, archive, state, os.abs_path(options.value('--kernel-dir', '')), arch, true)!
	expect := if options.has('--audit') { 'USERLAND IDENTITY AUDIT DONE' } else { 'USERLAND IDENTITY PASS' }
	result := guesthost.boot(launch.command, launch.env, state, [expect], ['USERLAND IDENTITY FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'], options.integer('--timeout', 120)!, true)!
	if result != 0 { return error('identity guest failed; see ' + state + '/serial.log') }
}
