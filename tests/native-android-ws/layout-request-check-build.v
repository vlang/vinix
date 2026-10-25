// SPDX-License-Identifier: GPL-2.0-or-later
// Small host build with a retained consumed-source snapshot; no guest or full framework build.
module main

import crypto.sha256
import json2
import os
import time

const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const checker_source = 'tests/native-android-ws/layout-request-check.v'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone(from string, to string) ! {
	os.mkdir_all(os.dir(to))!
	r := os.exec(['/bin/cp', '-c', os.real_path(from), to])
	if r.exit_code != 0 || hash(from)! != hash(to)! { return error('clone failed: ' + from) }
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular build evidence: ' + key) }
		}
	}
}

fn command(out string, name string, argv []string) !string {
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(out + '/commands/' + name + '.log', r.output)!
	write_json(out + '/commands/' + name + '.json', {
		'argv': json2.Any(argv)
		'cwd': json2.Any(os.getwd())
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'exit_code': json2.Any(r.exit_code)
		'binary_sha256': json2.Any(hash(os.real_path(argv[0]))!)
		'VROOT': json2.Any(os.getenv('VROOT'))
		'VTMP': json2.Any(os.getenv('VTMP'))
	})!
	if r.exit_code != 0 { return error(name + ' failed:\n' + r.output) }
	return r.output
}

fn closure(out string, label string, compiler string, paths string) !map[string]string {
	listing := command(out, label, [compiler, '-print-v-files', '-enable-globals', '-path', paths, checker_source])!
	mut pins := map[string]string{}
	for line in listing.split_into_lines() {
		path := line.trim_space()
		if path.ends_with('.v') {
			if !path.starts_with('/') { return error('nonabsolute source closure entry') }
			pins[path] = hash(path)!
		}
	}
	if pins.len == 0 { return error('empty source closure') }
	write_json(out + '/' + label + '.json', pins)!
	return pins
}

fn build() ! {
	if os.args.len != 6 { return error('usage: layout-request-check-build COMPILER FRAMEWORK329 JAVA FRESH_BUILD_OUT FRESH_CHECK_OUT') }
	compiler := os.real_path(os.args[1])
	baseline := os.real_path(os.args[2])
	java := os.real_path(os.args[3])
	out := os.abs_path(os.args[4])
	check_out := os.abs_path(os.args[5])
	repo := os.real_path('.')
	for target in [out, check_out] {
		if os.exists(target) || os.is_link(target) { return error('fresh output required') }
		if target == repo || target.starts_with(repo + '/') { return error('external output required') }
	}
	if out == check_out || out.starts_with(check_out + '/') || check_out.starts_with(out + '/') { return error('independent sibling outputs required') }
	if hash(compiler)! != compiler_pin { return error('compiler pin mismatch') }
	os.mkdir_all(out + '/commands')!
	os.mkdir_all(out + '/tmp')!
	os.mkdir_all(out + '/vmodules')!
	os.setenv('VTMP', out + '/tmp', true)
	os.setenv('VMODULES', out + '/vmodules', true)
	os.setenv('VROOT', '/Users/alex/code/v', true)
	clone(os.executable(), out + '/build-runner')!
	clone(repo + '/tests/native-android-ws/layout-request-check-build.v', out + '/build-runner.v')!
	paths := 'tests/native-android-tools|tests/native-android-ws|tests/host-policy|tests/linuxkpi|tests/native-generators|tests/native-guest-tools|build-support|tools|@vlib|@vmodules'
	before := closure(out, 'consumed-before', compiler, paths)!
	mut native := map[string]string{}
	for path, _ in before {
		clone(path, out + '/inputs/' + path.trim_left('/'))!
		for name in os.ls(os.dir(path))! {
			if name.ends_with('.c') || name.ends_with('.h') {
				adjacent := os.dir(path) + '/' + name
				if adjacent !in native && os.is_file(adjacent) {
					native[adjacent] = hash(adjacent)!
					clone(adjacent, out + '/inputs/' + adjacent.trim_left('/'))!
				}
			}
		}
	}
	native[os.real_path('/usr/bin/cc')] = hash(os.real_path('/usr/bin/cc'))!
	write_json(out + '/native-inputs-before.json', native)!
	checker := out + '/layout-request-check'
	command(out, 'compile', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc',
		'-enable-globals', '-cflags', '-O2', '-path', paths, '-o', checker, checker_source])!
	after := closure(out, 'consumed-after', compiler, paths)!
	if before != after { return error('consumed source changed during build') }
	for path, pin in before {
		if hash(out + '/inputs/' + path.trim_left('/'))! != pin { return error('source snapshot changed') }
	}
	for path, pin in native {
		if hash(path)! != pin { return error('native build input changed') }
	}
	if hash(compiler)! != compiler_pin { return error('compiler changed during build') }
	command(out, 'check', [checker, baseline, java, check_out, repo])!
	write_json(out + '/result.json', {
		'scope': json2.Any('Host only; consumed live V source closure retained as identical snapshots and checked before/after compilation; original VROOT used. System SDK/dynamic libraries and non-adjacent native inputs remain environment inputs.')
		'compiler_sha256': json2.Any(compiler_pin)
		'checker_sha256': json2.Any(hash(checker)!)
		'consumed_v_files': json2.Any(before.len)
		'consumed_closure_identical': json2.Any(true)
		'check_manifest_sha256': json2.Any(hash(check_out + '/sha256.json')!)
		'exit_code': json2.Any(0)
	})!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	write_json(out + '/sha256.json', pins)!
	println('LAYOUT-REQUEST-HOST-BUILD-PASS files=${before.len} manifest=${hash(out + '/sha256.json')!}')
}

fn main() {
	$if prod { eprintln('assertions required; compile without -prod'); exit(2) }
	build() or { eprintln(err); exit(1) }
}
