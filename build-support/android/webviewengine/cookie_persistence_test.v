// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browsercookies
import browseripc
import os
import time

fn C.socketpair(i32, i32, i32, &i32) i32

// Unused engine APIs trap; tests override only cookie operations.
fn cookie_test_unused() { panic('unexpected non-cookie API') }

fn cookie_test_api() Api {
	return Api{
		init:               unsafe { Init(voidptr(cookie_test_unused)) }
		webkit_major:       unsafe { Version(voidptr(cookie_test_unused)) }
		webkit_minor:       unsafe { Version(voidptr(cookie_test_unused)) }
		webkit_micro:       unsafe { Version(voidptr(cookie_test_unused)) }
		gtk_major:          unsafe { Version(voidptr(cookie_test_unused)) }
		gtk_minor:          unsafe { Version(voidptr(cookie_test_unused)) }
		gtk_micro:          unsafe { Version(voidptr(cookie_test_unused)) }
		window:             unsafe { New(voidptr(cookie_test_unused)) }
		window_size:        unsafe { Size(voidptr(cookie_test_unused)) }
		window_child:       unsafe { Child(voidptr(cookie_test_unused)) }
		present:            unsafe { Call(voidptr(cookie_test_unused)) }
		destroy:            unsafe { Call(voidptr(cookie_test_unused)) }
		view_type:          unsafe { Type(voidptr(cookie_test_unused)) }
		view_new:           unsafe { NewView(voidptr(cookie_test_unused)) }
		session_new:        unsafe { NewSession(voidptr(cookie_test_unused)) }
		session_cookies:    unsafe { Get(voidptr(cookie_test_unused)) }
		settings:           unsafe { Get(voidptr(cookie_test_unused)) }
		javascript:         unsafe { SetFlag(voidptr(cookie_test_unused)) }
		acceleration:       unsafe { SetFlag(voidptr(cookie_test_unused)) }
		load:               unsafe { SetText(voidptr(cookie_test_unused)) }
		can_edit:           unsafe { CanEdit(voidptr(cookie_test_unused)) }
		can_edit_done:      unsafe { CookieDone(voidptr(cookie_test_unused)) }
		edit_text:          unsafe { EditText(voidptr(cookie_test_unused)) }
		uri:                unsafe { GetText(voidptr(cookie_test_unused)) }
		iterate:            unsafe { Iterate(voidptr(cookie_test_unused)) }
		connect:            unsafe { Connect(voidptr(cookie_test_unused)) }
		disconnect:         unsafe { Disconnect(voidptr(cookie_test_unused)) }
		snapshot:           unsafe { Snapshot(voidptr(cookie_test_unused)) }
		snapshot_done:      unsafe { SnapshotDone(voidptr(cookie_test_unused)) }
		width:              unsafe { Dimension(voidptr(cookie_test_unused)) }
		height:             unsafe { Dimension(voidptr(cookie_test_unused)) }
		download:           unsafe { Download(voidptr(cookie_test_unused)) }
		ref:                unsafe { Get(voidptr(cookie_test_unused)) }
		unref:              unsafe { Call(voidptr(cookie_test_unused)) }
		free:               unsafe { Call(voidptr(cookie_test_unused)) }
		error_free:         cookie_test_error_free
		uri_parse:          unsafe { UriParse(voidptr(cookie_test_unused)) }
		uri_scheme:         unsafe { GetText(voidptr(cookie_test_unused)) }
		uri_unref:          unsafe { Call(voidptr(cookie_test_unused)) }
		cookie_parse:       unsafe { CookieParse(voidptr(cookie_test_unused)) }
		cookie_storage:     unsafe { CookieStorage(voidptr(cookie_test_unused)) }
		cookie_free:        cookie_test_free
		cookie_header:      unsafe { GetText(voidptr(cookie_test_unused)) }
		cookie_add:         cookie_test_add
		cookie_add_done:    cookie_test_done
		cookie_delete:      cookie_test_delete
		cookie_delete_done: cookie_test_done
		cookies_get:        unsafe { GetCookies(voidptr(cookie_test_unused)) }
		cookies_done:       unsafe { CookiesDone(voidptr(cookie_test_unused)) }
		cookies_all:        cookie_test_all
		cookies_all_done:   cookie_test_all_done
		cookie_new:         cookie_test_new
		cookie_name:        cookie_test_name
		cookie_value:       cookie_test_value
		cookie_domain:      cookie_test_domain
		cookie_path:        cookie_test_path
		cookie_expires:     cookie_test_expires
		cookie_secure:      cookie_test_secure
		cookie_http_only:   cookie_test_http
		cookie_same_site:   cookie_test_same
		cookie_set_expires: cookie_test_set_expires
		cookie_set_secure:  cookie_test_set_secure
		cookie_set_http:    cookie_test_set_http
		cookie_set_same:    cookie_test_set_same
		date_unix:          cookie_test_date_unix
		date_new:           cookie_test_date_new
		date_unref:         cookie_test_noop
		list_free:          cookie_test_list_free
		policy_action:      unsafe { Get(voidptr(cookie_test_unused)) }
		action_request:     unsafe { Get(voidptr(cookie_test_unused)) }
		request_uri:        unsafe { GetText(voidptr(cookie_test_unused)) }
		policy_use:         unsafe { Call(voidptr(cookie_test_unused)) }
		policy_ignore:      unsafe { Call(voidptr(cookie_test_unused)) }
		native_surface:     unsafe { Get(voidptr(cookie_test_unused)) }
		xid:                unsafe { Xid(voidptr(cookie_test_unused)) }
		display_default:    unsafe { New(voidptr(cookie_test_unused)) }
		xdisplay:           unsafe { Get(voidptr(cookie_test_unused)) }
		xroot:              unsafe { Root(voidptr(cookie_test_unused)) }
		xtranslate:         unsafe { Translate(voidptr(cookie_test_unused)) }
		xfocus:             unsafe { Focus(voidptr(cookie_test_unused)) }
		xmotion:            unsafe { Motion(voidptr(cookie_test_unused)) }
		xbutton:            unsafe { Button(voidptr(cookie_test_unused)) }
		xkeycode:           unsafe { Keycode(voidptr(cookie_test_unused)) }
		xkey:               unsafe { FakeKey(voidptr(cookie_test_unused)) }
		xflush:             unsafe { Flush(voidptr(cookie_test_unused)) }
		xsync:              unsafe { Sync(voidptr(cookie_test_unused)) }
	}
}

