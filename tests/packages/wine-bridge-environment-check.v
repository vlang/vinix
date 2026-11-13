// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import tests.packages.winesource

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 300)!
}
fn compile_v(args []string, directory string, mut inputs map[string]string) ! {
	os.mkdir_all(directory)!
	mut discovery := args.clone()
	discovery.insert(1, ['-print-watched-files', '-dump-files', directory + '/sources-before.txt'])
	invoke(discovery, directory + '/discover.log')!
	winesource.capture(directory + '/sources-before.txt', mut inputs)!
	os.write_file(directory + '/inputs-before.json', json2.encode(inputs))!
	mut actual := args.clone()
	actual.insert(1, ['-dump-files', directory + '/sources-built.txt'])
	invoke(actual, directory + '/build.log')!
	winesource.admit(directory + '/sources-before.txt', directory + '/sources-built.txt', inputs)!
}
fn verify(inputs map[string]string) ! {
	for path, expected in inputs {
		if winesource.file_digest(path)! != expected { return error('bridge environment input changed: ' + path) }
	}
}
fn run() ! {
	if os.args.len != 8 { return error('usage: CHECK FRESH_OUTPUT V CLANG ARM_SYSROOT ARM_GCC X86_SYSROOT X86_GCC') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('fresh output required') }
	test := root + '/tests/packages/winebridgeenvironmenttest/environment_test.v'
	helper := root + '/tools/packages/wineadapter/bridge_environment.v'
	runner := root + '/tools/packages/wine-runner.v'
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-bridge-environment-check.v').to_string())
		|| winesource.file_digest(test)! != sha256.hexhash($embed_file('winebridgeenvironmenttest/environment_test.v').to_string())
		|| winesource.file_digest(helper)! != sha256.hexhash($embed_file('../../tools/packages/wineadapter/bridge_environment.v').to_string())
		|| winesource.file_digest(runner)! != sha256.hexhash($embed_file('../../tools/packages/wine-runner.v').to_string()) { return error('compiled bridge environment sources differ') }
	mut inputs := map[string]string{}
	mut outputs := map[string]string{}
	v := os.args[2]; cc := os.args[3]
	for path in [@FILE, test, helper, runner, os.executable(), v, cc, root + '/desktop/tools/tests/heap_tracker.h',
		os.dir(v) + '/vlib/os/execute_capture_nix.h', os.dir(v) + '/vlib/sync/thread_helper.h'] {
		inputs[path] = winesource.file_digest(path)!
	}
	os.mkdir_all(work)!
	for mode in ['normal', 'prod', 'sanitized']! {
		directory := work + '/' + mode
		binary := directory + '/check'
		mut args := [v, '-backend', 'c', '-cc', cc, '-cflags', '-Wno-error=incompatible-pointer-types', '-gc', 'none', '-manualfree', '-keepc',
			'-d', 'track_heap', '-path', '@vlib|' + root + '|@vmodules', '-o', binary, test]
		if mode != 'normal' { args.insert(1, '-prod') }
		if mode == 'sanitized' { args.insert(1, ['-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']) }
		compile_v(args, directory, mut inputs)!
		for path in [binary, binary + '.c'] { outputs[path] = winesource.file_digest(path)! }
		os.write_file(directory + '/artifacts-before-run.json', json2.encode(outputs))!
		invoke([binary], directory + '/run.log')!
		verify(outputs)!
		log := os.read_file(directory + '/run.log')!
		if !log.contains('WINE BRIDGE ENVIRONMENT PASS top-level reset; nested handoff; borrowed descriptor; 1000 cycles')
			|| log.contains('AddressSanitizer') || log.contains('runtime error:') { return error('bridge environment checks failed') }
	}
	// Compile the actual production runner for both supported guest targets.
	for arch in ['aarch64', 'x86_64']! {
		directory := work + '/' + arch
		cfile := directory + '/wine-runner.c'
		compile_v([v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
			'-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler',
			'-path', '@vlib|' + root + '|' + root + '/tools/packages|@vmodules', '-o', cfile, runner], directory, mut inputs)!
		runtime := directory + '/runtime.c'
		os.write_file(runtime, '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' + os.dir(v) + '/vlib/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + os.dir(v) + '/vlib/sync/thread_helper.h"\n')!
		index := if arch == 'aarch64' { 4 } else { 6 }
		invoke([cc, '--target=' + arch + '-linux-musl', '--sysroot=' + os.args[index], '--gcc-install-dir=' + os.args[index + 1],
			'-fuse-ld=lld', '-static', '-O2', '-w', '-D_GNU_SOURCE', '-fno-stack-protector', '-Wno-error=incompatible-pointer-types',
			cfile, runtime, '-lm', '-lpthread', '-o', directory + '/wine-runner'], directory + '/cc.log')!
		for path in [cfile, runtime, directory + '/wine-runner'] { outputs[path] = winesource.file_digest(path)! }
	}
	verify(inputs)!
	verify(outputs)!
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(work + '/outputs-verified.json', json2.encode(outputs))!
	println('WINE BRIDGE ENVIRONMENT CHECK PASS host policy, production, sanitizers and both runner targets')
}
fn main() { run() or { eprintln(err); exit(1) } }
