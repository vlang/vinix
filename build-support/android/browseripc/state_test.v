// SPDX-License-Identifier: GPL-2.0-or-later
module browseripc

fn packet(op Op, request u64, view u64, generation u64, navigation u64, payload []u8) Header {
	return Header{
		op:           op
		request:      request
		view:         view
		generation:   generation
		navigation:   navigation
		payload_size: u32(payload.len)
	}
}

fn test_cookie_session_exact_completions() {
	mut s := State{}
	get := [u8(1), 0, 0, 0, `x`]
	s.submit(packet(.cookie_get, 1, 0, 0, 0, get), get) or { panic(err) }
	if _ := s.receive(packet(.ack, 1, 0, 0, 0, []u8{}), []u8{}) {
		assert false
	}
	assert s.receive(packet(.cookie_result, 1, 0, 0, 0, []u8{}), []u8{}) or { panic(err) }
	if _ := s.receive(packet(.cookie_result, 1, 0, 0, 0, []u8{}), []u8{}) {
		assert false
	}
	set := [u8(1), 0, 0, 0, `x`, 1, 0, 0, 0, `y`]
	s.submit(packet(.cookie_set, 2, 0, 0, 0, set), set) or { panic(err) }
	assert s.receive(packet(.ack, 2, 0, 0, 0, []u8{}), []u8{}) or { panic(err) }
}

fn test_stale_work_after_navigation_and_destroy() {
	mut s := State{}
	size := [u8(1), 0, 0, 0, 1, 0, 0, 0]
	s.submit(packet(.create, 1, 1, 1, 0, size), size) or { panic(err) }
	uri := 'https://example.test/'.bytes()
	s.submit(packet(.navigate, 2, 1, 1, 1, uri), uri) or { panic(err) }
	s.submit(packet(.navigate, 3, 1, 1, 2, uri), uri) or { panic(err) }
	mut old := [u8(3)]
	old << uri
	assert !(s.receive(packet(.navigation, 0, 1, 1, 1, old), old) or { panic(err) })
	assert !(s.receive(packet(.ack, 2, 1, 1, 1, []u8{}), []u8{}) or { panic(err) })
	s.submit(packet(.destroy, 4, 1, 1, 2, []u8{}), []u8{}) or { panic(err) }
	assert !(s.receive(packet(.ack, 1, 1, 1, 0, []u8{}), []u8{}) or { panic(err) })
	assert s.receive(packet(.ack, 4, 1, 1, 2, []u8{}), []u8{}) or { panic(err) }
	s.submit(packet(.create, 5, 2, 2, 0, size), size) or { panic(err) }
	assert !(s.receive(packet(.navigation, 0, 1, 1, 2, old), old) or { panic(err) })
	if _ := s.submit(packet(.create, 6, 1, 3, 0, size), size) {
		assert false
	}
	s.close()
	if _ := s.submit(packet(.create, 7, 3, 3, 0, size), size) {
		assert false
	}
}

fn test_active_mismatch_and_unknown_completion_fail() {
	mut s := State{}
	size := [u8(1), 0, 0, 0, 1, 0, 0, 0]
	s.submit(packet(.create, 1, 1, 1, 0, size), size) or { panic(err) }
	if _ := s.receive(packet(.ack, 1, 1, 2, 0, []u8{}), []u8{}) {
		assert false
	}
	if _ := s.receive(packet(.ack, 2, 1, 1, 0, []u8{}), []u8{}) {
		assert false
	}
}

fn test_failed_create_releases_view() {
	mut s := State{}
	size := [u8(1), 0, 0, 0, 1, 0, 0, 0]
	s.submit(packet(.create, 1, 1, 1, 0, size), size) or { panic(err) }
	failure := 'allocation failed'.bytes()
	assert s.receive(packet(.failure, 1, 1, 1, 0, failure), failure) or { panic(err) }
	if _ := s.submit(packet(.resize, 2, 1, 1, 0, size), size) {
		assert false
	}
	s.submit(packet(.create, 2, 2, 2, 0, size), size) or { panic(err) }
	assert !(s.receive(packet(.failure, 1, 1, 1, 0, failure), failure) or { panic(err) })
}