@[heap]
struct TestCookie {
mut:
	name      string
	value     string
	domain    string
	path      string
	expiry    ?i64
	secure    bool
	http_only bool
	same_site int
	freed     bool
}

@[heap]
struct CookieFixture {
mut:
	items    []&TestCookie
	kind     string
	callback Ready = unsafe { nil }
	data     voidptr
	item     &TestCookie = unsafe { nil }
	fail     bool
	error    bool
	freed    int
	lists    int
	calls    int
}

__global cookie_test_fixture = &CookieFixture{}

struct CookieTestDate {
	value i64
}

fn cookie_test_noop(_ voidptr) {}

fn cookie_test_new(n &char, v &char, d &char, p &char, _ i32) voidptr {
	return &TestCookie{ name: unsafe { n.vstring().clone() }, value: unsafe { v.vstring().clone() }, domain: unsafe { d.vstring().clone() }, path: unsafe { p.vstring().clone() } }
}

fn cookie_test_name(p voidptr) &char { return unsafe { (&TestCookie(p)).name.str } }

fn cookie_test_value(p voidptr) &char { return unsafe { (&TestCookie(p)).value.str } }

fn cookie_test_domain(p voidptr) &char { return unsafe { (&TestCookie(p)).domain.str } }

fn cookie_test_path(p voidptr) &char { return unsafe { (&TestCookie(p)).path.str } }

