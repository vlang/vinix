// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browsercookies
import browseripc
import time

// Root every asynchronous operation until its real WebKit completion. No
// command is admitted while restoration or a cookie operation is pending.
struct CookieRestore {
	engine   &Engine @[required]
	deadline u64
mut:
	records []browsercookies.Cookie
	index   int
}

fn (mut e Engine) expire_cookie_operations(now u64) {
	for _, job in e.jobs {
		if now >= job.deadline {
			e.closed = true
			return
		}
	}
	if e.restore != unsafe { nil } && now >= e.restore.deadline { e.closed = true }
}

fn (mut e Engine) restore_cookies() ! {
	if e.store == unsafe { nil } { return error('cookie-snapshot-unavailable') }
	records := e.store.load()!
	e.restore = &CookieRestore{
		engine:   &e
		records:  records
		deadline: time.sys_mono_now() + u64(30 * time.second)
	}
	e.restore.next()
}

fn (mut restore CookieRestore) next() {
	mut e := restore.engine
	if e.closed {
		restore.finish()
		return
	}
	for restore.index < restore.records.len {
		cookie := restore.records[restore.index]
		restore.index++
		if expires := cookie.expires {
			if expires <= time.now().unix() { continue }
		}
		// -1 creates a session cookie. A nullable expiry is subsequently set
		// verbatim; no invented Max-Age or header serialization loses attributes.
		item := e.api.cookie_new(cookie.name.str, cookie.value.str, cookie.domain.str,
			cookie.path.str, -1)
		if item == unsafe { nil } {
			e.closed = true
			restore.finish()
			return
		}
		if expires := cookie.expires {
			date := e.api.date_new(expires)
			if date == unsafe { nil } {
				e.api.cookie_free(item)
				e.closed = true
				restore.finish()
				return
			}
			e.api.cookie_set_expires(item, date)
			e.api.date_unref(date)
		}
		e.api.cookie_set_secure(item, i32(cookie.secure))
		e.api.cookie_set_http(item, i32(cookie.http_only))
		e.api.cookie_set_same(item, i32(cookie.same_site))
		e.api.cookie_add(e.cookies, item, unsafe { nil }, cookie_restored, &restore)
		e.api.cookie_free(item) // WebKit copies the cookie before returning.
		return
	}
	restore.finish()
}

fn (mut restore CookieRestore) finish() {
	// load returns owned rows. WebKit has copied every value before its add
	// callback; discard them only once the last callback has released the root.
	browsercookies.dispose_cookies(restore.records)
	restore.records = []browsercookies.Cookie{}
	mut e := restore.engine
	e.restore = unsafe { nil }
}

fn cookie_restored(manager voidptr, result voidptr, data voidptr) {
	mut restore := unsafe { &CookieRestore(data) }
	mut e := restore.engine
	mut err := unsafe { &GError(nil) }
	ok := e.api.cookie_add_done(manager, result, &err)
	failed := err != unsafe { nil } || ok == 0
	if err != unsafe { nil } { e.api.error_free(err) }
	if failed { e.closed = true }
	restore.next()
}

fn (mut e Engine) cookie_flush(h browseripc.Header) {
	job := &CookieJob{ engine: &e, header: h, deadline: time.sys_mono_now() + u64(30 * time.second) }
	e.jobs[h.request] = job
	e.api.cookies_all(e.cookies, unsafe { nil }, cookie_snapshot_ready, job)
}

fn (mut e Engine) cookie_clear(h browseripc.Header, session_only bool) {
	job := &CookieJob{
		engine:       &e
		header:       h
		deadline:     time.sys_mono_now() + u64(30 * time.second)
		session_only: session_only
	}
	e.jobs[h.request] = job
	e.api.cookies_all(e.cookies, unsafe { nil }, cookies_clear_ready, job)
}

