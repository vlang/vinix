// SPDX-License-Identifier: GPL-2.0-or-later
// Checks the source export without preparing or writing a guest image.
module main

import crypto.sha256
import json2
import os
import tools.development.sourcecore

struct SourcePin { path string sha256 string }
struct SourceCheck { name string argv []string exit_code int expected_failure string artifacts []SourcePin }
struct SourceReceipt { schema int = 1 revision string compiler string inputs []SourcePin checks []SourceCheck }

fn source_pin(path string) !SourcePin {
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	return SourcePin{path: path, sha256: sha256.sum(data).hex()}
}

fn source_tree(path string) ![]SourcePin {
	mut pins := []SourcePin{}
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		file := path + '/' + name
		kind := (os.lstat(file)!).mode & 0o170000
		if kind == 0o040000 { pins << source_tree(file)! }
		else if kind == 0o100000 { pins << source_pin(file)! }
		else { return error('source qualification requires ordinary inputs: ' + file) }
	}
	return pins
}

fn source_command(name string, argv []string, work string, expected string, artifact string) !SourceCheck {
	command := work + '/' + name + '.argv.json'
	os.write_file(command, json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	child.set_args(argv[1..])
	child.set_work_folder(work)
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	code := child.code
	child.close()
	log := work + '/' + name + '.log'
	os.write_file(log, output)!
	if (expected == '' && code != 0) || (expected != '' && (code == 0 || !output.contains(expected))) {
		return error('unexpected source qualification result: ' + log)
	}
	mut pins := [source_pin(command)!, source_pin(log)!]
	if expected == '' {
		if !os.is_file(artifact) || (os.stat(artifact)!).size < 1024 { return error('package CLI C was not generated') }
		pins << source_pin(artifact)!
	}
	println(name + ' PASS')
	return SourceCheck{name: name, argv: argv, exit_code: code, expected_failure: expected, artifacts: pins}
}

fn source_qualification() ! {
	if os.args.len != 2 { return error('usage: check-development-source NEW_EXTERNAL_DIRECTORY; set V to the selected compiler') }
	root := os.dir(os.dir(os.dir(@FILE)))
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) || work.starts_with(root + '/') { return error('results require a fresh external directory') }
	v := os.real_path(os.find_abs_path_of_executable(os.getenv_opt('V') or { return error('set V to the selected compiler') })!)
	os.mkdir_all(work)!
	for key in ['VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	for key, value in {'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_C_ERROR_BUG_REPORT_DISABLED': '1'} { os.setenv(key, value, true) }
	os.mkdir(work + '/empty-modules')!
	os.setenv('VMODULES', work + '/empty-modules', true)
	revision := sourcecore.revision(root)!
	source := work + '/source'
	os.mkdir(source)!
	sourcecore.export_native_userland(root, revision, source)!
	mut inputs := source_tree(source)!
	inputs << source_pin(v)!
	for directory in ['vlib', 'thirdparty'] { inputs << source_tree(os.dir(v) + '/' + directory)! }
	inputs << source_pin(os.dir(v) + '/v.mod')!
	for path in ['tools/development/sourcecore/native.v', 'tools/development/sourcecore/source.v',
		'tests/native-guest-tools/development-main.v', 'tests/native-guest-tools/check-development-source.v'] {
		target := work + '/harness/' + path
		os.mkdir_all(os.dir(target))!
		os.cp(root + '/' + path, target)!
		if source_pin(root + '/' + path)!.sha256 != source_pin(target)!.sha256 { return error('harness changed during retention') }
		inputs << source_pin(target)!
	}
	os.write_file(work + '/inputs.json', json2.encode(inputs) + '\n')!
	mut checks := []SourceCheck{}
	for arch in ['arm64', 'amd64'] {
		output := work + '/package-' + arch + '.c'
		flags := [v, '-backend', 'c', '-cc', 'clang', '-prod', '-os', 'linux', '-arch', arch,
			'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'no_backtrace', '-d', 'no_segfault_handler']
		argv := [...flags, '-path', sourcecore.native_package_module_path(source), '-o', output, source + '/tools/packages/main.v']
		checks << source_command('package-' + arch, argv, work, '', output)!
		audio := source + '/tools/packages/audiopcm'
		withheld := work + '/withheld-audiopcm'
		os.mv(audio, withheld)!
		checks << source_command('missing-audiopcm-' + arch, argv, work, 'cannot import module "tools.packages.audiopcm"', '') or {
			os.mv(withheld, audio)!
			return err
		}
		os.mv(withheld, audio)!
		bad_path := [...flags, '-path', '@vlib|' + source, '-o', output, source + '/tools/packages/main.v']
		checks << source_command('missing-account-path-' + arch, bad_path, work, 'cannot import module "authclient"', '')!
	}
	for pin in inputs { if source_pin(pin.path)!.sha256 != pin.sha256 { return error('retained input changed: ' + pin.path) } }
	os.write_file(work + '/qualification.json', json2.encode(SourceReceipt{revision: revision, compiler: v, inputs: inputs, checks: checks}) + '\n')!
	println('Native development committed source: 6 checks PASS')
}

fn main() { source_qualification() or { eprintln(err); exit(1) } }
