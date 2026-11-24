// SPDX-License-Identifier: GPL-2.0-or-later
// v -path '@vlib|@vmodules|.|desktop/tools' run tests/packages/software-graphical-build.v --arch=aarch64 --out=DIR
// Freeze the production compositor sources before compiling a graphical check.
module main

import crypto.sha256
import hosttest
import json2
import os
import workflowbuild

fn main() {
	build() or {
		eprintln(err)
		exit(1)
	}
}

fn build() ! {
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') {
			return error('use --arch=aarch64|x86_64 --out=NEW_DIRECTORY [--ui=UI2_SOURCE] [--musl-cc=COMPILER]')
		}
		options[argument.all_before('=')] = argument.all_after('=')
	}
	arch := options['--arch'] or { 'aarch64' }
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported architecture') }
	root := os.real_path(@DIR + '/../..')
	work := os.abs_path(options['--out'] or { return error('--out is required') })
	if os.exists(work) { return error('output directory must be new') }
	ui := os.real_path(options['--ui'] or { root + '/../ui2' })
	compiler := os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	version := if arch == 'aarch64' { 'arm64' } else { 'amd64' }
	sysroot := if arch == 'aarch64' {
		root + '/build-aarch64-userland/staging'
	} else {
		root + '/build/session-amd64-sysroot'
	}
	source := work + '/source'
	os.mkdir_all(source + '/tools')!
	for name in ['desktop', 'tools/packages', 'tools/accounts', 'compat'] {
		workflowbuild.run('cp', ['-Rp', root + '/' + name, source + '/' + name])!
	}
	workflowbuild.run('cp', ['-Rp', ui, source + '/ui2'])!
	app := work + '/app'
	workflowbuild.stage(source, source + '/ui2', app, true)!
	flags := ['-new-compiler', '-nocache', '-w', '-prod', '-os', 'linux', '-arch', version, '-gc',
		'none', '-manualfree', '-enable-globals', '-d', 'no_segfault_handler', '-d', 'ui2_headless',
		'-path',
		'@vlib|' + app + '/modules|' + source + '|' + source + '/tools/accounts|@vmodules|' + root + '/third_party']
	workflowbuild.run(compiler, [...flags, '-o', app + '/desktop.c', app])!
	hosttest.generate_module(source + '/desktop/execinfocore', app + '/execinfo.c', version, [])!
	runtime := app + '/v-runtime'
	workflowbuild.run(compiler, ['run', root + '/build-support/stage-v-runtime.v', runtime])!
	sources := [app + '/desktop.c', app + '/execinfo.c', app + '/presenter.c',
		runtime + '/execute_capture_nix.c', runtime + '/fontstash_impl.c']
	common := ['-static', '-I', app, '-I', runtime, '-D_GNU_SOURCE', '-O2', '-fno-stack-protector', '-w']
	if cc := options['--musl-cc'] {
		workflowbuild.run(os.find_abs_path_of_executable(cc)!, [...common, '-fpermissive',
			...sources, '-lm', '-o', work + '/vinix-desktop'])!
	} else {
		gcc_root := sysroot + '/usr/lib/gcc/' + arch + '-alpine-linux-musl'
		mut versions := os.ls(gcc_root)!
		versions.sort()
		if versions.len == 0 { return error('missing static musl GCC runtime') }
		gcc := gcc_root + '/' + versions.last()
		workflowbuild.run(llvm + '/clang', [
		...common,
		'--target=' + arch + '-linux-musl',
		'-nostdinc',
		'-nostdlib',
		'-isystem',
		root + '/build-support/aarch64-cc-shim',
		'-isystem',
		gcc + '/include',
		'-isystem',
		sysroot + '/usr/include',
		sysroot + '/usr/lib/crt1.o',
		sysroot + '/usr/lib/crti.o',
		gcc + '/crtbeginT.o',
		...sources,
		'-L' + sysroot + '/usr/lib',
		'-L' + gcc,
		'-lgcc_eh',
		'-lc',
		'-lgcc',
		'-lm',
		gcc + '/crtend.o',
		sysroot + '/usr/lib/crtn.o',
		'-fuse-ld=lld',
		'-B' + llvm,
		'-o',
		work + '/vinix-desktop',
		])!
	}
	mut artifacts := map[string]string{}
	artifacts['compiler'] = sha256.sum(os.read_bytes(compiler)!).hex()
	artifacts['repository-head'] = os.execute('git rev-parse HEAD').output.trim_space()
	for path in os.walk_ext(source, '') {
		if os.is_file(path) {
			artifacts[path[source.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex()
		}
	}
	for path in [app + '/desktop.c', app + '/execinfo.c', app + '/presenter.c',
		work + '/vinix-desktop', ...os.walk_ext(runtime, '')] {
		artifacts[path[work.len + 1..]] = sha256.sum(os.read_bytes(path)!).hex()
	}
	os.write_file(work + '/desktop-build.json', json2.encode(artifacts) + '\n')!
	println('SOFTWARE GRAPHICAL built ' + arch + ': ' + work + '/vinix-desktop')
}
