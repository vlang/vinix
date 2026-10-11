// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import hosttest

fn test_speculation_status_exact_bytes_and_sanitizer_diagnostics() {
	assert speculation_host_pass(hosttest.Result{ stdout: 'SPECULATION POLICY PASS (6144 cases)\n' })
	for text in ['SPECULATION POLICY PASS (6144 cases)', 'SPECULATION POLICY PASS (6143 cases)\n', 'SPECULATION POLICY PASS (6144 cases)\nextra\n'] {
		assert !speculation_host_pass(hosttest.Result{ stdout: text })
	}
	assert !speculation_host_pass(hosttest.Result{ code: 1, stdout: speculation_stdout })
	for diagnostic in ['runtime error', 'AddressSanitizer', 'LeakSanitizer'] {
		assert !speculation_host_pass(hosttest.Result{ stdout: speculation_stdout, stderr: diagnostic })
	}
}
