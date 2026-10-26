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
	mut supplied := false
	for argument in os.args[1..] {
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
	if !supplied { args << '--sysroot=' + sysroot }
	mut process := os.new_process(backend)
	process.set_args(args)
	process.run()
	process.wait()
	status := process.code
	process.close()
	exit(status)
}
