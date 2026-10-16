module pkglaunch
import json2

fn compat_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn test_previous_and_current_transport_acceptance_and_receipts() {
	mut raw := []u8{cap: 255}
	for byte in 1 .. 256 { raw << u8(byte) }
	mut full := ['run-args', 'app', '--data-cwd']; unsafe { full.flags |= .noslices }
	for _ in 0 .. 256 { full << '--file'; full << '/tmp/doc' }; full << '--'
	for _ in 0 .. 256 { full << '' }
	requests := [
		Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app'] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-terminal', 'app', '/tmp/é'] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-window', 'app'] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', '', 'é🚀', raw.bytestr()] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-terminal-args', 'app', '--', '\b\f\n\r\t"\\'] },
		Request{ nonce: 'a'.repeat(32), arguments: full },
		Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app', ...[]string{len: 256, init: '/tmp/doc'}] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', 'x'.repeat(4096)] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', ...[]string{len: 16, init: '\x01'.repeat(4095)}] },
		Request{ nonce: 'bad', arguments: ['run', 'app'] },
		Request{ nonce: 'A'.repeat(32), arguments: ['run', 'app'] },
		Request{ format: 2, nonce: 'a'.repeat(32), arguments: ['run', 'app'] },
		Request{ nonce: 'a'.repeat(32), arguments: ['update', 'app'] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app', 'relative'] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', 'nul\x00'] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', 'x'.repeat(4097)] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', ...[]string{len: 257, init: ''}] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run', 'app', ...[]string{len: 257, init: '/tmp/doc'}] },
		Request{ nonce: 'a'.repeat(32), arguments: ['run-args', 'app', '--', ...[]string{len: 16, init: 'x'.repeat(4096)}] },
		Request{ nonce: 'a'.repeat(32), arguments: []string{len: 773, init: ''} },
	]
	for index, request in requests {
		text := json2.encode(request)
		if mut parsed := decode(text) {
			assert parsed.arguments == request.arguments && parsed.nonce == request.nonce
			for code in [0, 37, 126, 127, 143, 255]! {
				receipt := parsed.receipt(code); assert parsed.result(receipt)! == code
				println('COMPAT ' + index.str() + ' ' + receipt); unsafe { receipt.free() }
			}
			parsed.close()
		} else { compat_error(err); println('REFUSED ' + index.str()) }
		unsafe { text.free() }
	}
	text := requests[0].encode()!
	mut cases := ['', ' ', '{}', text + ' ', ' ' + text, text + '\n',
		text.replace('"format":1', '"format":1.0'), text.replace('"format":1', '"format":1,"format":1'),
		text.replace('"nonce":', '"extra":{},"nonce":'), text.replace('"app"', '"\\u0061pp"'),
		text.replace('"app"', '"\\ud800"'), text.replace('"app"', 'null'), text.replace('"app"', '[]'),
		text.replace('"app"', 'true'), text.replace('"app"', '1'), text.replace('"app"', '"\\u00ZZ"')]
	unsafe { cases.flags |= .noslices }
	for cut in 0 .. text.len { cases << text[..cut] }
	for index, value in cases {
		if mut parsed := decode(value) { parsed.close(); println('MALFORMED ACCEPTED ' + index.str()) }
		else { compat_error(err); println('MALFORMED REFUSED ' + index.str()) }
	}
}
