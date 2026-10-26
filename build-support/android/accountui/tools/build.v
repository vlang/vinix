// SPDX-License-Identifier: GPL-2.0-or-later
// v run build-support/android/accountui/tools/build.v --arch=arm64 --out=STATE
module main

import crypto.sha256
import json2
import os

struct FilePin {
	path   string
	sha256 string
}

struct Build {
	revision string
	arch     string
	inputs   []FilePin
	outputs  []FilePin
}

fn pin(path string) !FilePin {
	bytes := os.read_bytes(path)!
	return FilePin{path, sha256.hexhash(bytes.bytestr())}
}

fn execute(program string, args []string) ! {
	mut p := os.new_process(program)
	p.set_args(args)
	p.run()
	p.wait()
	status := p.code
	p.close()
	if status != 0 { return error('command failed: ' + program) }
}

fn capture(program string, args []string) !string {
	mut p := os.new_process(program)
	p.set_args(args)
	p.set_redirect_stdio()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	status := p.code
	p.close()
	if status != 0 { return error('cannot inventory V build inputs') }
	return output
}

fn revision(root string) !string {
	mut p := os.new_process('git')
	p.set_args(['-C', root, 'rev-parse', 'HEAD'])
	p.set_redirect_stdio()
	p.run()
	p.wait()
	result := p.stdout_slurp().trim_space()
	status := p.code
	p.close()
	if status != 0 { return error('cannot record source revision') }
	return result
}

fn build() ! {
	root := os.real_path(@DIR + '/../../../..')
	mut arch := 'host'
	mut output := os.join_path(os.home_dir(), '.local/state/vinix/android/account-ui-build')
	for arg in os.args[1..] {
		if arg.starts_with('--arch=') {
			arch = arg.all_after('=')
		} else if arg.starts_with('--out=') {
			output = os.abs_path(arg.all_after('='))
		} else {
			return error('usage: build.v [--arch=host|arm64] [--out=EXTERNAL_STATE_DIRECTORY]')
		}
	}
	if arch !in ['host', 'arm64'] { return error('unsupported account UI architecture') }
	if os.exists(output) && os.ls(output)!.len != 0 {
		return error('account UI build requires a fresh output directory')
	}
	os.mkdir_all(output)!
	output = os.real_path(output)
	if output == root || output.starts_with(root + '/') {
		return error('build output must be outside the checkout')
	}
	v := os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	source := root + '/build-support/android/accountui'
	generated := output + '/account-ui.c'
	binary := output + '/vinix-android-account-ui'
	mut command := ['-new-compiler', '-nocache', '-gc', 'none', '-manualfree', '-d',
		'no_segfault_handler', '-d', 'no_backtrace', '-path',
		'@vlib|@vmodules|' + root + '|' + root + '/build-support/android']
	mut compiler := os.getenv_opt('CC') or { 'clang' }
	mut tools := [v]
	mut dependencies := []string{}
	mut compile := []string{}
	if arch == 'host' {
		command << ['-cc', compiler, '-cflags', '-O2', '-o', binary, source]
	} else {
		command << ['-os', 'linux', '-arch', 'arm64', '-o', generated, source]
		sysroot := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root + '/build-aarch64-userland/staging' }
		mut versions := os.ls(sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
		versions.sort()
		if versions.len == 0 { return error('missing AArch64 GCC runtime') }
		gcc := sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()
		llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
		linker := os.getenv_opt('LD_LLD') or { os.find_abs_path_of_executable('ld.lld')! }
		compiler = llvm + '/clang'
		compile = ['--target=aarch64-linux-musl', '-static', '-nostdinc', '-nostdlib', '-isystem',
			root + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include', '-isystem',
			sysroot + '/usr/include', '-D_GNU_SOURCE', '-O2', '-fno-stack-protector', '-w',
			sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o', gcc + '/crtbeginT.o', generated,
			'-L' + sysroot + '/usr/lib', '-L' + gcc, '-lgcc_eh', '-lc', '-lgcc', '-lm',
			gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o', '-fuse-ld=' + linker, '-B' + llvm,
			'-o', binary]
		dependencies << [sysroot + '/usr/lib/crt1.o', sysroot + '/usr/lib/crti.o',
			gcc + '/crtbeginT.o', gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o',
			sysroot + '/usr/lib/libc.a', gcc + '/libgcc.a', gcc + '/libgcc_eh.a', linker]
	}
	tools << os.find_abs_path_of_executable(compiler)!
	mut files := []string{}
	for directory in [source, root + '/desktop/windowfb', root + '/desktop/sessionruntime',
		root + '/build-support/android/nativeaccountauth'] {
		files << os.walk_ext(directory, '.v')
	}
	// Include the actual selected standard-library sources, which can live
	// outside the compiler launcher's checkout.
	mut inventory := ['-print-v-files']
	inventory << command
	parsed := capture(v, inventory)!
	for line in parsed.split_into_lines() {
		if !line.ends_with('.v') || !os.is_file(line) {
			return error('invalid V source inventory')
		}
		if line !in files { files << line }
	}
	files << dependencies
	files << tools
	files.sort()
	mut inputs := []FilePin{}
	for file in files { inputs << pin(file)! }
	source_revision := revision(root)!
	os.write_file(output + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	execute(v, command)!
	if arch != 'host' { execute(compiler, compile)! }
	for input in inputs {
		if pin(input.path)!.sha256 != input.sha256 {
			return error('account UI build input changed: ' + input.path)
		}
	}
	mut outputs := [pin(binary)!]
	if arch != 'host' { outputs << pin(generated)! }
	report := Build{source_revision, arch, inputs, outputs}
	os.write_file(output + '/build.json', json2.encode(report,
		prettify:       true
		legacy_layout:  true
		escape_unicode: true
		time_as_unix:   true
	) + '\n')!
	println('Built ' + binary)
	println('SHA256 ' + outputs[0].sha256)
}

fn main() {
	build() or {
		eprintln(err)
		exit(1)
	}
}
