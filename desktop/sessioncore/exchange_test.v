// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

fn test_clipboard_types_history_and_private_values() {
	mut e := &Exchange{}
	e.copy(1000, 10, .html, '<b>Hello</b>', false) or { panic(err) }
	e.copy(1000, 10, .text, 'Hello', false) or { panic(err) }
	e.copy(1000, 10, .html, '<b>Hello</b>', false) or { panic(err) }
	assert e.count == 2 && e.history[0].kind == .html
	e.copy(1000, 11, .text, 'password', true) or { panic(err) }
	assert e.count == 2
	e.revoke(11)
	assert e.current.len == 0
	if _ := e.select_history(0, 1001) {
		assert false
	}
	e.select_history(1, 1000) or { panic(err) }
	assert e.current.data() == 'Hello'
}

fn test_exchange_requires_both_peers_type_and_one_use() {
	mut e := &Exchange{}
	e.grant(123, 1000, 10, 20, .uri_list, 0) or { panic(err) }
	if _ := e.consume(123, 1001, 10, 20, .uri_list, 1) {
		assert false
	}
	if _ := e.consume(123, 1000, 10, 21, .uri_list, 1) {
		assert false
	}
	if _ := e.consume(123, 1000, 10, 20, .text, 1) {
		assert false
	}
	e.consume(123, 1000, 10, 20, .uri_list, 1) or { panic(err) }
	if _ := e.consume(123, 1000, 10, 20, .uri_list, 2) {
		assert false
	}
	e.grant(124, 1000, 10, 20, .text, 0) or { panic(err) }
	if _ := e.consume(124, 1000, 10, 20, .text, 5000) {
		assert false
	}
}

fn test_mime_and_uri_associations_validate_identity() {
	mut a := Associations{}
	a.set('text/plain', 'vinix-editor', false) or { panic(err) }
	a.set('https', 'vinix-firefox', true) or { panic(err) }
	assert a.resolve(mime_for_path('/tmp/HELLO.TXT'), false) or { '' } == 'vinix-editor'
	assert a.resolve('https', true) or { '' } == 'vinix-firefox'
	if _ := a.set('https', 'sh -c', true) {
		assert false
	}
	if _ := a.set('1bad', 'vinix-firefox', true) {
		assert false
	}
}
