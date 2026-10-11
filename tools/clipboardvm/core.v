// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module clipboardvm

import hosttest
import json2
import os
import packageserver
import qmpclient
import sourcecommand
import time

const sample = 'Привет\t😀\nsecond line'

struct State {
	work string
	log_path string
	deadline u64
mut:
	log os.File
	received string
	phases []string
	monitor qmpclient.Monitor
	connected bool
}

fn read_clipboard(server &packageserver.Server) !string {
	data := os.read_file(server.clipboard_context)!
	hosttest.module_decode_utf8(data)!
	return data
}

fn observe(chunk string, context voidptr) ! {
	mut state := unsafe { &State(context) }
	state.log.write_string(chunk)!; state.log.flush()
	state.received += chunk
	for phase in ['editor', 'terminal', 'x11'] {
		if !state.received.contains('CLIPBOARD READY: ' + phase) || phase in state.phases { continue }
		state.phases << phase
		if !state.connected { state.monitor = qmpclient.connect_bounded(state.work + '/qmp.sock', state.deadline, packageserver.cancelled)!; state.connected = true }
		text := if phase == 'terminal' { "printf 'Привет\\t😀\\nsecond line' > /tmp/terminal-paste" } else { sample }
		os.write_file(state.work + '/clipboard.new', text)!
		os.mv(state.work + '/clipboard.new', state.work + '/clipboard')!
		state.monitor.command('human-monitor-command', {'command-line': json2.Any('sendkey ctrl-v')})!
		deadline := time.sys_mono_now() + u64(2 * time.second)
		for time.sys_mono_now() < deadline { packageserver.checkpoint()!; time.sleep(10 * time.millisecond) }
		if phase in ['editor', 'terminal'] {
			state.monitor.command('human-monitor-command', {'command-line': json2.Any(if phase == 'editor' { 'sendkey ctrl-s' } else { 'sendkey ret' })})!
		}
		println('pasted into ' + phase)
	}
	if state.received.contains('CLIPBOARD FAIL:') { return error(state.received[if state.received.len > 3000 { state.received.len - 3000 } else { 0 }..]) }
	if state.received.contains('CLIPBOARD TEST: PASS') { return error_with_code('clipboard passed', 99) }
}

pub fn prepare(root string, work string, port int) !map[string]string {
	overlay := work + '/overlay'
	app := overlay + '/opt/clipboard'
	os.mkdir_all(app)!; os.mkdir_all(overlay + '/usr/bin')!
	os.write_file(app + '/url', 'http://10.0.2.2:${port}/clipboard\n')!
	os.write_file(app + '/expected', sample)!
	for name in ['vinix-desktop', 'vinix-editor', 'vinix-terminal', 'vinix-firefox'] {
		hosttest.module_copy_file_preserving_stat(root + '/build/vinix-desktop', overlay + '/usr/bin/' + name)!
	}
	hosttest.module_copy_file_preserving_stat(root + '/build/vinix-wine-host-clipboard', overlay + '/usr/bin/vinix-wine-host')!
	os.write_file(overlay + '/usr/bin/run-firefox', '#!/bin/sh\nexec /opt/clipboard/x11-client\n')!
	os.chmod(overlay + '/usr/bin/run-firefox', 0o755)!
	sysroot := root + '/build-aarch64-x11/sysroot'
	gcc_root := root + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl'
	versions := os.ls(gcc_root)!
	if versions.len == 0 { return error('GCC install directory missing') }
	result := sourcecommand.capture(['/opt/homebrew/opt/llvm/bin/clang', '--target=aarch64-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc_root + '/' + versions[0], '-static-libgcc', '-Wall', '-Wextra', '-Werror', root + '/tests/clipboard/x11-client.c',
		'-fuse-ld=lld', '-L' + sysroot + '/usr/lib', '-L' + sysroot + '/lib', '-Wl,-rpath-link,' + sysroot + '/usr/lib', '-Wl,-rpath-link,' + sysroot + '/lib',
		'-lX11', '-lxcb', '-o', app + '/x11-client'], os.environ(), -1, 64 * 1024 * 1024, packageserver.cancelled)!
	if result.status != 0 { return error('clipboard X11 client build failed: ' + result.stderr) }
	mut env := os.environ()
	for key, value in {'VINIX_QEMU_OVERLAY': overlay, 'VINIX_QEMU_AUDIO': 'off', 'VINIX_QEMU_EXTRA': '-qmp unix:' + work + '/qmp.sock,server=on,wait=off',
		'VINIX_QEMU_HOST_SOURCE': '0', 'VINIX_QEMU_PACKAGE_PERSIST': '0', 'VINIX_QEMU_RESOLUTION': '1024x768x32',
		'VINIX_OVMF_CODE': root + '/boot-image/edk2-aarch64-code-2048x1536.fd'} { env[key] = value }
	return env
}

pub fn drive(argv []string, env map[string]string, work string, log string, timeout f64, grace f64) ! {
	mut state := &State{work: work, log_path: log, log: os.create(log)!, deadline: time.sys_mono_now() + u64(timeout * f64(time.second))}
	defer { state.monitor.close(); state.log.close() }
	sourcecommand.capture_observed(argv, env, timeout, 0x7fffffff, packageserver.cancelled, observe, state, grace) or {
		if err.code() == 99 { println('PASS QEMU editor, terminal and X11 clipboard; log: ' + log); return }
		return err
	}
	return error('clipboard VM did not finish; see ' + log)
}

pub fn run(root string) ! {
	guard := packageserver.own_service(); defer { guard.close() }
	work := sourcecommand.temporary('vinix-clipboard-vm')!; defer { os.rmdir_all(work) or { eprintln(err) } }
	os.write_file(work + '/clipboard', sample)!
	mut server := packageserver.start(packageserver.Config{store: work + '/packages.tar', port: 0, maximum: 1024, clipboard: true})!
	server.clipboard_context = work + '/clipboard'
	server.clipboard_reader = read_clipboard
	task := spawn server.serve()
	defer { server.stop(); task.wait() or { eprintln(err) } }
	env := prepare(root, work, server.port)!
	log := root + '/build/clipboard-vm.log'
	argv := [root + '/scripts/run-desktop-aarch64.sh', '--no-build', '--no-persist', '--ephemeral', '--serial', '--mem=16384', '--guest-init=' + root + '/tests/clipboard/guest-init.sh']
	drive(argv, env, work, log, 300, 10)!
}

pub fn cli(args []string) int {
	if args == ['--help'] || args == ['-h'] { println('run-vm: paste through QEMU into native and hosted applications'); return 0 }
	root := os.real_path(@DIR + '/../..')
	run(root) or { eprintln(err); return if packageserver.cancelled() { packageserver.interrupt_status() } else { 1 } }
	return 0
}
