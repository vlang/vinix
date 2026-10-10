// SPDX-License-Identifier: GPL-2.0-or-later
module nativepolicy

import hosttest
import os

fn diagnostics() ! {
	owner := private_work('vinix-stack-diagnostics-')!
	defer { retire(owner) }
	common := concat([hosttest.env_default('CC', 'clang')], clang_arch(arch()), ['-std=gnu11', '-O2', '-g',
		'-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-fno-omit-frame-pointer'])
	for adapter in ['amd64', 'arm64'] {
		work := owner + '/' + adapter
		os.mkdir(work)!
		policy := work + '/diagnosticpolicy'
		os.mkdir(policy)!
		for name, original in {'diagnostic.v': 'stack_diagnostics.v', 'serial.v': 'stack_diagnostics_' + adapter + '.v'} {
			write(policy + '/' + name, read(root() + '/kernel/lib/' + original)!
				.replace('module lib', 'module diagnosticpolicy'))!
		}
		compile_module(policy, work + '/diagnostic.o', arch(), concat(common,
			['-ffreestanding', '-fno-builtin', '-fno-strict-aliasing']))!
		compile_module(root() + '/tests/stack-protector/diagnosticfixture', work + '/fixture.o',
			arch(), concat(common, ['-fno-strict-aliasing']))!
		no_allocators(output(['nm', '-u', work + '/diagnostic.o', work + '/fixture.o'])!)!
		run(concat(common, [work + '/fixture.o', work + '/diagnostic.o', '-o', work + '/host']))!
		run([work + '/host'])!
		println('PASS ' + adapter + ' serial adapter and no allocator imports')
	}
}
