// SPDX-License-Identifier: GPL-2.0-or-later
// Retained host regression for the audio source inventory's CPU fixture.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time

#include <errno.h>

const retained = '/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/fixture-host-01'
const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const kernel = '/Users/alex/Library/Caches/vinix-codex/section14/audio-peer-login-20261026/kernel-evidence'
const cap = u64(512) << 20

struct CompilerPin {
	path string
	sha256 string
}

fn charged(output string) []string {
	parent := os.dir(retained)
	return [retained, retained + '.inventory.json', parent + '/fixture-setup',
		parent + '/fixture-setup.v', parent + '/fixture-setup.c', parent + '/fixture-setup-build.log',
		parent + '/fixture-maintained-01', parent + '/fixture-maintained-02', os.dir(output)]
}

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	return hash.sum([]u8{}).hex()
}

fn tree(path string, depth int, started i64, mut result map[string]string) ! {
	if depth > 64 || result.len > 200000 || recoveryguard.deadline_expired(started, 120000) {
		return error('input tree exceeds bounded scope')
	}
	kind := os.lstat(path)!.mode & 0o170000
	if kind == 0o040000 {
		result[path] = 'directory'
		mut names := os.ls(path)!
		names.sort()
		for name in names { tree(path + '/' + name, depth + 1, started, mut result)! }
	} else if kind == 0o100000 { result[path] = digest(path)! }
	else if kind == 0o120000 {
		result['literal-link:' + path] = os.readlink(path)!
		result['resolved-link:' + path] = os.real_path(path)
	} else { return error('nonregular input: ' + path) }
}

fn inputs() !map[string]string {
	mut result := map[string]string{}
	mut compiler_names := os.ls(os.dir(compiler))!
	compiler_names.sort()
	if compiler_names != ['snapshot.json', 'thirdparty', 'v', 'v.mod', 'vlib'] {
		return error('qualified compiler root entries differ')
	}
	for path in [retained + '/source', os.dir(compiler) + '/vlib', os.dir(compiler) + '/thirdparty'] {
		tree(path, 0, time.sys_mono_now(), mut result)!
	}
	for path in [compiler, os.dir(compiler) + '/v.mod', os.dir(compiler) + '/snapshot.json',
		os.dir(os.dir(compiler)) + '/overlay-before.json', os.dir(os.dir(compiler)) + '/changes.json',
		os.dir(os.dir(compiler)) + '/bundle.json', retained + '/audio-runtime', @FILE, os.executable(),
		kernel + '/kernel-seal.json', kernel + '/kernel-aarch64/bin/vinix', '/usr/bin/cc',
		'/usr/bin/arch', '/bin/sh', '/bin/df', '/usr/bin/uname', '/usr/bin/file', '/usr/bin/mktemp', '/bin/rm'] {
		result[path] = digest(path)!
	}
	if result[compiler] != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		|| result[os.dir(os.dir(compiler)) + '/overlay-before.json'] != '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
		|| result[os.dir(os.dir(compiler)) + '/changes.json'] != '4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21'
		|| result[os.dir(os.dir(compiler)) + '/bundle.json'] != '32d8bc5f46c953aeb5e9ad1ad63e182f10752fe270983943a22c040016617976' {
		return error('qualified compiler binding differs')
	}
	mut actual_compiler := map[string]string{}
	for path, value in result {
		if path.starts_with(os.dir(compiler) + '/') { actual_compiler[path] = value }
	}
	mut expected_compiler := map[string]string{}
	for pin in json2.decode[[]CompilerPin](os.read_file(os.dir(os.dir(compiler)) + '/overlay-before.json')!)! {
		expected_compiler[os.dir(compiler) + '/' + pin.path] = pin.sha256
	}
	if actual_compiler != expected_compiler { return error('complete compiler root differs from retained overlay map') }
	return result
}

