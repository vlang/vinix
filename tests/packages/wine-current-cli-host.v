// SPDX-License-Identifier: GPL-2.0-or-later
// Selected-input host build/control receipt; never stages an image or starts QEMU.
module main

import json2
import os
import tests.packages.winesource

fn invoke(argv []string, environment map[string]string, log string, expected int) ! {
	os.write_file(log + '.argv.json', json2.encode(argv))!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_environment(environment)
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	defer { unsafe { output.free() } }
	child.wait()
	os.write_file(log, output)!
	os.write_file(log + '.exit.json', json2.encode({'exit': child.code}))!
	if child.code != expected { return error('host command exit differs: ' + log) }
}

fn verify(inputs map[string]string) ! {
	for path, expected in inputs {
		actual := winesource.file_digest(path)!
		defer { unsafe { actual.free() } }
		if actual != expected { return error('host selected input changed: ' + path) }
	}
}

fn retain_sources(dump_path string, inputs map[string]string, work string) ! {
	text := os.read_file(dump_path)!
	defer { unsafe { text.free() } }
	paths := text.split_into_lines()
	defer { unsafe { for path in paths { path.free() }; (&array(&paths)).free() } }
	os.mkdir_all(work + '/source-blobs')!
	mut mapping := map[string]string{}
	for path in paths {
		expected := inputs[path] or { return error('discovered input was not admitted') }
		destination := work + '/source-blobs/' + expected
		defer { unsafe { destination.free() } }
		if !os.exists(destination) { os.cp(path, destination)! }
		if winesource.file_digest(destination)! != expected || winesource.file_digest(path)! != expected {
			return error('retained discovered source differs')
		}
		mapping[path] = destination.clone()
	}
	os.write_file(dump_path + '.retained.json', json2.encode(mapping))!
}

fn check() ! {
	if os.args.len != 4 { return error('usage: wine-current-cli-host FRESH_OUTPUT V CLANG') }
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.abs_path(os.args[1])
	v := os.real_path(os.args[2])
	clang := os.real_path(os.args[3])
	if os.exists(work) { return error('host receipt output already exists') }
	os.mkdir_all(work)!
	os.cp(@FILE, work + '/producer.v')!
	os.cp(os.executable(), work + '/producer')!
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), v, clang, os.dir(v) + '/vlib/os/os.v',
		root + '/tests/packages/winecurrent/admission.v', root + '/tests/packages/winesource/closure.v',
		root + '/tests/packages/wine-current-cli-check.v', root + '/tests/packages/wine-startup-check.v'] {
		inputs[path] = winesource.file_digest(path)!
	}
	environment := {
		'PATH': '/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
		'HOME': '/Users/alex'
		'TMPDIR': work
		'VEXE': v
		'V_MACOS_V3_CALLER_VEXE': v
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1'
		'V_C_ERROR_BUG_REPORT_DISABLED': '1'
	}
	os.write_file(work + '/environment.json', json2.encode(environment))!
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	mut outputs := map[string]string{}
	for name in ['wine-current-cli-check', 'wine-startup-check'] {
		prefix := work + '/' + name
		argv := [v, '-prod', '-gc', 'none', '-manualfree', '-cc', clang,
			'-path', '@vlib|' + root + '|' + root + '/tests/hardware-platform|@vmodules',
			'-o', prefix, root + '/tests/packages/' + name + '.v']
		mut discovery := argv.clone()
		discovery.insert(1, ['-print-watched-files', '-dump-files', prefix + '.sources-before.txt'])
		invoke(discovery, environment, prefix + '.discover.log', 0)!
		winesource.capture(prefix + '.sources-before.txt', mut inputs)!
		retain_sources(prefix + '.sources-before.txt', inputs, work)!
		mut build := argv.clone()
		build.insert(1, ['-dump-files', prefix + '.sources-built.txt'])
		invoke(build, environment, prefix + '.build.log', 0)!
		winesource.admit(prefix + '.sources-before.txt', prefix + '.sources-built.txt', inputs)!
		outputs[prefix] = winesource.file_digest(prefix)!
	}
	verify(inputs)!
	os.write_file(work + '/inputs-built.json', json2.encode(inputs))!
	invoke([work + '/wine-current-cli-check', work + '/controls'], environment, work + '/controls.log', 0)!
	refused_output := work + '/must-not-exist'
	invoke([work + '/wine-startup-check', 'server', refused_output, '/missing-kernel',
		'/missing-extras', '/missing-sysroot', '/missing-gcc', work + '/controls/selected', '0'.repeat(64)],
		environment, work + '/controller-refusal.log', 1)!
	if os.exists(refused_output) || !os.read_file(work + '/controller-refusal.log')!.contains('current CLI digest mismatch') {
		return error('controller did not refuse wrong digest before creating output')
	}
	verify(inputs)!
	verify(outputs)!
	os.write_file(work + '/inputs-after.json', json2.encode(inputs))!
	os.write_file(work + '/outputs.json', json2.encode(outputs))!
	os.write_file(work + '/completed.json', json2.encode({
		'purpose': 'current CLI host admission and staging controls only; no image or guest'
		'source_scope': 'parsed-v1 for both built programs; producer and selected compiler inputs'
		'limitation': 'complete compiler executable/library/header/linker closure is not admitted'
		'controls': work + '/controls/result.json'
		'controls_sha256': winesource.file_digest(work + '/controls/result.json')!
	}))!
	println('WINE CURRENT CLI host controls completed: ' + work)
}

fn main() { check() or { eprintln(err.msg()); exit(1) } }
