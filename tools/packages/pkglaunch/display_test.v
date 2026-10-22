// SPDX-License-Identifier: GPL-2.0-or-later
module pkglaunch

import os

fn display_error(err IError) { message := err.msg(); unsafe { message.free(); err.free() } }
fn display_refuse(text string) {
	if mut accepted := decode(text) { accepted.close(); assert false } else { display_error(err) }
}

fn test_private_display_transport_preserves_literal_input_and_binds_receipt() {
	request := Request{ format: 2, nonce: 'a'.repeat(32), arguments: ['run', 'org.editor', '/home/a; $(literal)'],
		display: ':42', authority: '/run/user/1000/vinix-hosted-x11/app-9/Xauthority' }
	text := request.encode()!
	defer { unsafe { text.free() } }
	mut first := decode(text)!
	mut second := decode(text)!
	first.close()
	assert second.format == 2 && second.display == request.display && second.authority == request.authority
	assert second.arguments == request.arguments
	second.close()
	for cut in 0 .. text.len { display_refuse(unsafe { tos(text.str, cut) }) }
	for bad in [text.replace(':42', ':042'), text.replace('"display":', '"env":'),
		text.replace('"authority":', '"display":":43","authority":'), text.replace('"format":2', '"format":1'),
		text.replace('"authority":', '"uid":1000,"authority":'), text + ' '] { display_refuse(bad); unsafe { bad.free() } }
	receipt := request.receipt(37)
	defer { unsafe { receipt.free() } }
	assert request.result(receipt)! == 37
	changed := Request{ format: 2, nonce: request.nonce, arguments: request.arguments, display: ':43', authority: request.authority }
	if _ := changed.result(receipt) { assert false } else { display_error(err) }
	// Version one is still exactly the existing literal-only wire envelope.
	legacy := Request{ nonce: request.nonce, arguments: ['run', 'org.editor'] }.encode()!
	assert !legacy.contains('display') && !legacy.contains('authority')
	unsafe { legacy.free() }
}

fn test_private_display_display_refuses_ambient_paths_and_control_fields() {
	for authority in ['', '/tmp/Xauthority', '/root/.Xauthority', '/run/user/0/vinix-hosted-x11/app/Xauthority',
		'/run/user/01000/vinix-hosted-x11/app/Xauthority', '/run/user/4294967296/vinix-hosted-x11/app/Xauthority',
		'/run/user/1000/vinix-hosted-x11/../Xauthority', '/run/user/1000/vinix-hosted-x11/a/b/Xauthority',
		'/run/user/1000/vinix-hosted-x11/app/Xauthority\x00tail', '/run/user/1000/vinix-hosted-x11/app/Xauthority/'] {
		request := Request{ format: 2, nonce: 'b'.repeat(32), arguments: ['run', 'app'], display: ':42', authority: authority }
		if value := request.encode() { unsafe { value.free() }; assert false } else { display_error(err) }
	}
	for display in ['', ':01', ':1.0', 'localhost:1', ':65536', ':1\n', ':1\x00tail', ':1\x00', ':1\x00x', ':0\x00'] {
		request := Request{ format: 2, nonce: 'b'.repeat(32), arguments: ['run', 'app'], display: display,
			authority: '/run/user/1000/vinix-hosted-x11/app/Xauthority' }
		if value := request.encode() { unsafe { value.free() }; assert false } else { display_error(err) }
	}
	for display in [':1\\u0000', ':1\\u0000x', ':0\\u0000'] {
		text := '{"format":2,"nonce":"' + 'a'.repeat(32) + '","arguments":["run","app"],"display":"' + display + '","authority":"/run/user/1000/vinix-hosted-x11/app/Xauthority"}'
		display_refuse(text)
		unsafe { text.free() }
	}
	for command in ['run-window', 'run-terminal', 'run-terminal-args'] {
		request := Request{ format: 2, nonce: 'b'.repeat(32), arguments: if command == 'run-terminal-args' { [command, 'app', '--'] } else { [command, 'app'] },
			display: ':42', authority: '/run/user/1000/vinix-hosted-x11/app/Xauthority' }
		if value := request.encode() { unsafe { value.free() }; assert false } else { display_error(err) }
	}
	// A syntactically valid pair still cannot be forwarded without its private
	// filesystem objects. Refusal must leave the worker environment unchanged.
	os.setenv('DISPLAY', 'sentinel-display', true)
	os.setenv('XAUTHORITY', 'sentinel-authority', true)
	request := Request{ format: 2, arguments: ['run', 'app'], display: ':65535',
		authority: '/run/user/4294967295/vinix-hosted-x11/missing/Xauthority' }
	if _ := request.forward_display(4294967295) { assert false } else { display_error(err) }
	assert os.getenv('DISPLAY') == 'sentinel-display' && os.getenv('XAUTHORITY') == 'sentinel-authority'
	Request{}.forward_display(1000)!
	assert os.getenv('DISPLAY') == '' && os.getenv('XAUTHORITY') == ''
}
