// SPDX-License-Identifier: GPL-2.0-only
module vmxcheck

import hosttest
import os

fn test_real_cli_original_entry_bytes_failures_argument_rules_and_cleanup() {
	tool := os.getenv('VINIX_VMX_TOOL')
	if tool == '' { return }
	work := hosttest.work_dir('', 'vinix-vmx-cli-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	temporary := join(work, 'temporary')
	os.mkdir(temporary)!
	mut env := os.environ()
	env['TMPDIR'] = temporary
	env['CC'] = 'clang'
	legacy := hosttest.capture(['git', '-C', hosttest.root(), 'show',
		'bf2fdd33705f85aa5ce9b33e8304cdb8c1633e16^:kernel/c/vmx.c'], '', 30, env)!
	assert legacy.code == 0 && legacy.stderr == ''
	original := join(work, 'pre-port vmx.c')
	os.write_file(original, legacy.stdout)!
	for argv in [[]string{}, ['--orig', original]] {
		mut command := [tool]
		command << argv
		result := hosttest.capture_in(command, '', 120, env, work)!
		assert result.code == 0 && result.stderr == '', result.stderr
		assert result.stdout.starts_with('VMX CONTROL PASS: 7680 C ABI cases, failure status and guarded VMREAD\nVMX UNSUPPORTED PASS: C ABI, no output mutation, null no-ops\n')
		assert result.stdout.contains('VMX INSTRUCTION PASS: optimized x86 ports, CF/ZF capture, operands and barriers\n')
		assert result.stdout.ends_with('PASS VMX production V C ABI, ASan/UBSan, x86 assembly and no allocator imports\n')
		if argv.len > 0 {
			assert result.stdout.contains(' instruction bytes match original C assembly\n')
		}
		assert os.ls(temporary)!.len == 0
	}
	assert legacy.stdout.contains('pushq %rbp')
	os.write_file(original, legacy.stdout.replace('pushq %rbp', 'pushq %rax'))!
	mismatch := hosttest.capture_in([tool, '--original=' + original], '', 120, env, work)!
	assert mismatch.code == 1 && mismatch.stderr == 'VM entry bytes changed\n', mismatch.stderr
	assert mismatch.stdout.contains('VMX INSTRUCTION PASS:') && !mismatch.stdout.contains('VMX ENTRY PASS:') && !mismatch.stdout.contains('PASS VMX production')
	assert os.ls(temporary)!.len == 0
	env['CC'] = '/absent/vinix-vmx-compiler'
	failed := hosttest.capture([tool], '', 60, env)!
	assert failed.code == 1 && failed.stdout == '' && failed.stderr.contains(env['CC'])
	assert os.ls(temporary)!.len == 0
	for argv in [['--unknown'], ['extra'], ['--original'], ['--original', '--unknown']] {
		mut command := [tool]
		command << argv
		result := hosttest.capture(command, '', 30, env)!
		assert result.code == 2 && result.stdout == '' && result.stderr != ''
	}
	for argument in ['--help', '-h'] {
		result := hosttest.capture([tool, argument], '', 30, env)!
		assert result.code == 0 && result.stderr == '' && result.stdout.starts_with('Usage:')
	}
}
