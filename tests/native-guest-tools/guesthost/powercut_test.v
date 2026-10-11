// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

fn test_powercut_completion_requires_entire_phase_number_and_line() {
	policy := PowercutPolicy{ start: 'START', done: 'DONE', phase: 'create', failures: ['FAIL'] }
	assert powercut_verdict('START\nDONE create ino=123\r\r\n', policy) == 0
	for text in ['START\nDONE create ino=123', 'START\nDONE create ino=\n', 'START\nDONE create ino=123x\n',
		'START\nDONE cleanup ino=0\n', 'DONE create ino=1\n', 'START FAIL\nDONE create ino=0\n',
		'START\nDONE create ino=0\nDONE cleanup ino=0\nFAIL'] {
		assert powercut_verdict(text, policy) == 1
	}
	phase, number := powercut_done('DONE ! ino=0\nDONE other_1 ino=18446744073709551616\r\n', 'DONE') or { panic('Missing complete match') }
	assert phase == 'other_1' && number == '18446744073709551616'
}
