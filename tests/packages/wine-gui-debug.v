// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only replay of one failed graphical fixture; no launch qualification.
module main

import crypto.sha256
import json2
import os
import time
import tests.packages.winesource

const kernel_sha = '3ab99a5aebbc64efadd678f3de2ab6ec4ba4ade06bd76012ccdf4bc2635c36f6'
const iso_sha = '61916ed97e22f2c4c990c3b2799c7613cf3403d8533010df4326fcdad9cdea3d'

fn run() ! {
	if os.args.len != 4 { return error('usage: wine-gui-debug FRESH_OUTPUT KERNEL ISO') }
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-gui-debug.v').to_string()) { return error('compiled GUI debugger source differs') }
	work := os.abs_path(os.args[1]); kernel := os.real_path(os.args[2]); iso := os.real_path(os.args[3])
	if winesource.file_digest(kernel)! != kernel_sha || winesource.file_digest(iso)! != iso_sha { return error('unsupported diagnostic kernel or ISO') }
	if os.exists(work) || os.is_link(work) { return error('GUI debugger output must be fresh') }
	os.mkdir_all(work)!
	os.cp(@FILE, work + '/producer.v')!; os.cp(os.executable(), work + '/producer')!
	qemu := '/opt/homebrew/bin/qemu-system-x86_64'; firmware := '/opt/homebrew/share/qemu/edk2-x86_64-code.fd'
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), kernel, iso, qemu, firmware, '/usr/bin/lldb', os.dir(@FILE) + '/winesource/closure.v'] {
		inputs[path] = winesource.file_digest(path)!
	}
	os.write_file(work + '/selected-inputs.json', json2.encode(inputs))!
	os.write_file(work + '/scope.txt', 'Read-only failed GUI replay. Exact retained kernel/ISO; selected host executable/source pins only, no complete debugger/compiler/library closure or Wine acceptance.\n')!
	qargs := ['-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024', '-smp', '2',
		'-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom', iso,
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + work + '/serial.log', '-no-reboot', '-S', '-gdb', 'tcp:127.0.0.1:54515']
	mut full_qargs := [qemu]; full_qargs << qargs
	os.write_file(work + '/qemu-argv.json', json2.encode(full_qargs))!
	mut machine := os.new_process(qemu); machine.set_args(qargs); machine.run()
	defer { if machine.is_alive() { machine.signal_kill(); machine.wait() }; machine.close() }
	time.sleep(time.second)
	if machine.pid <= 0 || !machine.is_alive() { return error('GUI diagnostic QEMU did not remain running') }
	mut largs := ['--batch', '--no-lldbinit', '--arch', 'x86_64', '--file', kernel,
		'-o', 'gdb-remote 127.0.0.1:54515', '-o', 'breakpoint set --hardware --address 0xffffffff80206a50']
	for _ in 0 .. 2 {
		largs << ['-o', 'continue', '-o', 'register read rdi rsi rdx rip rsp rbp', '-o', 'bt',
			'-o', 'thread step-inst --count 4',
			'-o', 'expression -- ((proc__Thread*)$rsi)->pledge_syscall',
			'-o', 'expression -- ((proc__Thread*)$rsi)->pledge_argument',
			'-o', 'expression -- ((proc__Thread*)$rsi)->pledge_violation',
			'-o', 'expression -- ((proc__Thread*)$rsi)->process->pledge',
			'-o', 'expression -- ((proc__Thread*)$rsi)->process->pid',
			'-o', 'expression -- ((proc__Thread*)$rsi)->process->name',
			'-o', 'frame select 0']
	}
	largs << ['-o', 'process detach']
	mut full_largs := ['/usr/bin/lldb']; full_largs << largs
	os.write_file(work + '/lldb-argv.json', json2.encode(full_largs))!
	mut debugger := os.new_process('/usr/bin/lldb'); debugger.set_args(largs); debugger.set_redirect_stdio_merged(); debugger.run()
	defer { debugger.close() }
	C.close(debugger.stdio_fd[0]); debugger.stdio_fd[0] = -1
	deadline := time.sys_mono_now() + 150 * time.second
	for debugger.is_alive() && time.sys_mono_now() < deadline { time.sleep(100 * time.millisecond) }
	timed_out := debugger.is_alive()
	if timed_out { debugger.signal_kill(); debugger.wait() }
	os.write_file(work + '/lldb.log', debugger.stdout_slurp())!
	os.write_file(work + '/exit.json', json2.encode({'code': debugger.code.str(), 'timed_out': timed_out.str()}))!
	for path, expected in inputs { if winesource.file_digest(path)! != expected { return error('GUI debugger selected input changed: ' + path) } }
	os.write_file(work + '/selected-inputs-verified.json', json2.encode(inputs))!
	if debugger.code != 0 || timed_out { return error('GUI diagnostic replay failed; retain partial output') }
	println('WINE GUI DIAGNOSTIC replay completed; no launch qualification')
}

fn main() { run() or { eprintln(err); exit(1) } }