fn cookie_test_expires(p voidptr) voidptr {
	item := unsafe { &TestCookie(p) }
	if value := item.expiry { return &CookieTestDate{ value: value } }
	return unsafe { nil }
}

fn cookie_test_secure(p voidptr) i32 { return i32(unsafe { (&TestCookie(p)).secure }) }

fn cookie_test_http(p voidptr) i32 { return i32(unsafe { (&TestCookie(p)).http_only }) }

fn cookie_test_same(p voidptr) i32 { return i32(unsafe { (&TestCookie(p)).same_site }) }

fn cookie_test_date_new(value i64) voidptr { return &CookieTestDate{ value: value } }

fn cookie_test_date_unix(p voidptr) i64 { return unsafe { (&CookieTestDate(p)).value } }

fn cookie_test_set_expires(p voidptr, d voidptr) {
	mut item := unsafe { &TestCookie(p) }
	item.expiry = cookie_test_date_unix(d)
}

fn cookie_test_set_secure(p voidptr, b i32) {
	mut item := unsafe { &TestCookie(p) }
	item.secure = b != 0
}

fn cookie_test_set_http(p voidptr, b i32) {
	mut item := unsafe { &TestCookie(p) }
	item.http_only = b != 0
}

fn cookie_test_set_same(p voidptr, b i32) {
	mut item := unsafe { &TestCookie(p) }
	item.same_site = int(b)
}

fn cookie_test_free(p voidptr) {
	mut item := unsafe { &TestCookie(p) }
	assert !item.freed
	item.freed = true
	cookie_test_fixture.freed++
}

fn cookie_test_error_free(_ voidptr) { cookie_test_fixture.error = false }

fn cookie_test_list_free(_ voidptr) { cookie_test_fixture.lists++ }

fn cookie_test_queue(kind string, cb Ready, data voidptr) {
	assert cookie_test_fixture.kind == ''
	cookie_test_fixture.kind = kind
	cookie_test_fixture.callback = cb
	cookie_test_fixture.data = data
	cookie_test_fixture.calls++
}

fn cookie_test_all(_ voidptr, _ voidptr, cb Ready, data voidptr) {
	cookie_test_queue('all', cb, data)
}

fn cookie_test_add(_ voidptr, p voidptr, _ voidptr, cb Ready, data voidptr) {
	item := unsafe { &TestCookie(p) }
	cookie_test_fixture.item = &TestCookie{ ...*item }
	cookie_test_queue('add', cb, data)
}

fn cookie_test_delete(_ voidptr, p voidptr, _ voidptr, cb Ready, data voidptr) {
	item := unsafe { &TestCookie(p) }
	cookie_test_fixture.item = &TestCookie{ ...*item }
	cookie_test_queue('delete', cb, data)
}

fn cookie_test_done(_ voidptr, _ voidptr, err &&GError) i32 {
	if cookie_test_fixture.error { unsafe { *err = &GError{ message: nil } } }
	return if cookie_test_fixture.fail { 0 } else { 1 }
}

fn cookie_test_all_done(_ voidptr, _ voidptr, err &&GError) &GList {
	if cookie_test_fixture.error { unsafe { *err = &GError{ message: nil } } }
	mut list := unsafe { &GList(nil) }
	for item in cookie_test_fixture.items {
		copy := &TestCookie{ ...*item, freed: false }
		list = &GList{ data: copy, next: list, prev: unsafe { nil } }
	}
	return list
}

