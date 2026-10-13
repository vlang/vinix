// SPDX-License-Identifier: MIT
// v run desktop/tools/build-window-capi.v --arch=host --out=/tmp/window-sdk
module main

import os

const exports = ['vinix_window_api_version', 'vinix_window_open', 'vinix_window_open_at',
	'vinix_window_close', 'vinix_window_event_fd', 'vinix_window_get_framebuffer',
	'vinix_window_frame_pending', 'vinix_window_wants_write', 'vinix_window_present',
	'vinix_window_next_event', 'vinix_window_wait']

fn run(program string, args []string) ! {
	mut process := os.new_process(program)
	process.set_args(args)
	process.run()
	process.wait()
	status := process.code
	process.close()
	if status != 0 { return error('command failed: ' + program) }
}

fn main() {
	root := os.real_path(@DIR + '/../..')
	mut arch := 'host'
	mut output := root + '/build/window-sdk'
	for arg in os.args[1..] {
		if arg.starts_with('--arch=') {
			arch = arg.all_after('=')
		} else if arg.starts_with('--out=') {
			output = os.real_path(arg.all_after('='))
		} else {
			eprintln('usage: build-window-capi.v [--arch=host|arm64|amd64] [--out=DIR]')
			exit(2)
		}
	}
	if arch !in ['host', 'arm64', 'amd64'] { panic('unsupported SDK architecture') }
	os.mkdir_all(output + '/include')!
	os.mkdir_all(output + '/lib')!
	api := root + '/desktop/windowfb/capi'
	v := os.getenv_opt('V') or { os.find_abs_path_of_executable('v')! }
	mut generate := ['-new-compiler', '-nocache', '-shared', '-prod', '-gc', 'none', '-manualfree',
		'-d', 'no_segfault_handler', '-d', 'no_backtrace', '-path', '@vlib|@vmodules|' + root,
		'-o', output + '/window.c']
	mut cc := os.getenv_opt('CC') or { 'clang' }
	mut compile := ['-w', '-O2', '-fPIC', '-fvisibility=hidden', '-I', api]
	mut link := []string{}
	mut ar := os.getenv_opt('AR') or { 'ar' }
	mut suffix := '.so'
	if arch == 'host' {
		$if macos {
			suffix = '.dylib'
			link << ['-dynamiclib', '-install_name', '@rpath/libvinix-window.dylib']
		} $else {
			link << ['-shared', '-Wl,-soname,libvinix-window.so']
		}
	} else {
		generate << ['-os', 'linux', '-arch', arch]
		target := if arch == 'arm64' { 'aarch64' } else { 'x86_64' }
		sysroot := if arch == 'arm64' {
			os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root + '/build-aarch64-userland/staging' }
		} else {
			os.getenv_opt('VINIX_AMD64_SYSROOT') or { root + '/build/session-amd64-sysroot' }
		}
		mut versions := os.ls(sysroot + '/usr/lib/gcc/' + target + '-alpine-linux-musl')!
		versions.sort()
		gcc := sysroot + '/usr/lib/gcc/' + target + '-alpine-linux-musl/' + versions.last()
		llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
		cc = llvm + '/clang'
		ar = llvm + '/llvm-ar'
		compile << ['--target=' + target + '-linux-musl', '-nostdinc', '-isystem',
			root + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include', '-isystem',
			sysroot + '/usr/include', '-D_GNU_SOURCE', '-fno-stack-protector']
		link << ['--target=' + target + '-linux-musl', '-shared', '-nostdlib',
			'-Wl,-soname,libvinix-window.so',
			sysroot + '/usr/lib/crti.o', gcc + '/crtbeginS.o', '-L' + sysroot + '/usr/lib', '-L' + gcc,
			'-fuse-ld=lld', '-B' + llvm]
		link << [output + '/window.o', '-lc', '-lgcc', '-lm', gcc + '/crtendS.o',
			sysroot + '/usr/lib/crtn.o']
	}
	generate << api
	run(v, generate)!
	// Shared-library exports are restricted to the public ABI; in particular,
	// V's interface metadata must not interpose on another V-based library.
	if suffix == '.dylib' {
		os.write_file(output + '/exports', exports.map('_' + it).join('\n') + '\n')!
		link << ['-Wl,-exported_symbols_list,' + output + '/exports']
	} else {
		os.write_file(output + '/exports', '{ global: ' + exports.join('; ') + '; local: *; };\n')!
		link << ['-Wl,--version-script=' + output + '/exports', '-Wl,-z,defs']
	}
	compile << ['-c', output + '/window.c', '-o', output + '/window.o']
	run(cc, compile)!
	if arch == 'host' { link << [output + '/window.o', '-lpthread', '-lm'] }
	link << ['-o', output + '/lib/libvinix-window' + suffix]
	run(cc, link)!
	run(ar, ['rcs', output + '/lib/libvinix-window.a', output + '/window.o'])!
	os.cp(api + '/vinix_window.h', output + '/include/vinix_window.h')!
	println('Built ' + arch + ' C window SDK: ' + output)
}
