// SPDX-License-Identifier: GPL-2.0-or-later
// v -path '@vlib|@vmodules|.|desktop/tools' run tests/packages/software-graphical-build.v --arch=aarch64 --out=DIR
// Freeze the production compositor sources before compiling a graphical check.
module main

import crypto.sha256
import hosttest
import json2
import os
import workflowbuild

fn digest(path string) !string {
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	return sha256.hexhash(unsafe { tos(data.data, data.len) })
}

fn inventory(directory string, prefix string, mut paths map[string]string) ! {
	for name in os.ls(directory)! {
		if name == '.git' { continue }
		path := directory + '/' + name
		if os.is_link(path) {
			if os.is_file(path) { paths[prefix + name] = path }
		} else if os.is_dir(path) {
			inventory(path, prefix + name + '/', mut paths)!
		} else if os.is_file(path) {
			paths[prefix + name] = path
		}
	}
}

fn inputs(root string, ui string, sysroot string, compiler string, llvm string) !map[string]string {
	mut paths := {
		'builder-source': @FILE
		'builder': os.executable()
		'compiler': compiler
		'compiler-v.mod': os.dir(compiler) + '/v.mod'
		'clang': llvm + '/clang'
		'linker': os.find_abs_path_of_executable('ld.lld')!
		'find-v': root + '/build-support/find-v.sh'
	}
	for name in ['desktop', 'tools/packages', 'tools/accounts', 'compat'] {
		inventory(root + '/' + name, 'source/' + name + '/', mut paths)!
	}
	inventory(ui, 'source/ui2/', mut paths)!
	inventory(sysroot + '/usr/include', 'sysroot/include/', mut paths)!
	inventory(sysroot + '/usr/lib', 'sysroot/lib/', mut paths)!
	inventory(root + '/build-support/aarch64-cc-shim', 'shim/', mut paths)!
	inventory(os.dir(compiler) + '/vlib', 'vlib/', mut paths)!
	inventory(os.dir(compiler) + '/thirdparty', 'thirdparty/', mut paths)!
	return paths
}

fn main() {
	build() or {
		eprintln(err)
		exit(1)
	}
}

fn build() ! {
	$if prod {} $else { return error('compile this builder with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('build.v').to_string()) {
		return error('builder source differs from this executable')
	}
	mut options := map[string]string{}
	for argument in os.args[1..] {
		if !argument.starts_with('--') || !argument.contains('=') {
			return error('use --arch=aarch64|x86_64 --out=NEW_DIRECTORY [--ui=UI2_SOURCE]')
		}
		name := argument.all_before('=')
		if name !in ['--arch', '--out', '--ui'] || name in options {
			return error('unknown or duplicated build option: ' + name)
		}
		options[name] = argument.all_after('=')
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
	mut versions := os.ls(sysroot + '/usr/lib/gcc/' + arch + '-alpine-linux-musl')!
	versions.sort()
	if versions.len == 0 { return error('missing static musl GCC runtime') }
	gcc := sysroot + '/usr/lib/gcc/' + arch + '-alpine-linux-musl/' + versions.last()
	input_paths := inputs(root, ui, sysroot, compiler, llvm)!
	mut input_hashes := map[string]string{}
	for name, path in input_paths { input_hashes[name] = digest(path)! }
	source := work + '/source'
	os.mkdir_all(source + '/tools')!
	for name in ['desktop', 'tools/packages', 'tools/accounts', 'compat'] {
		workflowbuild.run('cp', ['-Rp', root + '/' + name, source + '/' + name])!
	}
	workflowbuild.run('cp', ['-Rp', ui, source + '/ui2'])!
	if os.exists(source + '/ui2/.git') { os.rmdir_all(source + '/ui2/.git')! }
	app := work + '/app'
	workflowbuild.stage(source, source + '/ui2', app, true)!
	flags := ['-new-compiler', '-nocache', '-w', '-prod', '-os', 'linux', '-arch', version, '-gc',
		'none', '-manualfree', '-enable-globals', '-d', 'no_segfault_handler', '-d', 'ui2_headless',
		'-path',
		'@vlib|' + app + '/modules|' + source + '|' + source + '/tools/accounts|@vmodules|' + root + '/third_party']
	v_args := [...flags, '-o', app + '/desktop.c', app]
	workflowbuild.run(compiler, v_args)!
	hosttest.generate_module(source + '/desktop/execinfocore', app + '/execinfo.c', version, [])!
	c_args := [
		'--target=' + arch + '-linux-musl',
		'-static',
		'-nostdinc',
		'-nostdlib',
		'-isystem',
		root + '/build-support/aarch64-cc-shim',
		'-isystem',
		gcc + '/include',
		'-isystem',
		sysroot + '/usr/include',
		'-I',
		app,
		'-D_GNU_SOURCE',
		'-O2',
		'-fno-stack-protector',
		'-w',
		sysroot + '/usr/lib/crt1.o',
		sysroot + '/usr/lib/crti.o',
		gcc + '/crtbeginT.o',
		app + '/desktop.c',
		app + '/execinfo.c',
		app + '/presenter.c',
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
	]
	workflowbuild.run(llvm + '/clang', c_args)!
	mut artifacts := map[string]string{}
	artifacts['compiler'] = digest(compiler)!
	artifacts['repository-head'] = os.exec(['git', '-C', root, 'rev-parse', 'HEAD']).output.trim_space()
	mut frozen := map[string]string{}
	inventory(source, '', mut frozen)!
	for name, path in frozen { artifacts[name] = digest(path)! }
	for path in [app + '/desktop.c', app + '/execinfo.c', app + '/presenter.c',
		work + '/vinix-desktop'] {
		artifacts[path[work.len + 1..]] = digest(path)!
	}
	if inputs(root, ui, sysroot, compiler, llvm)! != input_paths {
		return error('build input inventory changed')
	}
	for name, path in input_paths {
		if digest(path)! != input_hashes[name] { return error('build input changed: ' + name) }
	}
	os.write_file(work + '/build-inputs.json', json2.encode(input_hashes) + '\n')!
	os.write_file(work + '/build-input-paths.json', json2.encode(input_paths) + '\n')!
	os.write_file(work + '/build-argv.json', json2.encode({
		'v': [compiler, ...v_args]
		'c': [llvm + '/clang', ...c_args]
		'builder': os.args
	}))!
	os.write_file(work + '/desktop-build.json', json2.encode(artifacts) + '\n')!
	println('SOFTWARE GRAPHICAL built ' + arch + ': ' + work + '/vinix-desktop')
}
