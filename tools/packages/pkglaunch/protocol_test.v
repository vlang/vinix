// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

fn refused(arguments []string) bool { validate_arguments(arguments) or { return true }; return false }

fn test_launch_request_is_literal_bounded_and_canonical() {
	for arguments in [['run', 'org.editor'], ['run-terminal', 'org.editor', '/home/a space; $(literal)'],
		['run-window', 'org.memo'], ['run-args', 'org.editor', '--data-cwd', '--file', '/home/doc', '--', '', '-flag', 'é; $(literal)'],
		['run-terminal-args', 'org.editor', '--']] {
		request := Request{ nonce: 'a'.repeat(32), arguments: arguments }
		text := request.encode()!
		mut parsed := decode(text)!
		assert parsed.arguments == arguments && parsed.nonce == request.nonce
		for code in [0, 37, 126, 255] {
			receipt := request.receipt(code)
			assert request.result(receipt)! == code
			unsafe { receipt.free() }
		}
		for bad in [text + ' ', text.replace('"format":1', '"format":1,"extra":0'), text.replace('"format":1', '"format":1,"format":1')] {
			mut failed := false
			decode(bad) or { failed = true }
			assert failed
			unsafe { bad.free() }
		}
		parsed.close(); unsafe { text.free() }
	}
	for arguments in [ []string{}, ['run'], ['run', '../app'], ['run', 'app', 'relative'], ['run', 'app', '/nul\x00'],
		['update', 'app'], ['admin', 'apply'], ['--root', '/tmp', 'run', 'app'], ['run', '--uid', '0'],
		['run-args', 'app'], ['run-args', 'app', '--uid', '0', '--'], ['run-args', 'app', '--data-cwd', '--data-cwd', '--'],
		['run-args', 'app', '--file', '--'], ['run-args', 'app', '--', 'nul\x00'] ] { assert refused(arguments) }
	assert refused(['run', 'app', ...[]string{len: 257, init: '/tmp/doc'}])
	assert refused(['run-args', 'app', '--', ...[]string{len: 17, init: 'x'.repeat(4096)}])
	// Full legacy command size survives JSON escaping and the small auth action.
	request := Request{ nonce: 'b'.repeat(32), arguments: ['run-args', 'app', '--', ...[]string{len: 16, init: '\x01'.repeat(4095)}] }
	text := request.encode()!
	assert text.len > 4096 && text.len < request_limit
	mut parsed := decode(text)!
	assert parsed.arguments == request.arguments
	parsed.close(); unsafe { text.free() }
}

fn test_completion_binds_the_launch_input_and_code() {
	request := Request{ nonce: 'c'.repeat(32), arguments: ['run', 'app'] }
	receipt := request.receipt(37)
	for bad in [receipt + '0', receipt + '\n', receipt.replace(' 37', ' 037'), receipt.replace(' 37', ' -1'), receipt.replace(' 37', ' 256')] {
		mut failed := false
		request.result(bad) or { failed = true }
		assert failed
	}
	mut failed := false
	Request{ nonce: request.nonce, arguments: ['run', 'another'] }.result(receipt) or { failed = true }
	assert failed
}
