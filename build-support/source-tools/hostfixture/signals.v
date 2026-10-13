// SPDX-License-Identifier: GPL-2.0-or-later
module hostfixture

import os
import sourcecommand

pub struct SignalCase {
pub:
	mode string
	number int
	diagnostic string
}

pub fn signal_cases(kind string) !([]SignalCase, string) {
	return match kind {
		'cxx' { [SignalCase{'abort', 6, 'IOS-CXX-ABORT: stack 17 1099511627776 2.500 0x1234\n'}],
			'IOS-CXX-REFERENCE: formatted diagnostic and SIGABRT' }
		'assertions' { [SignalCase{'with-function', 6, 'Assertion failed: (1 == 2), function fixture, file synthetic.c, line 17.\n'},
			SignalCase{'no-function', 6, 'Assertion failed: (1 == 2), file synthetic.c, line 17.\n'}],
			'IOS-ASSERT-REFERENCE: diagnostics and SIGABRT with/without function names' }
		'safety' { ['memcpy', 'memmove', 'memset', 'strncpy', 'strcat', 'unterminated', 'zero-capacity'].map(SignalCase{mode:it, number:5}),
			'IOS-LIBSYSTEM-SAFETY-REFERENCE: seven genuine SIGTRAP overflow cases' }
		'process' { [SignalCase{'usr1', 30, ''}, SignalCase{'usr2', 31, ''}, SignalCase{'bus', 10, ''}],
			'IOS-PROCESS-REFERENCE: native Darwin SIGUSR1, SIGUSR2 and SIGBUS delivery' }
		else { return error('unknown Darwin signal fixture: ' + kind) }
	}
}

pub fn validate_signal(result sourcecommand.Output, item SignalCase) ! {
	if result.status != -item.number {
		return error('unexpected signal for ' + item.mode + ': ' + result.status.str() + '\n' + result.stdout + result.stderr)
	}
	if item.diagnostic != '' && !result.stderr.contains(item.diagnostic) {
		return error('missing diagnostic for ' + item.mode + '\n' + result.stderr)
	}
}

pub fn signals(kind string, executable string, cancel fn () bool) ! {
	$if !macos { return error('reference signals require native Darwin') }
	cases, label := signal_cases(kind)!
	for item in cases {
		result := sourcecommand.capture_full([executable, item.mode], os.environ(), -1,
			64 * 1024 * 1024, cancel)!
		validate_signal(result, item)!
	}
	println(label)
}
