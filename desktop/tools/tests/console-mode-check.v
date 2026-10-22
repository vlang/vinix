// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct Pin {
	path   string
	sha256 string
}

struct Receipt {
	inputs    []Pin
	artifacts []Pin
	commands  [][]string
	result    string
}

fn pin(path string) !Pin {
	return Pin{ path: path, sha256: sha256.sum(os.read_bytes(path)!).hex() }
}

fn run(argv []string, log string) !string {
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	output := child.stdout_slurp()
	child.wait()
	os.write_file(log, output)!
	if child.code != 0 || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error('command failed; inspect ' + log)
	}
	return output
}

fn check() ! {
	if os.args.len != 2 {
		return error('usage: console-mode-check.v NEW_WORK_DIRECTORY; set V to the chosen compiler')
	}
	root := os.real_path(@DIR + '/../../..')
	work := os.abs_path(os.args[1])
	if os.exists(work) || os.is_link(work) { return error('work directory must be new') }
	os.mkdir_all(work)!
	selected := os.getenv_opt('V') or { 'v' }
	compiler := os.find_abs_path_of_executable(if os.is_dir(selected) {
		selected + '/v'
	} else {
		selected
	})!
	arm := os.uname().machine == 'arm64' || os.uname().machine == 'aarch64'
	arch := if arm { 'arm64' } else { 'amd64' }
	mut paths := [@FILE, compiler, root + '/desktop/gpucore/core.v', root + '/desktop/gpu_egl_abi.h',
		root + '/desktop/tools/tests/consolefixture/core.v', root + '/build-support/compile-v-module',
		root + '/build-support/run-v-tool.sh', root + '/build-support/find-v.sh',
		root + '/tests/linuxkpi/generate_module.v']
	for path in os.walk_ext(root + '/tests/linuxkpi/hosttest', '.v') {
		if !path.ends_with('_test.v') { paths << path }
	}
	if arm && os.user_os() == 'macos' {
		paths << root + '/desktop/tools/tests/gpufixture/ioctl_darwin_arm64.S'
	}
	paths.sort()
	mut inputs := []Pin{}
	for path in paths { inputs << pin(path)! }
	mut commands := [][]string{}
	commands << ['sh', root + '/build-support/compile-v-module', root + '/desktop/gpucore',
		work + '/console.c', '--arch', arch, '--header', work + '/console-api.h']
	mut generate := ['sh', root + '/build-support/compile-v-module',
		root + '/desktop/tools/tests/consolefixture', work + '/fixture.c', '--arch', arch]
	if arm && os.user_os() == 'macos' { generate << ['-d', 'fixture_darwin_arm64'] }
	commands << generate
	flags := ['clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-label', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fsanitize-address-use-after-return=always', '-fno-omit-frame-pointer', '-I',
		root + '/desktop']
	remaps := ['open', 'close', 'ioctl', 'stat', 'fstat'].map('-D' + it + '=gpf_' + it)
	compile_console := [...flags, ...remaps, '-c', work + '/console.c', '-o', work + '/console.o']
	commands << compile_console
	compile_fixture := [...flags, '-include', work + '/console-api.h', '-c', work + '/fixture.c',
		'-o', work + '/fixture.o']
	commands << compile_fixture
	mut objects := [work + '/console.o', work + '/fixture.o']
	if arm && os.user_os() == 'macos' {
		commands << ['clang', '-c', root + '/desktop/tools/tests/gpufixture/ioctl_darwin_arm64.S',
			'-o', work + '/ioctl.o']
		objects << work + '/ioctl.o'
	}
	link := [...flags, ...objects, '-o', work + '/console-check']
	commands << link
	commands << ['clang', '--version']
	commands << ['nm', '-u', work + '/console.o']
	commands << [work + '/console-check']
	os.setenv('ASAN_OPTIONS', 'detect_leaks=' + if os.user_os() == 'macos' { '0' } else { '1' } + ':halt_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1:print_stacktrace=1', true)
	mut output := ''
	for index, argv in commands {
		output = run(argv, work + '/step-' + index.str() + '.txt')!
		if argv[0] == 'nm' {
			for line in output.split_into_lines() {
				fields := line.fields()
				if fields.len == 0 { continue }
				name := fields.last().trim_left('_')
				if name in ['malloc', 'calloc', 'realloc', 'free', 'memdup'] || name.starts_with('new_array') {
					return error('unexpected allocation in console-mode object: ' + name)
				}
			}
		}
	}
	if !output.contains('CONSOLE MODE 16 cases and 1000 graphics/text cycles PASS\n') {
		return error('console fixture did not complete')
	}
	for input in inputs {
		if pin(input.path)! != input { return error('input changed: ' + input.path) }
	}
	mut artifacts := []Pin{}
	for name in ['console.c', 'console-api.h', 'fixture.c', 'console.o', 'fixture.o', 'console-check'] {
		artifacts << pin(work + '/' + name)!
	}
	if arm && os.user_os() == 'macos' { artifacts << pin(work + '/ioctl.o')! }
	for index in 0 .. commands.len { artifacts << pin(work + '/step-' + index.str() + '.txt')! }
	os.write_file(work + '/qualification.json', json2.encode(Receipt{ inputs: inputs, artifacts: artifacts, commands: commands, result: 'PASS' }) + '\n')!
	print(output)
	println('Evidence: ' + work + '/qualification.json')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
