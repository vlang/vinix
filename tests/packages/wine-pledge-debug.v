// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only debugger replay of a retained ISO; this cannot qualify Wine.
module main

import crypto.sha256
import json2
import os
import tests.packages.winesource
import time

const diagnostic_kernel = '06a9936a923892a01fb291d8a9ec21a69b3ad1a1a1658c47cf7d5e85ee10d039'
const diagnostic_iso = 'edeed0c5842343a90263140db10b0728b73d5d1734b63b1e7a39869265dfa10a'

fn check() ! {
	if os.args.len != 4 { return error('usage: wine-pledge-debug OUTPUT KERNEL ISO') }
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-pledge-debug.v').to_string()) {
		return error('compiled debugger producer differs from its source')
	}
	work := os.abs_path(os.args[1])
	kernel := os.real_path(os.args[2])
	iso := os.real_path(os.args[3])
	// Addresses, stepping count and DWARF field names below belong to this
	// retained kernel. Refuse another ELF rather than interpret the wrong ABI.
	if winesource.file_digest(kernel)! != diagnostic_kernel { return error('unsupported diagnostic kernel') }
	if winesource.file_digest(iso)! != diagnostic_iso { return error('unsupported diagnostic ISO') }
	if os.exists(work) { return error('output exists') }
	os.mkdir_all(work)!
	os.cp(@FILE, work + '/producer.v')!
	os.cp(os.executable(), work + '/producer')!
	qemu := '/opt/homebrew/bin/qemu-system-x86_64'
	firmware := '/opt/homebrew/share/qemu/edk2-x86_64-code.fd'
	mut hashes := map[string]string{}
	for path in [@FILE, os.executable(), kernel, iso, qemu, firmware, '/usr/bin/lldb',
		os.dir(@FILE) + '/winesource/closure.v'] {
		real := os.real_path(path)
		hashes[real] = winesource.file_digest(real)!
	}
	os.write_file(work + '/selected-inputs.json', json2.encode(hashes))!
	os.write_file(work + '/scope.txt', 'Read-only debugger replay; selected executable/source inputs only. Host compiler, debugger libraries and complete toolchain closure are not admitted. The retained ISO remains required. No Wine acceptance gate is evaluated.\n')!
	qargs := ['-machine', 'q35,smm=off', '-accel', 'tcg', '-cpu', 'max', '-m', '1024', '-smp', '2',
		'-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=' + firmware, '-cdrom', iso,
		'-display', 'none', '-monitor', 'none', '-serial', 'file:' + work + '/serial.log', '-no-reboot',
		'-S', '-gdb', 'tcp:127.0.0.1:54514']
	mut full_qargs := [qemu]; full_qargs << qargs
	os.write_file(work + '/qemu-argv.json', json2.encode(full_qargs))!
	mut machine := os.new_process(qemu)
	machine.set_args(qargs)
	machine.run()
	defer { if machine.is_alive() { machine.signal_kill() }; machine.wait(); machine.close() }
	time.sleep(time.second)
	if machine.pid <= 0 || !machine.is_alive() { return error('diagnostic QEMU did not remain running') }
	largs := ['--batch', '--no-lldbinit', '--arch', 'x86_64', '--file', kernel,
		'-o', 'gdb-remote 127.0.0.1:54514', '-o', 'breakpoint set --hardware --address 0xffffffff8002a540',
		'-o', 'continue', '-o', 'register read rdi rsi rdx rip rsp rbp', '-o', 'bt',
		'-o', 'thread step-inst --count 4',
		'-o', 'expression -- ((proc__Thread*)$rsi)->pledge_syscall',
		'-o', 'expression -- ((proc__Thread*)$rsi)->pledge_violation',
		'-o', 'expression -- ((proc__Thread*)$rsi)->process->pledge',
		'-o', 'expression -- ((proc__Thread*)$rsi)->process->pid',
		'-o', 'expression -- ((proc__Thread*)$rsi)->process->name',
		'-o', 'frame select 2', '-o', 'expression -- (char*)context->rdi',
		'-o', 'expression -- context->rsi', '-o', 'process detach']
	mut full_largs := ['/usr/bin/lldb']; full_largs << largs
	os.write_file(work + '/lldb-argv.json', json2.encode(full_largs))!
	mut debugger := os.new_process('/usr/bin/lldb')
	debugger.set_args(largs)
	debugger.set_redirect_stdio_merged()
	debugger.run()
	defer { debugger.close() }
	C.close(debugger.stdio_fd[0]); debugger.stdio_fd[0] = -1
	deadline := time.sys_mono_now() + 115 * time.second
	for debugger.is_alive() && time.sys_mono_now() < deadline { time.sleep(100 * time.millisecond) }
	timed_out := debugger.is_alive()
	if timed_out { debugger.signal_kill() }
	output := debugger.stdout_slurp()
	debugger.wait()
	os.write_file(work + '/lldb.log', output)!
	os.write_file(work + '/exit.json', json2.encode({'code': debugger.code.str(), 'timed_out': timed_out.str()}))!
	for path, expected in hashes {
		if winesource.file_digest(path)! != expected { return error('debugger input changed: ' + path) }
	}
	os.write_file(work + '/selected-inputs-verified.json', json2.encode(hashes))!
	if debugger.code != 0 || timed_out { return error('debugger replay failed; retain partial output') }
	println(output)
}

fn main() { check() or { eprintln(err.msg()); exit(1) } }