fn cookie_string(text &char) !string {
	if text == unsafe { nil } { return error('cookie-field-missing') }
	// Bound before copying a foreign string. Soup owns these zero-terminated
	// strings until the cookie is freed; payload contents never enter errors.
	for i in 0 .. 65537 {
		if unsafe { text[i] } == 0 {
			return unsafe { text.vstring_with_len(i).clone() }
		}
	}
	return error('cookie-field-too-large')
}

fn (e &Engine) snapshot_cookie(item voidptr) !browsercookies.Cookie {
	date := e.api.cookie_expires(item)
	expires := if date == unsafe { nil } { ?i64(none) } else { ?i64(e.api.date_unix(date)) }
	return browsercookies.Cookie{
		name:      cookie_string(e.api.cookie_name(item))!
		value:     cookie_string(e.api.cookie_value(item))!
		domain:    cookie_string(e.api.cookie_domain(item))!
		path:      cookie_string(e.api.cookie_path(item))!
		expires:   expires
		secure:    e.api.cookie_secure(item) != 0
		http_only: e.api.cookie_http_only(item) != 0
		same_site: int(e.api.cookie_same_site(item))
	}
}

fn cookie_snapshot_ready(manager voidptr, result voidptr, data voidptr) {
	mut job := unsafe { &CookieJob(data) }
	mut e := job.engine
	mut err := unsafe { &GError(nil) }
	list := e.api.cookies_all_done(manager, result, &err)
	mut failed := err != unsafe { nil } || e.closed || e.store == unsafe { nil }
	if err != unsafe { nil } { e.api.error_free(err) }
	mut records := []browsercookies.Cookie{}
	mut size := 0
	mut count := 0
	mut node := voidptr(list)
	for node != unsafe { nil } {
		entry := unsafe { &GList(node) }
		count++
		if count > 4096 { failed = true }
		if !failed {
			cookie := e.snapshot_cookie(entry.data) or {
				failed = true
				browsercookies.Cookie{}
			}
			if !failed {
				size += cookie.name.len + cookie.value.len + cookie.domain.len + cookie.path.len + 32
				if size > 4 * 1024 * 1024 { failed = true } else { records << cookie }
			}
		}
		e.api.cookie_free(entry.data)
		node = unsafe { entry.next }
	}
	e.api.list_free(list)
	// Flush succeeds only after this exact engine snapshot is durably committed.
	// In particular an empty successful enumeration replaces the previous jar.
	if !failed { e.store.replace(records) or { failed = true } }
	e.jobs.delete(job.header.request)
	if e.closed { return }
	if failed {
		e.fail(job.header, 'cookie-persistence-failed')
	} else if job.header.op == .cookie_clear {
		payload := [u8(job.matched)]
		e.enqueue(response(job.header, .cookie_cleared, 1), payload)
	} else {
		e.ack(job.header)
	}
}

fn cookies_clear_ready(manager voidptr, result voidptr, data voidptr) {
	mut job := unsafe { &CookieJob(data) }
	mut e := job.engine
	mut err := unsafe { &GError(nil) }
	list := e.api.cookies_all_done(manager, result, &err)
	job.failed = err != unsafe { nil }
	if err != unsafe { nil } { e.api.error_free(err) }
	mut node := voidptr(list)
	mut count := 0
	for node != unsafe { nil } {
		entry := unsafe { &GList(node) }
		count++
		if count > 4096 { job.failed = true }
		if !e.closed && !job.failed && (!job.session_only || e.api.cookie_expires(entry.data) == unsafe { nil }) {
			job.remaining << entry.data
		} else {
			e.api.cookie_free(entry.data)
		}
		node = unsafe { entry.next }
	}
	e.api.list_free(list)
	job.matched = job.remaining.len > 0
	if job.failed {
		for cookie in job.remaining { e.api.cookie_free(cookie) }
		job.remaining.clear()
		e.jobs.delete(job.header.request)
		if !e.closed { e.fail(job.header, 'cookie-clear-failed') }
		return
	}
	job.delete_next()
}