fn copy_tree(source string, target string, depth int, started i64) ! {
	if depth > 64 || recoveryguard.deadline_expired(started, 120000) { return error('source copy exceeds bounded scope') }
	kind := os.lstat(source)!.mode & 0o170000
	if kind == 0o040000 {
		os.mkdir(target)!
		for name in os.ls(source)! { copy_tree(source + '/' + name, target + '/' + name, depth + 1, started)! }
	} else if kind == 0o100000 { os.cp(source, target)! }
	else if kind == 0o120000 { os.symlink(os.readlink(source)!, target)! }
	else { return error('nonregular source snapshot entry: ' + source) }
}

fn run(arguments []string, output string, label string, expected int) ! {
	os.write_file(output + '/' + label + '.argv.json', json2.encode(arguments))!
	mut failure := ''
	result := nativeguard.supervise(arguments, retained + '/source', output, charged(output),
		output + '/' + label + '.log', output + '/' + label + '-df', nativeguard.Limits{
			start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: cap - (u64(2) << 20), wall_ms: 180000, sample_ms: 1000
		}) or { failure = recoveryguard.bounded_message(err.msg()); nativeguard.Result{} }
	os.write_file(output + '/' + label + '.result.json', json2.encode(result))!
	os.write_file(output + '/' + label + '.error.json', json2.encode({'error': failure}))!
	if failure != '' || result.reason != '' || !result.group_observed
		|| !result.cleanup.reaped || !result.cleanup.group_empty || result.cleanup.final_wait != -1
		|| result.cleanup.final_errno != C.ECHILD || result.cleanup.exit_code != expected {
		return error('command status or cleanup differs: ' + label)
	}
}

