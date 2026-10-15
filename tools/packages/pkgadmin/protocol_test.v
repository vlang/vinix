// SPDX-License-Identifier: GPL-2.0-or-later
module pkgadmin

fn test_reviewed_admin_requests_and_bound_completion() {
	fingerprint := 'a'.repeat(64)
	for arguments in [['update'], ['--progress', 'update'], ['--progress', '--offline', 'apply', fingerprint, 'install', 'org.vinix.memo'],
		['apply', fingerprint, 'upgrade'], ['apply', fingerprint, 'repair'], ['apply', fingerprint, 'rollback'], ['repo-apply', fingerprint, 'revoke', 'publisher'],
		['repo-apply', fingerprint, 'enroll', 'publisher', 'file:///media/with spaces; $literal', fingerprint],
		['deployment-apply', fingerprint, '/etc/company/approved apps.json'], ['policy-apply', fingerprint, '/etc/company/policy.json'],
		['mirror-apply', fingerprint, '/media/offline', 'org.vinix.memo'], ['mirror-deployment-apply', fingerprint, '/media/offline', '/etc/company/lock.json']] {
		request := Request{ nonce: 'b'.repeat(32), arguments: arguments }
		text := request.encode()!
		mut decoded := decode(text)!
		assert decoded.arguments == arguments && decoded.nonce == request.nonce
		for code in [0, 1, 124, 255] {
			result := request.receipt(code)
			assert request.result(result)! == code
			unsafe { result.free() }
		}
		decoded.close(); decoded.close()
		unsafe { text.free() }
	}
}

fn test_admin_transport_refuses_launches_alternate_roots_and_unreviewed_changes() {
	fingerprint := 'a'.repeat(64)
	for arguments in [['run', 'app'], ['run-window', 'app'], ['run-args', 'app', '--', 'literal'],
		['admin-authorize'], ['--root', '/tmp', 'update'], ['--json', 'update'], ['--progress'],
		['install', 'app'], ['remove', 'app'], ['rollback'], ['upgrade'], ['repair'], ['keygen', '/tmp/key'],
		['apply', fingerprint, 'install', '--root'], ['apply', fingerprint, 'install', 'bad; id'],
		['apply', fingerprint, 'upgrade', 'extra'], ['apply', fingerprint, 'repair', 'app'], ['repo-apply', fingerprint, 'revoke', 'publisher', 'extra'],
		['policy-apply', fingerprint, 'relative.json'], ['apply', fingerprint, 'deploy', 'app'],
		['update', 'extra'], ['--offline', '--progress', 'update']] {
		mut refused := false
		validate_arguments(arguments) or { refused = true; unsafe { err.free() } }
		assert refused, arguments.str()
	}
	request := Request{ nonce: 'b'.repeat(32), arguments: ['apply', fingerprint, 'install', 'app'] }
	text := request.encode()!
	for invalid in [text + '{}', text + ' ', text.replace('"format":1', '"format":1,"format":1'),
		text.replace('"format":1', '"format":1,"unknown":0'), text.replace('"format":1', '"format":2'),
		text.replace('"format":1', '"forma\\u0074":1'), 'x'.repeat(request_limit + 1)] {
		mut refused := false
		decode(invalid) or { refused = true; unsafe { err.free() } }
		assert refused
	}
	result := request.receipt(0)
	for invalid in [result + '0', result + ' extra', result.replace(' ' + fingerprint + ' ', ' ' + '0'.repeat(64) + ' '),
		Request{ nonce: 'c'.repeat(32), arguments: request.arguments }.receipt(0),
		Request{ nonce: request.nonce, arguments: ['update'] }.receipt(0)] {
		if invalid == result { continue }
		mut refused := false
		request.result(invalid) or { refused = true; unsafe { err.free() } }
		assert refused
	}
	unsafe { text.free(); result.free() }
}

fn test_admin_batch_and_encoded_request_limits() {
	mut arguments := ['--progress', '--offline', 'apply', 'a'.repeat(64), 'install']
	for index in 0 .. 64 { arguments << 'app-' + index.str() }
	assert arguments.len == 69
	encoded := Request{ nonce: 'b'.repeat(32), arguments: arguments }.encode()!
	unsafe { encoded.free() }
	arguments << 'another'
	mut too_many := false
	validate_arguments(arguments) or { too_many = true; unsafe { err.free() } }
	assert too_many
	large := ['apply', 'a'.repeat(64), 'install', ...[]string{len: 64, init: 'a'.repeat(128)}]
	validate_arguments(large)!
	mut oversized := false
	Request{ nonce: 'b'.repeat(32), arguments: large }.encode() or { oversized = true; unsafe { err.free() } }
	assert oversized
}
