// SPDX-License-Identifier: MIT
module main

import os
import time
import hosttest

fn run(program string, args []string) ! {
	mut process := os.new_process(program)
	process.set_args(args)
	process.run()
	process.wait()
	status := process.code
	process.close()
	if status != 0 { return error('command failed: ' + program) }
}

fn exercise(work string, name string) ! {
	path := work + '/' + name + '.sock'
	mut server := os.new_process(work + '/server')
	server.set_args([path])
	server.run()
	defer {
		server.signal_kill()
		server.wait()
		server.close()
	}
	deadline := time.sys_mono_now() + 5 * time.second
	for !os.exists(path) {
		if !server.is_alive() || time.sys_mono_now() >= deadline {
			return error('server did not start')
		}
		time.sleep(time.millisecond)
	}
	run(work + '/' + name, [path, if name == 'client-static' { 'explicit' } else { 'environment' }])!
	server.wait()
	if server.code != 0 { return error('framebuffer server failed') }
}

fn main() {
	root := os.real_path(@DIR + '/../..')
	v := os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	work := os.join_path(os.temp_dir(), 'vinix-capi-tests-${os.getpid()}')
	os.mkdir_all(work)!
	defer { if os.getenv('VINIX_CAPI_KEEP') != '1' { os.rmdir_all(work) or {} } }
	println('C ABI test artifacts: ' + work)
	sdk := work + '/host'
	run(v, ['run', root + '/desktop/tools/build-window-capi.v', '--arch=host', '--out=' + sdk])!
	arch := $if amd64 { 'amd64' } $else { 'arm64' }
	hosttest.generate_module(@DIR + '/client', work + '/client.c', arch, [])!
	assert !os.read_file(work + '/client.c')!.contains('memdup(')
	for name in ['client-shared', 'client-static'] {
		library := sdk + '/lib/libvinix-window' + if name == 'client-static' {
			'.a'
		} else {
			$if macos {
				'.dylib'
			} $else {
				'.so'
			}
		}
		mut flags := ['-w', '-O1', '-I', sdk + '/include', work + '/client.c', library, '-lpthread',
			'-lm', '-o', work + '/' + name]
		if name == 'client-shared' { flags << ['-Wl,-rpath,' + sdk + '/lib'] }
		run('clang', flags)!
	}
	run(v, ['-new-compiler', '-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d',
		'no_segfault_handler', '-path', '@vlib|@vmodules|' + root, '-o', work + '/server',
		@DIR + '/server.v'])!
	for name in ['client-shared', 'client-static'] { exercise(work, name)! }
	if os.args.contains('--cross') {
		for guest_arch in ['arm64', 'amd64'] {
			guest := work + '/' + guest_arch
			run(v, ['run', root + '/desktop/tools/build-window-capi.v', '--arch=' + guest_arch,
				'--out=' + guest])!
			hosttest.generate_module(@DIR + '/client', guest + '/client.c', guest_arch, [])!
			target := if guest_arch == 'arm64' { 'aarch64' } else { 'x86_64' }
			sysroot := if guest_arch == 'arm64' {
				root + '/build-aarch64-userland/staging'
			} else {
				root + '/build/session-amd64-sysroot'
			}
			mut versions := os.ls(sysroot + '/usr/lib/gcc/' + target + '-alpine-linux-musl')!
			versions.sort()
			gcc := sysroot + '/usr/lib/gcc/' + target + '-alpine-linux-musl/' + versions.last()
			llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
			run(llvm + '/clang', ['--target=' + target + '-linux-musl', '-static', '-nostdinc',
				'-nostdlib', '-isystem', gcc + '/include', '-isystem', sysroot + '/usr/include',
				'-I', guest + '/include', '-w', '-O1', sysroot + '/usr/lib/crt1.o',
				sysroot + '/usr/lib/crti.o', gcc + '/crtbeginT.o', guest + '/client.c',
				guest + '/lib/libvinix-window.a', '-L' + sysroot + '/usr/lib', '-L' + gcc, '-lgcc_eh',
				'-lc', '-lgcc', '-lm', gcc + '/crtend.o', sysroot + '/usr/lib/crtn.o', '-fuse-ld=lld',
				'-B' + llvm, '-o', guest + '/client-static'])!
		}
	}
	println('C ABI shared/static checks passed')
}
