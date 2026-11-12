// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only replay of the retained ARM GUI failure; diagnostic, not acceptance.
module main

import crypto.sha256
import json2
import os
import time
import tests.packages.winesource

fn run() ! {
	if os.args.len != 5 { return error('usage: wine-arm-gui-debug FRESH_OUTPUT KERNEL BOOT_IMAGE VARS') }
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-arm-gui-debug.v').to_string()) { return error('compiled debugger source differs') }
	work := os.abs_path(os.args[1]); kernel := os.real_path(os.args[2])
	image := os.real_path(os.args[3]); vars := os.real_path(os.args[4])
	if winesource.file_digest(kernel)! != '56b609fce5cdae4ff8137d897040a5b239a2e265aab4b28e6a18b2159cac83d9'
		|| winesource.file_digest(image)! != 'a6b1b952ffc50cfc0247b6ffe00f2c5a8579486c73a0df31d1e826116a86c059' { return error('unsupported diagnostic kernel/image') }
	if os.exists(work) || os.is_link(work) { return error('diagnostic output must be fresh') }
	os.mkdir_all(work)!
	os.cp(@FILE, work + '/producer.v')!; os.cp(os.executable(), work + '/producer')!
	qemu := '/opt/homebrew/bin/qemu-system-aarch64'
	firmware := '/opt/homebrew/share/qemu/edk2-aarch64-code.fd'
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), kernel, image, vars, qemu, firmware, '/usr/bin/lldb', os.dir(@FILE) + '/winesource/closure.v'] {
		inputs[path] = winesource.file_digest(path)!
	}
	os.write_file(work + '/selected-inputs.json', json2.encode(inputs))!
	os.write_file(work + '/scope.txt', 'Read-only retained ARM GUI replay with one virtual CPU for debugger isolation. Original disk is read-only; firmware variables are copied. Selected executable/source identities only; no complete toolchain/library closure, package or Wine qualification.\n')!
	os.cp(vars, work + '/vars.fd')!
	qargs := ['-machine', 'virt,gic-version=3', '-accel', 'hvf', '-cpu', 'host', '-m', '1024', '-smp', '1',
		'-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device', 'virtio-rng-device,rng=vinix-rng',
		'-drive', 'if=pflash,format=raw,readonly=on,file=' + firmware,
		'-drive', 'if=pflash,format=raw,file=' + work + '/vars.fd',
		'-drive', 'format=raw,readonly=on,file=' + image,
		'-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-device', 'ramfb',
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + work + '/serial.log', '-no-reboot',
		'-S', '-gdb', 'tcp:127.0.0.1:54516']
	mut qargv := [qemu]; qargv << qargs
	os.write_file(work + '/qemu-argv.json', json2.encode(qargv))!
	mut machine := os.new_process(qemu); machine.set_args(qargs); machine.run()
	defer { if machine.is_alive() { machine.signal_kill(); machine.wait() }; machine.close() }
	time.sleep(time.second)
	if machine.pid <= 0 || !machine.is_alive() { return error('diagnostic machine did not start') }
	largs := ['--batch', '--no-lldbinit', '--arch', 'aarch64', '--file', kernel,
		'-o', 'gdb-remote 127.0.0.1:54516',
		// Only the denied branch reaches this instruction, after x19/x21
		// hold the current thread/process. Pin the exact ELF above.
		'-o', 'breakpoint set --hardware --address 0xffffffff8006b04c',
		'-o', 'continue', '-o', 'register read x0 x19 x21 pc sp fp lr', '-o', 'bt',
		'-o', 'expression -- ((proc__Thread*)$x19)->pledge_syscall',
		'-o', 'expression -- ((proc__Thread*)$x19)->pledge_argument',
		'-o', 'expression -- ((proc__Thread*)$x19)->process->name',
		'-o', 'frame select 1', '-o', 'frame variable',
		'-o', 'frame select 2', '-o', 'frame variable', '-o', 'process detach']
	mut largv := ['/usr/bin/lldb']; largv << largs
	os.write_file(work + '/lldb-argv.json', json2.encode(largv))!
	mut debugger := os.new_process('/usr/bin/lldb'); debugger.set_args(largs); debugger.set_redirect_stdio_merged(); debugger.run()
	defer { debugger.close() }
	C.close(debugger.stdio_fd[0]); debugger.stdio_fd[0] = -1
	deadline := time.sys_mono_now() + 180 * time.second
	for debugger.is_alive() && time.sys_mono_now() < deadline { time.sleep(100 * time.millisecond) }
	timed_out := debugger.is_alive()
	if timed_out { debugger.signal_kill(); debugger.wait() }
	os.write_file(work + '/lldb.log', debugger.stdout_slurp())!
	os.write_file(work + '/exit.json', json2.encode({'code': debugger.code.str(), 'timed_out': timed_out.str()}))!
	for path, expected in inputs { if winesource.file_digest(path)! != expected { return error('diagnostic input changed: ' + path) } }
	os.write_file(work + '/selected-inputs-verified.json', json2.encode(inputs))!
	if debugger.code != 0 || timed_out { return error('debugger replay failed; retain partial evidence') }
	println('ARM GUI DEBUGGER replay complete; diagnostic only')
}

fn main() { run() or { eprintln(err); exit(1) } }
