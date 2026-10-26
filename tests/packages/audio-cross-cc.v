// SPDX-License-Identifier: GPL-2.0-or-later
// Keep the target harness's GCC ABI while consuming its frozen sysroot.
module main

import os

fn main() {
	backend := os.getenv('VINIX_AUDIO_BACKEND_CC')
	if !os.is_abs_path(backend) || !os.is_executable(backend) {
		eprintln('audio-cross-cc: requires absolute VINIX_AUDIO_BACKEND_CC')
		exit(2)
	}
	mut args := []string{}
	sysroot := os.getenv('VINIX_AUDIO_FROZEN_SYSROOT')
	if !os.is_abs_path(sysroot) || !os.is_dir(sysroot) {
		eprintln('audio-cross-cc: requires absolute VINIX_AUDIO_FROZEN_SYSROOT')
		exit(2)
	}
	gcc := os.getenv('VINIX_AUDIO_FROZEN_GCC')
	if !os.is_abs_path(gcc) || !os.is_dir(gcc) { eprintln('audio-cross-cc: requires absolute VINIX_AUDIO_FROZEN_GCC'); exit(2) }
	for path in [sysroot + '/include', gcc + '/include', gcc + '/include-fixed'] {
		if !os.is_dir(path) { eprintln('audio-cross-cc: missing captured include directory: ' + path); exit(2) }
	}
	for path in [sysroot + '/lib/crt1.o', sysroot + '/lib/crti.o', sysroot + '/lib/crtn.o',
		sysroot + '/lib/libc.a', sysroot + '/lib/libm.a', sysroot + '/lib/libpthread.a',
		gcc + '/crtbeginT.o', gcc + '/crtend.o', gcc + '/libgcc.a', gcc + '/libgcc_eh.a'] {
		if !os.is_file(path) { eprintln('audio-cross-cc: missing captured target input: ' + path); exit(2) }
	}
	target := os.exec([backend, '-dumpmachine'])
	if target.exit_code != 0 || target.output.trim_space() == '' {
		eprintln('audio-cross-cc: cannot identify backend target'); exit(2)
	}
	arm := target.output.trim_space().starts_with('aarch64-')
	args << ['-v', '-H', '-Wl,-t', '-save-temps=obj', '-nostdinc', '-isystem', gcc + '/include',
		'-isystem', gcc + '/include-fixed', '-isystem', sysroot + '/include',
		'-B' + sysroot + '/lib/', '-B' + gcc + '/', '-L' + sysroot + '/lib', '-L' + gcc]
	mut supplied := false
	for argument in os.args[1..] {
		// The shared hardware harness supplies -w. ARM audio must expose its
		// actual pointer boundary diagnostics; keep historical x86 handling.
		if arm && argument == '-w' { continue }
		if arm && argument == '-fpermissive' {
			eprintln('audio-cross-cc: ARM pointer diagnostics require strict compilation'); exit(2)
		}
		if argument.starts_with('--target=') || argument == '-fuse-ld=lld' { continue }
		if argument.starts_with('--sysroot=') {
			if argument != '--sysroot=' + sysroot {
				eprintln('audio-cross-cc: sysroot differs from frozen input')
				exit(2)
			}
			supplied = true
		}
		args << argument
	}
	if '-static' !in args { eprintln('audio-cross-cc: requires static target executable'); exit(2) }
	if !supplied { args << '--sysroot=' + sysroot }
	if arm { args << '-Werror=incompatible-pointer-types' }
	mut process := os.new_process(backend)
	process.set_args(args)
	process.run()
	process.wait()
	status := process.code
	process.close()
	exit(status)
}