fn cookie_test_complete() {
	kind := cookie_test_fixture.kind
	assert kind != ''
	cb, data := cookie_test_fixture.callback, cookie_test_fixture.data
	cookie_test_fixture.kind = ''
	if kind == 'add' && !cookie_test_fixture.fail && !cookie_test_fixture.error {
		cookie_test_fixture.items << cookie_test_fixture.item
	} else if kind == 'delete' && !cookie_test_fixture.fail && !cookie_test_fixture.error {
		target := cookie_test_fixture.item
		for i, item in cookie_test_fixture.items {
			if item.name == target.name && item.domain == target.domain && item.path == target.path {
				cookie_test_fixture.items.delete(i)
				break
			}
		}
	}
	cb(unsafe { nil }, unsafe { nil }, data)
}

fn cookie_test_start(label string) !(&Engine, string) {
	return cookie_test_start_fd(label, -1)
}

fn cookie_test_start_fd(label string, fd int) !(&Engine, string) {
	cookie_test_fixture = &CookieFixture{}
	path := os.join_path(os.home_dir(), '.local', 'state', 'vinix', 'android', 'vinix-webview-cookies-' + os.getpid().str() + '-' + label)
	os.mkdir(path)!
	os.chmod(path, 0o700)!
	mut store := browsercookies.open(path)!
	return &Engine{ api: cookie_test_api(), store: store, fd: fd }, path
}

fn cookie_test_finish(mut e Engine, path string) {
	mut store := e.store
	browsercookies.dispose(mut store) or { panic(err) }
	os.rmdir_all(path) or { panic(err) }
}

fn cookie_test_submit(mut e Engine, op browseripc.Op, id u64, payload []u8) {
	h := browseripc.Header{ op: op, request: id, payload_size: u32(payload.len) }
	e.state.submit(h, payload) or { panic(err) }
	e.handle(h, payload)
}

fn cookie_test_reply(e &Engine) browseripc.Header {
	assert e.output.len == 1
	return browseripc.decode_header(e.output[0].header, .engine_to_client) or { panic(err) }
}

fn test_cookie_flush_waits_real_enumeration_and_commit_then_restores_all_attributes() {
	mut e, path := cookie_test_start('persist')!
	defer { cookie_test_finish(mut e, path) }
	cookie_test_fixture.items = [
		&TestCookie{ name: 'session', value: 'utf8-é', domain: 'example.test', path: '/', secure: true, http_only: true, same_site: 2 },
		&TestCookie{ name: 'persistent', value: 'x', domain: '.example.test', path: '/a', expiry: time.now().unix() + 86400, same_site: 1 },
	]
	cookie_test_submit(mut e, .cookie_flush, 1, []u8{})
	assert e.output.len == 0 && e.jobs.len == 1
	assert e.store.load()!.len == 0
	cookie_test_complete()
	assert cookie_test_reply(e).op == .ack && e.jobs.len == 0
	saved := e.store.load()!
	assert saved.len == 2
	cookie_test_fixture.items.clear()
	e.restore_cookies()!
	assert e.restore != unsafe { nil }
	assert cookie_test_fixture.items.len == 0
	cookie_test_complete()
	assert e.restore != unsafe { nil }
	cookie_test_complete()
	assert e.restore == unsafe { nil }
	assert cookie_test_fixture.items.len == 2
	a, b := cookie_test_fixture.items[1], cookie_test_fixture.items[0]
	assert a.name == 'session' && a.value == 'utf8-é' && a.domain == 'example.test' && a.path == '/'
	assert a.expiry == none && a.secure && a.http_only && a.same_site == 2
	assert b.name == 'persistent' && b.domain == '.example.test' && b.path == '/a' && b.same_site == 1
	assert b.expiry == saved[0].expires
}

