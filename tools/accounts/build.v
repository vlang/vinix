// SPDX-License-Identifier: GPL-2.0-or-later
// Compatibility entry point for the account tool build command.
module main

import json2
import os

fn build() !int {
	if os.args.len != 3 || os.args[1] !in ['aarch64', 'x86_64'] {
		return error('usage: tools/accounts/build aarch64|x86_64 ROOT')
	}
	architecture := os.args[1]
	root := os.abs_path(os.args[2])
	if root == '/' { return error('account builds require an image directory other than /') }
	repository := os.dir(os.dir(os.dir(@FILE)))
	mut cc := []string{}
	if architecture == 'aarch64' {
		configured_root := os.getenv('VINIX_AARCH64_SYSROOT')
		sysroot := os.abs_path(if configured_root == '' {
			repository + '/build-aarch64-userland/sysroot'
		} else {
			configured_root
		})
		configured_cc := os.getenv('CC')
		cc = [if configured_cc == '' { 'clang' } else { configured_cc }, '--target=aarch64-linux-musl',
			'--sysroot=' + sysroot, '-fno-stack-protector', '-L' + sysroot + '/lib', '-fuse-ld=lld']
	} else {
		configured_cc := os.getenv('CC_AMD64')
		cc = [if configured_cc == '' { 'x86_64-linux-musl-gcc' } else { configured_cc }]
	}
	configured_v := os.getenv('V')
	v := os.find_abs_path_of_executable(if configured_v == '' { @VEXE } else { configured_v })!
	os.mkdir_all(root, mode: 0o755)!
	mut child := os.new_process(v)
	defer { child.close() }
	// Every option remains one literal argument, including paths with spaces or
	// shell metacharacters. The stage tool captures the image before compiling.
	child.set_args(['-backend', 'c', '-path',
		'@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts', 'run',
		repository + '/tools/accounts/stage.v', '--arch', architecture, '--staging', root, '--cc-argv',
		json2.encode(cc), '--include-session'])
	child.wait()
	return child.code
}

fn main() {
	status := build() or {
		eprintln('account build: ${err}')
		exit(2)
	}
	exit(status)
}
