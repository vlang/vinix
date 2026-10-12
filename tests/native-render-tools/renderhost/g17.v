// SPDX-License-Identifier: GPL-2.0-or-later
module renderhost

import agxhost
import cachecli
import os
import perfreport

fn transcript() agxhost.Transcript {
	return agxhost.Transcript{ inherit: true, host_arch: os.uname().machine }
}

pub fn g17_host_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--c-encoder-reference', '--c-verifier-reference'], [], [], 0, 0, 'Run independent G17 verifier and encoder fixtures against production V.\nUsage: run [--c-encoder-reference C --c-verifier-reference C]') or { return error_with_code(err.msg(), 2) }
	machine := os.uname().machine
	arch := os.getenv_opt('VINIX_G17_TEST_ARCH') or {
		if machine.to_lower() in ['arm64', 'aarch64'] {
			'aarch64'
		} else {
			'x86_64'
		}
	}
	if arch !in ['aarch64', 'x86_64'] { return error_with_code('unsupported host architecture', 2) }
	mut out := transcript()
	defer {
		print(out.stdout)
		eprint(out.stderr)
	}
	out.host_verifier(root, machine, args.value('--c-encoder-reference', ''), args.value('--c-verifier-reference', ''))!
	return 0
}

pub fn g17_native_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--arch', '--kernel-dir', '--state-dir', '--c-reference',
		'--fixture', '--timeout'], [], [], 0, 0, 'Run independent G17 oracles and unchanged production V in a native guest.\nUsage: run_encode_native --arch aarch64|x86_64 --kernel-dir DIR --state-dir NEW [--fixture encoder|verifier --c-reference C --timeout 600]') or { return error_with_code(err.msg(), 2) }
	arch := args.required('--arch') or { return error_with_code(err.msg(), 2) }
	kernel := args.required('--kernel-dir') or { return error_with_code(err.msg(), 2) }
	state := args.required('--state-dir') or { return error_with_code(err.msg(), 2) }
	fixture := args.value('--fixture', 'encoder')
	if arch !in ['aarch64', 'x86_64'] || fixture !in ['encoder', 'verifier'] {
		return error_with_code('unsupported architecture or fixture', 2)
	}
	timeout := perfreport.integer_text(args.value('--timeout', '600')) or { return error_with_code(err.msg(), 2) }
	mut out := transcript()
	defer {
		print(out.stdout)
		eprint(out.stderr)
	}
	return out.native_fixture(root, arch, kernel, state, args.value('--c-reference', ''), fixture, timeout, '', os.environ())!
}

pub fn g17_vm_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--timeout'], [], [], 0, 0, 'Exercise Mesa fake-G17 render/fence and descriptor lifetimes.\nUsage: run_vm [--timeout 180]') or { return error_with_code(err.msg(), 2) }
	timeout := perfreport.integer_text(args.value('--timeout', os.getenv_opt('VINIX_FAKE_G17_VM_TIMEOUT') or { '180' })) or { return error_with_code(err.msg(), 2) }
	if timeout == '0' || timeout.starts_with('-') {
		return error_with_code('--timeout must be positive', 2)
	}
	mut out := transcript()
	defer {
		print(out.stdout)
		eprint(out.stderr)
	}
	return out.vm_native_test(root, timeout)!
}