fn test_cookie_clear_session_preserves_persistent_and_commits_before_boolean_reply() {
	mut e, path := cookie_test_start('session-clear')!
	defer { cookie_test_finish(mut e, path) }
	cookie_test_fixture.items = [
		&TestCookie{ name: 'session', domain: 'example.test', path: '/' },
		&TestCookie{ name: 'persistent', domain: 'example.test', path: '/', expiry: time.now().unix() + 86400 },
	]
	cookie_test_submit(mut e, .cookie_clear, 1, [u8(1)])
	cookie_test_complete() // enumerate
	assert e.output.len == 0 && cookie_test_fixture.kind == 'delete'
	cookie_test_complete() // delete
	assert e.output.len == 0 && cookie_test_fixture.kind == 'all'
	cookie_test_complete() // durable post-delete snapshot
	assert cookie_test_reply(e).op == .cookie_cleared && e.output[0].payload == [u8(1)]
	saved := e.store.load()!
	assert saved.len == 1 && saved[0].name == 'persistent'
	e.output.clear()
	cookie_test_submit(mut e, .cookie_clear, 2, [u8(1)])
	cookie_test_complete()
	cookie_test_complete()
	assert cookie_test_reply(e).op == .cookie_cleared && e.output[0].payload == [u8(0)]
}

fn test_cookie_clear_all_then_flush_does_not_resurrect_snapshot() {
	mut e, path := cookie_test_start('all-clear')!
	defer { cookie_test_finish(mut e, path) }
	cookie_test_fixture.items = [&TestCookie{ name: 'a', domain: 'example.test', path: '/' }]
	cookie_test_submit(mut e, .cookie_flush, 1, []u8{})
	cookie_test_complete()
	assert e.store.load()!.len == 1
	e.output.clear()
	cookie_test_submit(mut e, .cookie_clear, 2, [u8(0)])
	cookie_test_complete()
	cookie_test_complete()
	cookie_test_complete()
	assert cookie_test_reply(e).op == .cookie_cleared && e.output[0].payload == [u8(1)]
	assert e.store.load()!.len == 0
	e.output.clear()
	cookie_test_submit(mut e, .cookie_flush, 3, []u8{})
	cookie_test_complete()
	assert cookie_test_reply(e).op == .ack && e.store.load()!.len == 0
}

fn test_cookie_flush_engine_error_and_storage_failure_never_ack() {
	for backend in [false, true] {
		mut e, path := cookie_test_start(if backend { 'db-failure' } else { 'engine-failure' })!
		cookie_test_fixture.items = [&TestCookie{ name: 'a', domain: 'example.test', path: '/' }]
		if backend { e.store.close()! } else { cookie_test_fixture.error = true }
		cookie_test_submit(mut e, .cookie_flush, 1, []u8{})
		cookie_test_complete()
		assert cookie_test_reply(e).op == .failure && e.jobs.len == 0
		assert cookie_test_fixture.freed == 1 && cookie_test_fixture.lists == 1
		cookie_test_finish(mut e, path)
	}
}

fn test_cookie_restore_failure_blocks_commands_and_closed_completion_does_not_persist() {
	mut e, path := cookie_test_start('restore-failure')!
	defer { cookie_test_finish(mut e, path) }
	e.store.replace([browsercookies.Cookie{ name: 'a', value: 'x', domain: 'example.test', path: '/' }])!
	e.restore_cookies()!
	cookie_test_fixture.fail = true
	cookie_test_complete()
	assert e.closed && e.restore == unsafe { nil }
	assert e.output.len == 0
}

fn test_cookie_snapshot_rejects_attributes_or_bounds_and_retires_closed_job() {
	mut e, path := cookie_test_start('invalid')!
	defer { cookie_test_finish(mut e, path) }
	cookie_test_fixture.items = [&TestCookie{ name: 'a', domain: 'example.test', path: '/', same_site: 3 }]
	cookie_test_submit(mut e, .cookie_flush, 1, []u8{})
	cookie_test_complete()
	assert cookie_test_reply(e).op == .failure && e.store.load()!.len == 0
	e.output.clear()
	cookie_test_fixture.items = [&TestCookie{ name: 'a', domain: 'example.test', path: '/' }]
	cookie_test_submit(mut e, .cookie_flush, 2, []u8{})
	e.closed = true
	cookie_test_complete()
	assert e.output.len == 0 && e.jobs.len == 0 && e.store.load()!.len == 0
}

