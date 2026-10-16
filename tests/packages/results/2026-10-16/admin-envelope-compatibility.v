module pkgadmin
import crypto.sha256
fn compatibility_digest(value string) string {
	bytes := value.bytes(); defer { unsafe { bytes.free() } }
	mut hash := sha256.new(); mut digest := []u8{len: sha256.size}
	defer { unsafe { hash.free(); free(hash); digest.free() } }
	hash.write(bytes) or { panic(err) }; hash.checksum_into(mut digest)
	return digest.hex()
}
fn compatibility_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn test_admin_wire_compatibility() {
	fingerprint := 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
	nonce := '0123456789abcdef0123456789abcdef'
	inputs := [['update'], ['--progress', '--offline', 'apply', fingerprint, 'install', 'app'],
		['apply', fingerprint, 'remove', 'app'], ['apply', fingerprint, 'upgrade'], ['apply', fingerprint, 'repair'],
		['apply', fingerprint, 'rollback'], ['cleanup-apply', fingerprint], ['repo-apply', fingerprint, 'revoke', 'publisher'],
		['repo-apply', fingerprint, 'enroll', 'publisher', 'file:///media/with spaces; $literal "quotes" \\ 💡', fingerprint],
		['deployment-apply', fingerprint, '/etc/company/approved apps.json'], ['policy-apply', fingerprint, '/etc/company/policy.json'],
		['mirror-apply', fingerprint, '/media/offline', 'app'], ['mirror-deployment-apply', fingerprint, '/media/offline', '/etc/company/lock.json']]
	for index, arguments in inputs {
		request := Request{ nonce: nonce, arguments: arguments }; text := request.encode()!
		println('ADMIN COMPAT encode ' + index.str() + ' ' + compatibility_digest(text))
		mut decoded := decode(text)!; assert decoded.arguments == arguments && decoded.nonce == nonce; decoded.close()
		for code in [0, 1, 37, 124, 126, 127, 143, 255]! {
			receipt := request.receipt(code); assert request.result(receipt)! == code
			println('ADMIN COMPAT receipt ' + index.str() + ' ' + code.str() + ' ' + compatibility_digest(receipt))
		}
	}
	// Every printable byte, including non-UTF-8 Unix path bytes, quotes and
	// backslashes. Record legacy refusals too, rather than assuming acceptance.
	for byte in 32 .. 256 {
		value := [u8(`/`), u8(byte)].bytestr()
		request := Request{ nonce: nonce, arguments: ['policy-apply', fingerprint, value] }
		if text := request.encode() {
			if mut decoded := decode(text) { assert decoded.arguments == request.arguments; decoded.close(); println('ADMIN COMPAT byte ' + byte.str() + ' ' + compatibility_digest(text)) }
			else { compatibility_error(err); println('ADMIN COMPAT byte ' + byte.str() + ' refused') }
		} else { compatibility_error(err); println('ADMIN COMPAT byte ' + byte.str() + ' refused') }
	}
	request := Request{ nonce: nonce, arguments: ['policy-apply', fingerprint, '/etc/company/policy.json'] }
	text := request.encode()!
	mut invalid := [text + '{}', text + ' ', ' ' + text, text.replace('"format":1', '"format":2'),
		text.replace('"format":1', '"format":"1"'), text.replace('"format":1', '"format":null'),
		text.replace('"format":1', '"format":1,"unknown":[]'), text.replace('"format":1', '"format":1,"format":1'),
		text.replace('"format":1', '"forma\\u0074":1'), text.replace('"arguments":[', '"arguments":[{},'),
		text.replace('"arguments":[', '"arguments":[17,'), text.replace('"arguments":[', '"arguments":[null,'),
		text.replace('/etc/company/policy.json', '/bad\\u0000name'), text.replace('/etc/company/policy.json', '/bad\\nname'),
		text.replace('"policy-apply"', '"run"'), text.replace(']}', ',]}')]
	for cut in 0 .. text.len { invalid << unsafe { tos(text.str, cut).clone() } }
	for index, value in invalid {
		if mut decoded := decode(value) { decoded.close(); println('ADMIN COMPAT invalid ' + index.str() + ' accepted') }
		else { compatibility_error(err); println('ADMIN COMPAT invalid ' + index.str() + ' refused') }
	}
	mut arguments := ['--progress', '--offline', 'apply', fingerprint, 'install']
	for i in 0 .. 64 { arguments << 'app-' + i.str() }
	batch := Request{ nonce: nonce, arguments: arguments }; batch_text := batch.encode()!
	mut decoded_batch := decode(batch_text)!; assert decoded_batch.arguments == arguments; decoded_batch.close()
	println('ADMIN COMPAT maximum-count ' + compatibility_digest(batch_text))
	seed := Request{ nonce: nonce, arguments: ['policy-apply', fingerprint, '/'] }.encode()!
	path := '/' + 'a'.repeat(request_limit - seed.len)
	boundary := Request{ nonce: nonce, arguments: ['policy-apply', fingerprint, path] }; boundary_text := boundary.encode()!
	assert boundary_text.len == request_limit
	mut decoded_boundary := decode(boundary_text)!; assert decoded_boundary.arguments == boundary.arguments; decoded_boundary.close()
	println('ADMIN COMPAT maximum-bytes ' + compatibility_digest(boundary_text))
}
