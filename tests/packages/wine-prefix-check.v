// SPDX-License-Identifier: GPL-2.0-or-later
// Measure actual prefix captures and retain the old V address-escape control.
module main

import crypto.sha256
import json2
import os

struct PrefixRun {
	name string
	argv []string
	compile_exit int
	run_exit int
	cycles int
	expected_retained_bytes u64
}

struct PrefixProof {
	format int = 1
	scope string = 'ordinary host prefix capture/recheck/double-close; no native Wine claim'
	compiler string
	inputs map[string]string
	outputs map[string]string
	runs []PrefixRun
}

fn digest(path string) !string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return sha256.hexhash(text)
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
	if os.args.len != 4 { return error('usage: wine-prefix-check V WORKTREE NEW_OUTPUT') }
	v := os.real_path(os.args[1])
	root := os.real_path(os.args[2])
	out := os.abs_path(os.args[3])
	if os.exists(out) { return error('prefix proof requires a new output directory') }
	os.mkdir_all(out)!
	os.chmod(out, 0o700)!
	mut inputs := map[string]string{}
	for path in [v, os.executable(), @FILE, root + '/desktop/tools/tests/heap_tracker.h',
		root + '/tools/packages/wineadapter/prefix.c.v', root + '/tools/packages/wineadapter/patch.v',
		root + '/tools/packages/wineadapter/prefix_test.v'] {
		inputs[path] = digest(path)!
	}
	prefix := os.read_file(root + '/tools/packages/wineadapter/prefix.c.v')!
	test := os.read_file(root + '/tools/packages/wineadapter/prefix_test.v')!
	if !test.contains('for _ in 0 .. 1000 {') || !test.contains('assert C.vinix_heap_end() == 0') {
		return error('prefix test must measure 1000 real cycles with a zero-byte assertion')
	}
	mut runs := []PrefixRun{}
	for name in ['fixed', 'sanitized', 'old-control']! {
		module_dir := out + '/' + name
		os.mkdir(module_dir)!
		os.write_file(module_dir + '/v.mod', "Module { name: 'wineadapter' }\n")!
		mut source := prefix
		mut variant := test.replace('@VMODROOT/../../../desktop/tools/tests/heap_tracker.h', root + '/desktop/tools/tests/heap_tracker.h')
		if name == 'old-control' {
			source = source.replace('C.fstat(fd, unsafe { &info })', 'C.fstat(fd, &info)')
			source = source.replace('C.fstat(fd, unsafe { &source })', 'C.fstat(fd, &source)')
			variant = variant.replace('for _ in 0 .. 1000 {', 'for _ in 0 .. 64 {')
			variant = variant.replace('assert C.vinix_heap_end() == 0', 'assert C.vinix_heap_end() == 165888')
		}
		os.write_file(module_dir + '/prefix.c.v', source)!
		os.write_file(module_dir + '/prefix_test.v', variant)!
		os.cp(root + '/tools/packages/wineadapter/patch.v', module_dir + '/patch.v')!
		mut argv := [v, '-backend', 'c', '-cc', 'clang', '-nocache', '-gc', 'none', '-manualfree',
			'-d', 'track_heap', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-keepc']
		if name == 'sanitized' {
			argv << ['-cflags', '-fsanitize=address,undefined', '-ldflags', '-fsanitize=address,undefined']
		}
		argv << ['-o', module_dir + '/check', module_dir + '/prefix_test.v']
		code := invoke(argv, module_dir + '/compile.log')!
		if code != 0 { return error('prefix proof compilation failed: ' + name) }
		run_code := invoke([module_dir + '/check'], module_dir + '/run.log')!
		if run_code != 0 { return error('prefix proof execution failed: ' + name) }
		cfile := module_dir + '/check.c'
		generated := os.read_file(cfile)!
		old_stat := 'struct stat* source = (struct stat*)memdup('
		old_info := 'struct stat* info = (struct stat*)memdup('
		fixed_stat := 'struct stat source = (struct stat){0};'
		fixed_info := 'struct stat info = (struct stat){0};'
		if (name == 'old-control' && (generated.count(old_stat) != 1 || generated.count(old_info) != 2))
			|| (name != 'old-control' && (generated.count(fixed_stat) != 1 || generated.count(fixed_info) != 2
				|| generated.contains(old_stat) || generated.contains(old_info))) {
			return error('generated prefix stat ownership differs: ' + name)
		}
		runs << PrefixRun{name: name, argv: argv, compile_exit: code, run_exit: run_code,
			cycles: if name == 'old-control' { 64 } else { 1000 },
			expected_retained_bytes: if name == 'old-control' { u64(165888) } else { u64(0) }}
	}
	for path, expected in inputs { if digest(path)! != expected { return error('prefix proof input changed: ' + path) } }
	mut outputs := map[string]string{}
	for path in os.walk_ext(out, '') { if os.is_file(path) { outputs[path[out.len + 1..]] = digest(path)! } }
	os.write_file(out + '/proof.json', json2.encode(PrefixProof{compiler: v, inputs: inputs, outputs: outputs, runs: runs}) + '\n')!
	println('WINE PREFIX lifetime fixed1000+sanitized1000 zero bytes; old-control64 retained165888 PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