fn test_cookie_clear_engine_delete_and_durable_snapshot_errors_never_report_success() {
	for stage in ['enumerate', 'delete', 'snapshot', 'storage'] {
		mut e, path := cookie_test_start('clear-error-' + stage)!
		cookie_test_fixture.items = [&TestCookie{ name: 'a', domain: 'example.test', path: '/' }]
		e.store.replace([browsercookies.Cookie{ name: 'old', domain: 'example.test', path: '/' }])!
		cookie_test_submit(mut e, .cookie_clear, 1, [u8(0)])
		if stage == 'enumerate' { cookie_test_fixture.error = true }
		cookie_test_complete()
		if stage != 'enumerate' {
			if stage == 'delete' { cookie_test_fixture.error = true }
			cookie_test_complete()
			if stage != 'delete' {
				if stage == 'snapshot' {
					cookie_test_fixture.error = true
				} else {
					e.store.close()!
				}
				cookie_test_complete()
			}
		}
		assert cookie_test_reply(e).op == .failure && e.jobs.len == 0
		assert cookie_test_fixture.kind == ''
		if stage != 'storage' {
			saved := e.store.load()!
			assert saved.len == 1 && saved[0].name == 'old'
		}
		cookie_test_finish(mut e, path)
	}
}

fn test_cookie_restore_skips_expired_and_input_waits_until_all_restoration_completes() {
	mut sockets := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, &sockets[0]) == 0
	defer {
		C.close(sockets[0])
		C.close(sockets[1])
	}
	control(int(sockets[0]))!
	mut e, path := cookie_test_start_fd('ordered', int(sockets[0]))!
	defer { cookie_test_finish(mut e, path) }
	e.store.replace([
		browsercookies.Cookie{ name: 'expired', domain: 'example.test', path: '/', expires: time.now().unix() - 1 },
		browsercookies.Cookie{ name: 'live', domain: 'example.test', path: '/' },
	])!
	h := browseripc.Header{ op: .cookie_flush, request: 1 }
	frame := browseripc.encode_header(h, .client_to_engine)!
	assert C.write(sockets[1], frame.data, usize(frame.len)) == frame.len
	e.restore_cookies()!
	assert cookie_test_fixture.kind == 'add' && e.restore != unsafe { nil }
	e.read()
	assert e.header_position == 0 && e.jobs.len == 0 && e.output.len == 0
	cookie_test_complete()
	assert e.restore == unsafe { nil } && cookie_test_fixture.items.len == 1
	assert cookie_test_fixture.items[0].name == 'live'
	e.read()
	assert e.jobs.len == 1 && cookie_test_fixture.kind == 'all' && e.output.len == 0
	e.read()
	assert e.jobs.len == 1 && cookie_test_fixture.calls == 2
	cookie_test_complete()
	assert cookie_test_reply(e).op == .ack
}

fn test_cookie_operation_and_restore_timeouts_close_without_false_ack() {
	for restoring in [false, true] {
		mut e, path := cookie_test_start(if restoring { 'restore-timeout' } else { 'flush-timeout' })!
		if restoring {
			e.store.replace([browsercookies.Cookie{ name: 'a', domain: 'example.test', path: '/' }])!
			e.restore_cookies()!
			e.expire_cookie_operations(e.restore.deadline - 1)
			assert !e.closed
			e.expire_cookie_operations(e.restore.deadline)
		} else {
			cookie_test_submit(mut e, .cookie_flush, 1, []u8{})
			e.expire_cookie_operations(e.jobs[1].deadline - 1)
			assert !e.closed
			e.expire_cookie_operations(e.jobs[1].deadline)
		}
		assert e.closed && e.output.len == 0
		cookie_test_complete()
		assert e.output.len == 0 && e.restore == unsafe { nil } && e.jobs.len == 0
		cookie_test_finish(mut e, path)
	}
}
