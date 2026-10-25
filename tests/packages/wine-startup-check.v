// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded x86 diagnostics; reused signed extras never constitute qualification.
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import tests.packages.winesource

fn invoke(arguments []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(arguments))!
	mut child := os.new_process(arguments[0])
	defer { child.close() }
	child.set_args(arguments[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	defer { unsafe { output.free() } }
	child.wait()
	os.write_file(log, output)!
	if child.code != 0 { return error('startup diagnostic producer failed: ' + log) }
}

fn inventory(directory string, mut files map[string]string) ! {
	names := os.ls(directory)!
	defer { unsafe { for name in names { name.free() }; (&array(&names)).free() } }
	for name in names {
		if files.len > 50000 { return error('diagnostic inventory exceeded bound') }
		path := directory + '/' + name
		defer { unsafe { path.free() } }
		st := os.lstat(path)!
		match st.get_filetype() {
			.directory { inventory(path, mut files)! }
			.regular { files[path] = winesource.file_digest(path)! }
			.symbolic_link { files[path] = 'symlink:' + os.readlink(path)! }
			else { return error('unsupported diagnostic input object: ' + path) }
		}
	}
}

fn verify(inputs map[string]string) ! {
	for path, expected in inputs {
		actual := if expected.starts_with('symlink:') { 'symlink:' + os.readlink(path)! } else { winesource.file_digest(path)! }
		defer { unsafe { actual.free() } }
		if actual != expected { return error('diagnostic input changed: ' + path) }
	}
}

fn check() ! {
	$if prod {} $else { return error('compile startup controller with -prod') }
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-startup-check.v').to_string()) {
		return error('compiled startup controller source differs')
	}
	if winesource.file_digest(os.dir(@FILE) + '/winesource/closure.v')! != sha256.hexhash($embed_file('winesource/closure.v').to_string()) {
		return error('compiled startup source closure admission differs')
	}
	if os.args.len != 7 || os.args[1] !in ['process', 'server'] {
		return error('usage: wine-startup-check process|server OUTPUT KERNEL EXTRAS_OR_DASH SYSROOT GCC_RUNTIME')
	}
	root := hwhost.find_root(@FILE)!
	mode := os.args[1]
	work := os.abs_path(os.args[2])
	kernel := os.real_path(os.args[3])
	extras := if mode == 'server' { os.real_path(os.args[4]) } else { '' }
	sysroot := os.real_path(os.args[5])
	gcc := os.real_path(os.args[6])
	if os.exists(work) { return error('startup output already exists') }
	os.mkdir_all(work)!
	host := hwhost.find_host(root, 'x86_64', '')!
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), host.v, host.qemu, host.firmware, kernel,
		os.dir(@FILE) + '/winesource/closure.v', '/opt/homebrew/opt/llvm/bin/clang'] {
		inputs[path] = winesource.file_digest(path)!
	}
	for _, path in plainiso.inputs(root)! { inputs[path] = winesource.file_digest(path)! }
	inventory(root + '/tests/hardware-platform/hwhost', mut inputs)!
	inventory(root + '/tests/hardware-platform/plainiso', mut inputs)!
	if extras != '' { inventory(extras, mut inputs)! }
	source := root + '/tests/packages/' + if mode == 'process' { 'wine-process-probe/main.v' } else { 'wine-native/main.v' }
	directory := work + '/build'
	os.mkdir_all(directory)!
	cfile := directory + '/guest.c'
	mut command := [host.v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', 'amd64',
		'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
		'-path', '@vlib|' + root + '|' + root + '/tools/accounts|@vmodules', '-o', cfile, source]
	mut discovery := command.clone()
	discovery.insert(1, ['-print-watched-files', '-dump-files', directory + '/sources-before.txt'])
	invoke(discovery, directory + '/discover.log')!
	winesource.capture(directory + '/sources-before.txt', mut inputs)!
	command.insert(1, ['-dump-files', directory + '/sources-built.txt'])
	invoke(command, directory + '/v.log')!
	winesource.admit(directory + '/sources-before.txt', directory + '/sources-built.txt', inputs)!
	vlib := os.dir(host.v) + '/vlib'
	os.write_file(directory + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		vlib + '/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + vlib + '/sync/thread_helper.h"\n')!
	invoke(['/opt/homebrew/opt/llvm/bin/clang', '--target=x86_64-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + gcc, '-fuse-ld=lld', '-O1', '-w', '-fno-stack-protector', '-static',
		'-D_GNU_SOURCE', '-Wno-error=incompatible-pointer-types', cfile, directory + '/runtime.c',
		'-lm', '-lpthread', '-o', directory + '/guest'], directory + '/cc.log')!
	verify(inputs)!
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	mut built := map[string]string{}
	inventory(directory, mut built)!
	os.write_file(work + '/built-before.json', json2.encode(built))!
	os.write_file(work + '/declaration.json', json2.encode({
		'mode': mode, 'source_root': root, 'kernel': kernel, 'extras': extras,
		'source_scope': 'parsed-v1', 'purpose': 'diagnostic-only; reused extras cannot qualify Wine',
		'input_scope': 'selected paths; sysroot, GCC runtime, headers and linker closure are not admitted',
		'VEXE': os.getenv('VEXE'), 'V_MACOS_V3_CALLER_VEXE': os.getenv('V_MACOS_V3_CALLER_VEXE'),
		'V_MACOS_V3_CALLER_VEXE_PRESENT': os.getenv('V_MACOS_V3_CALLER_VEXE_PRESENT'),
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': os.getenv('V_MACOS_V3_CALLER_VCHILD_PRESENT'),
		'V_MACOS_V3_NO_FALLBACK': os.getenv('V_MACOS_V3_NO_FALLBACK'),
	}))!
	if extras != '' {
		// APFS clone saves space; never mutate the frozen producer or its ISO.
		os.mkdir_all(work + '/boot/rootfs')!
		invoke(['/bin/cp', '-cRp', extras + '/.', work + '/boot/rootfs'], work + '/clone.log')!
	}
	scenario := hwhost.Scenario{
		name: 'Wine-startup-' + mode
		arches: ['x86_64']
		qemu_x86_64: ['-cpu', 'max']
		required: [if mode == 'process' { 'HWTEST PASS Wine-process-primitives' } else { 'HWTEST PASS packaged-Wine' }]
		forbidden: ['HWTEST FAIL', 'Kernel panic', 'KERNEL PANIC', 'FATAL EXCEPTION']
		ending: .running
	}
	outcome := hwhost.run_scenario(hwhost.Host{ ...host, root: plainiso.prepare(root, work)! },
		scenario, hwhost.Run{kernel: kernel, guest: directory + '/guest', state: work + '/boot', timeout: if mode == 'process' { 45 } else { 240 }, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	verify(inputs)!
	verify(built)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(work + '/built-verified.json', json2.encode(built))!
	if !outcome.passed || outcome.interrupted || outcome.reason != '' { return error('Wine startup diagnostic failed: ' + outcome.reason) }
	println('WINE STARTUP DIAGNOSTIC ' + mode + ' completed: ' + work)
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err.msg()); exit(1) }; return }
	check() or { eprintln(err.msg()); exit(1) }
}
