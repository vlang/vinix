// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import os

fn test_binary_capture_keeps_independent_streams_and_nonzero_status() {
	result := capture_both_preferred(['/bin/sh', '-c',
		'printf "\\377\\000out"; printf "\\200err" >&2; exit 7'], os.environ(), '') or { panic(err) }
	assert result.status == 7
	assert result.stdout.bytes() == [u8(255), 0, `o`, `u`, `t`]
	assert result.stderr.bytes() == [u8(128), `e`, `r`, `r`]
}

fn test_both_full_pipes_are_drained_before_waiting() {
	result := capture_both_preferred(['/bin/sh', '-c',
		'printf "%0600000d" 0 >&2; printf "%0700000d" 0'], os.environ(), '') or { panic(err) }
	assert result.status == 0
	assert result.stdout.len == 700000 && result.stdout.bytes().all(it == `0`)
	assert result.stderr.len == 600000 && result.stderr.bytes().all(it == `0`)
}

fn test_capture_reports_the_child_signal() {
	result := capture_both_preferred(['/bin/sh', '-c', r'kill -TERM $$'], os.environ(), '') or { panic(err) }
	assert result.status == -15
	assert result.stdout == '' && result.stderr == ''
}

fn test_capture_reports_exec_error_without_successful_child() {
	capture_both_preferred(['/vinix-nonexistent-capture-test-command'], os.environ(), '') or {
		assert err is FileError
		assert err.code() == 2
		return
	}
	assert false
}
