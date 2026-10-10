// SPDX-License-Identifier: GPL-2.0-or-later
module boundarycheck

import hosttest
import os

fn test_darwin_directives_symbol_rewrite_and_unterminated_line() {
	source := '.type read_current_sp, %function\n.size read_current_sp, .-read_current_sp\n' +
		'.section .note.GNU-stack,"",%progbits\n.text\n.global read_current_sp\nread_current_sp:\n' +
		'  mov x0, sp\n  ret\n'
	assert darwin_assembly(source) == '.text\n.global _read_current_sp\n_read_current_sp:\n  mov x0, sp\n  ret\n'
	assert darwin_assembly(' .type x\n.type final') == ' .type x\n.type final'
	assert darwin_assembly('') == ''
}

fn test_unsupported_architecture_rejected_before_work_or_commands() {
	compare('/absent/repository', 'x86_64', {}) or {
		assert err.msg() == 'This differential boundary fixture requires an ARM64 host'
		return
	}
	assert false, 'accepted unsupported host architecture'
}

fn test_real_command_success_failures_and_cleanup() {
	tool := os.getenv('VINIX_BOUNDARY_TOOL')
	compiler := os.getenv('VINIX_BOUNDARY_COMPILER_FIXTURE')
	if tool == '' || compiler == '' { return }
	work := hosttest.work_dir('', 'vinix-boundary-qualification-')!
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	mut env := os.environ()
	env['CC'] = compiler
	env['TMPDIR'] = work
	env['VINIX_BOUNDARY_REAL_CC'] = hosttest.tool('clang')
	for mode, diagnostic in {
		'pass':            ''
		'compile-failure': 'forced compiler failure'
		'allocator':       'native boundary allocator import:'
		'mismatch':        'native boundary differential output mismatch:'
		'fixture-failure': 'v fixture failed:'
	} {
		env['VINIX_BOUNDARY_CASE'] = mode
		result := hosttest.capture_in([tool], '', 120, env, work)!
		if mode == 'pass' {
			assert result.code == 0 && result.stderr == ''
			assert result.stdout == 'NATIVE HEADER BOUNDARIES: PASS (10 UART traces, 256 callbacks, stack/counter)\n' +
				'Frozen C / production V ASan/UBSan and stack-use-after-return: PASS\n'
		} else {
			assert result.code == 1 && result.stdout == ''
			assert result.stderr.contains(diagnostic), result.stderr
		}
		assert os.ls(work)!.len == 0, 'temporary boundary or module files remain after ${mode}'
	}
	for argv, code in {
		'--help':    0
		'--unknown': 2
	} {
		result := hosttest.capture([tool, argv], '', 30, env)!
		assert result.code == code
	}
}