fn check() ! {
	$if prod {} $else { return error('compile this checker with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('audio-fixture-closure-check.v').to_string()) {
		return error('compiled checker source differs')
	}
	if os.args.len != 2 { return error('use audio-fixture-closure-check NEW_EXTERNAL_DIRECTORY') }
	output := os.abs_path(os.args[1])
	parent := os.dir(output)
	if os.is_link(parent) || !os.is_dir(parent) || os.real_path(parent) != parent
		|| os.exists(output) || os.is_link(output) { return error('requires a new state path below a canonical existing parent') }
	os.mkdir(output, mode: 0o700)!
	nativeguard.watch_interrupts()!
	admission := nativeguard.actual_df(output, output + '/admission-df.log')!
	if admission.available < u64(2) << 30 { return error('actual df below 2GiB admission') }
	if !os.executable().starts_with(parent + '/') { return error('checker executable must be inside its charged state parent') }
	initial_allocation := nativeguard.allocated(charged(output), os.lstat(output)!.dev)!
	os.write_file(output + '/admission.json', json2.encode({'allocated_bytes': initial_allocation.str(),
		'cap_bytes': cap.str(), 'metric': 'Pathname allocation; shared hardlinks may be counted repeatedly, unlike du'}))!
	if initial_allocation > cap - (u64(16) << 20) {
		return error('insufficient projected namespace allowance')
	}
	for name, _ in os.environ() { os.unsetenv(name) }
	for directory in ['tmp', 'modules', 'generated'] { os.mkdir(output + '/' + directory, mode: 0o700)! }
	mut environment := {
		'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'TMPDIR': output + '/tmp', 'VTMP': output + '/tmp', 'VMODULES': output + '/modules',
		'V': compiler, 'VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0',
		'V_MACOS_V3_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'VFLAGS': '-nocache',
		'VINIX_ROOT': retained + '/source', 'VINIX_AUDIO_KERNEL_EVIDENCE': kernel,
	}
	for name, value in environment { os.setenv(name, value, true) }
	before := inputs()!
	os.write_file(output + '/inputs-before.json', json2.encode(before))!
	os.write_file(output + '/environment.json', json2.encode(environment))!
	generated := output + '/generated/sandbox.c'
	run([retained + '/source/build-support/security-tools/compile-v-core', 'sandbox', generated, '--arch', 'arm64'], output, 'sandbox', 0)!
	if os.lstat(generated)!.mode & 0o170000 != 0o100000 || os.lstat(generated)!.size == 0 {
		return error('sandbox generation did not produce ordinary nonempty C')
	}
	clone := output + '/missing-fixture-source'
	copy_tree(retained + '/source', clone, 0, time.sys_mono_now())!
	os.mv(clone + '/tests/native-policy-tools/cpufixture', clone + '/tests/native-policy-tools/omitted-cpufixture')!
	mut original_tree := map[string]string{}
	mut cloned_tree := map[string]string{}
	tree(retained + '/source', 0, time.sys_mono_now(), mut original_tree)!
	tree(clone, 0, time.sys_mono_now(), mut cloned_tree)!
	mut expected_clone := map[string]string{}
	for name, value in original_tree {
		cloned_name := name.replace(retained + '/source', clone)
		cloned_value := if name.starts_with('resolved-link:') { value.replace(retained + '/source', clone) } else { value }
		expected_clone[cloned_name.replace('/tests/native-policy-tools/cpufixture', '/tests/native-policy-tools/omitted-cpufixture')] = cloned_value
	}
	if cloned_tree != expected_clone { return error('source clone differs beyond the fixture directory rename') }
	os.write_file(output + '/source-tree.json', json2.encode(original_tree))!
	os.write_file(output + '/omitted-tree.json', json2.encode(cloned_tree))!
	os.setenv('VINIX_ROOT', clone, true)
	environment['VINIX_ROOT'] = clone
	os.write_file(output + '/missing-environment.json', json2.encode(environment))!
	run([retained + '/audio-runtime', '--prepare-only', '--arch', 'aarch64',
		'--scenario', 'packages-audio-basic', '--kernel', kernel + '/kernel-aarch64/bin/vinix',
		'--state-dir', output + '/missing-fixture-preparation'], output, 'missing', 1)!
	log := os.read_file(output + '/missing.log')!
	expected := 'audio-portal-runtime-check: ls() couldnt open dir "' + clone + '/tests/native-policy-tools/cpufixture"; code: 2\n'
	if log != expected { return error('missing fixture did not refuse at the exact source inventory path') }
	for relative in ['source-before.json', 'cross-probe.c', 'preparation.json', 'run', 'qualification.json'] {
		path := output + '/missing-fixture-preparation/' + relative
		if os.exists(path) || os.is_link(path) { return error('missing fixture proceeded: ' + relative) }
	}
	after := inputs()!
	os.write_file(output + '/inputs-after.json', json2.encode(after))!
	if before != after { return error('selected inputs changed') }
	mut final_clone := map[string]string{}
	tree(clone, 0, time.sys_mono_now(), mut final_clone)!
	if final_clone != cloned_tree { return error('omission fixture changed during refusal') }
	if os.ls(output + '/modules')!.len != 0 { return error('private modules changed') }
	for name in os.ls(output + '/tmp')! {
		if name.contains('cache') { return error('unexpected compiler cache in private temporary state') }
	}
	final_df := nativeguard.actual_df(output, output + '/final-df.log')!
	allocation := nativeguard.allocated(charged(output), os.lstat(output)!.dev)!
	pending_receipt := output + '/receipt.pending.json'
	os.write_file(pending_receipt, json2.encode({
		'result': 'PASS', 'scope': 'Host sandbox C generation and exact source inventory refusal; no target compilation or VM',
		'checker_source_sha256': digest(@FILE)!, 'sandbox_c_sha256': digest(generated)!,
		'inputs_before_sha256': digest(output + '/inputs-before.json')!,
		'inputs_after_sha256': digest(output + '/inputs-after.json')!,
		'allocated_bytes_before_receipt': allocation.str(), 'available_bytes_before_receipt': final_df.available.str(),
		'cap_bytes': cap.str(), 'limits': 'Sampled namespace allocation, including retained original bundle; trusted host inherited groups only',
	}))!
	post_receipt_df := nativeguard.actual_df(output, output + '/post-receipt-df.log')!
	if post_receipt_df.available < u64(1) << 30 || nativeguard.allocated(charged(output), os.lstat(output)!.dev)! > cap {
		return error('final namespace cap or actual df floor refused')
	}
	os.mv(pending_receipt, output + '/receipt.json')!
	println('PASS audio CPU fixture sandbox generation and exact early omission refusal; no target or guest executed')
}

fn main() { check() or { eprintln(err); exit(1) } }
