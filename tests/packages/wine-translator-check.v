// SPDX-License-Identifier: GPL-2.0-or-later
// Qualify one exact local-only TCG argument patch. Native execution is separate.
module main

import crypto.sha256
import json2
import os
import tools.packages.wineadapter

struct TranslatorRun {
	name string
	compile_exit int
	run_exit int
	cycles int = 64
	expected_retained_bytes u64
}

struct TranslatorProof {
	format int = 1
	scope string = 'local-only exact Alpine QEMU instruction patch and host refusal/lifetime tests; no native execution or complete source/redistribution qualification'
	inputs map[string]string
	outputs map[string]string
	runs []TranslatorRun
}

fn digest(path string) !string {
	bytes := os.read_file(path)!
	defer { unsafe { bytes.free() } }
	return sha256.hexhash(bytes)
}

fn invoke(argv []string, log string) !int {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	defer { unsafe { output.free() } }
	child.wait()
	os.write_file(log, output)!
	return child.code
}

fn check() ! {
	if os.args.len != 5 { return error('usage: wine-translator-check V WORKTREE QEMU_INPUT NEW_OUTPUT') }
	v := os.real_path(os.args[1])
	root := os.real_path(os.args[2])
	input := os.real_path(os.args[3])
	out := os.abs_path(os.args[4])
	objdump := '/opt/homebrew/opt/llvm/bin/llvm-objdump'
	if os.exists(out) { return error('translator proof needs a new output directory') }
	os.mkdir_all(out)!
	os.chmod(out, 0o700)!
	mut inputs := map[string]string{}
	for path in [v, os.executable(), @FILE, input, objdump, root + '/desktop/tools/tests/heap_tracker.h',
		root + '/tools/packages/wineadapter/patch.v', root + '/tools/packages/wineadapter/patch_test.v'] {
		inputs[path] = digest(path)!
	}
	if inputs[input] != wineadapter.qemu_splitwx_input { return error('translator proof input differs') }
	bytes := os.read_file(input)!
	defer { unsafe { bytes.free() } }
	patched := wineadapter.splitwx_patch(bytes)!
	defer { unsafe { patched.free() } }
	os.write_file(out + '/qemu-x86_64-patched', patched)!
	for name, path in {'original': input, 'patched': out + '/qemu-x86_64-patched'} {
		if invoke([objdump, '-d', '--start-address=0x85c40', '--stop-address=0x85c78', path], out + '/' + name + '.disassembly.txt')! != 0 {
			return error('cannot retain translator call-site disassembly')
		}
	}
	original_disassembly := os.read_file(out + '/original.disassembly.txt')!
	patched_disassembly := os.read_file(out + '/patched.disassembly.txt')!
	defer { unsafe { original_disassembly.free(); patched_disassembly.free() } }
	if !original_disassembly.contains('ldr\tw1, [x19, #0x2c]')
		|| !patched_disassembly.contains('mov\tw1, #0x1')
		|| !patched_disassembly.contains('mov\tw2, #0x1')
		|| !patched_disassembly.contains('lsl\tx0, x0, #20')
		|| !patched_disassembly.contains('bl\t0xe85a0') {
		return error('translator argument/call disassembly differs')
	}
	test := os.read_file(root + '/tools/packages/wineadapter/patch_test.v')!
	defer { unsafe { test.free() } }
	if !test.contains('for _ in 0 .. 64 {') || !test.contains('assert C.vinix_heap_end() == 0') {
		return error('translator test must measure actual patch and refusal cycles')
	}
	os.setenv('VINIX_WINE_PATCH_INPUT', input, true)
	mut runs := []TranslatorRun{}
	for name in ['normal', 'sanitized']! {
		directory := out + '/' + name
		os.mkdir(directory)!
		os.write_file(directory + '/v.mod', "Module { name: 'wineadapter' }\n")!
		os.cp(root + '/tools/packages/wineadapter/patch.v', directory + '/patch.v')!
		os.write_file(directory + '/patch_test.v', test.replace('@VMODROOT/../../../desktop/tools/tests/heap_tracker.h', root + '/desktop/tools/tests/heap_tracker.h'))!
		mut argv := [v, '-backend', 'c', '-cc', 'clang', '-nocache', '-gc', 'none', '-manualfree',
			'-d', 'track_heap', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-keepc']
		if name == 'sanitized' { argv << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined'] }
		argv << ['-o', directory + '/check', directory + '/patch_test.v']
		code := invoke(argv, directory + '/compile.log')!
		if code != 0 { return error('translator test compilation failed: ' + name) }
		run_code := invoke([directory + '/check'], directory + '/run.log')!
		if run_code != 0 { return error('translator test execution failed: ' + name) }
		runs << TranslatorRun{name: name, compile_exit: code, run_exit: run_code}
	}
	for path, expected in inputs { if digest(path)! != expected { return error('translator proof input changed: ' + path) } }
	mut outputs := map[string]string{}
	for path in os.walk_ext(out, '') { if os.is_file(path) { outputs[path[out.len + 1..]] = digest(path)! } }
	os.write_file(out + '/proof.json', json2.encode(TranslatorProof{inputs: inputs, outputs: outputs, runs: runs}) + '\n')!
	println('WINE TRANSLATOR exact4bytes normal64+sanitized64 zero retained bytes PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
