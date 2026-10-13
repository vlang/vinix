// SPDX-License-Identifier: MIT
module main

import os
import tools.packages.pkgcore

fn command(program string, arguments []string) ! {
	mut process := os.new_process(program)
	process.set_args(arguments)
	process.wait()
	code := process.code
	process.close()
	if code != 0 { return error('${program} failed (${code})') }
}

fn build(destination string) ! {
	repository := os.dir(os.dir(os.dir(@FILE)))
	v := os.find_abs_path_of_executable(if os.getenv('V') == '' { 'v' } else { os.getenv('V') })!
	output := os.abs_path(destination)
	if os.exists(output) { return error('example repository output must be new') }
	work := os.temp_dir() + '/vinix-sdk-example-' + os.getpid().str()
	os.mkdir_all(work)!
	defer { os.rmdir_all(work) or {} }
	for architecture in ['aarch64', 'x86_64'] {
		cc := os.find_abs_path_of_executable(architecture + '-linux-musl-gcc')!
		payload := work + '/' + architecture
		os.mkdir_all(payload + '/bin')!
		os.mkdir_all(payload + '/licenses')!
		os.cp(repository + '/tools/packages/appsdk/LICENSE', payload + '/licenses/application-sdk-MIT.txt')!
		os.cp(os.dir(v) + '/LICENSE', payload + '/licenses/v-MIT.txt')!
		os.cp(os.getenv_opt('VINIX_MUSL_COPYRIGHT') or { repository + '/build-support/musl/COPYRIGHT' }, payload + '/licenses/musl-MIT.txt')!
		command(v, ['-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|' + repository,
			'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-os', 'linux', '-arch',
			if architecture == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', work + '/counter.c',
			repository + '/examples/package-counter/main.v'])!
		command(cc, ['-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', work + '/counter.c', '-o',
			payload + '/bin/counter', '-lm', '-lpthread'])!
		bytes := os.read_bytes(payload + '/bin/counter')!
		if bytes.len < 20 || int(bytes[18]) + (int(bytes[19]) << 8) != if architecture == 'aarch64' {
			183
		} else {
			62
		} {
			return error('wrong example ELF architecture')
		}
		pkgcore.pack(repository + '/examples/package-counter/manifest-' + architecture + '.json', payload, output)!
	}
	println('SDK example repository is ready to sign: ' + output)
}

fn main() {
	if os.args.len != 2 {
		eprintln('usage: v run examples/package-counter/build.v NEW_REPOSITORY_DIRECTORY')
		exit(2)
	}
	build(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
}
