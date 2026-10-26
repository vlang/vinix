// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browseripc
import encoding.binary
import time

struct CookieJob {
	engine   &Engine @[required]
	header   browseripc.Header
	deadline u64
mut:
	remaining []voidptr
	failed    bool
}

fn fields(bytes []u8) []string {
	mut result := []string{}
	mut offset := 0
	for offset < bytes.len {
		length := int(binary.little_endian_u32(bytes[offset..offset + 4]))
		offset += 4
		result << bytes[offset..offset + length].bytestr()
		offset += length
	}
	return result
}

fn (e &Engine) http_uri(text string) !voidptr {
	mut err := unsafe { &GError(nil) }
	uri := e.api.uri_parse(text.str, 0, &err)
	if err != unsafe { nil } { e.api.error_free(err) }
	if uri == unsafe { nil } { return error('invalid-cookie-uri') }
	scheme := e.api.uri_scheme(uri)
	if scheme == unsafe { nil } || unsafe { scheme.vstring() } !in ['http', 'https'] {
		e.api.uri_unref(uri)
		return error('invalid-cookie-uri')
	}
	return uri
}

fn (mut e Engine) cookie(h browseripc.Header, bytes []u8) {
	values := fields(bytes) // browseripc validated lengths and UTF-8 first.
	uri := e.http_uri(values[0]) or {
		e.fail(h, 'invalid-cookie-uri')
		return
	}
	defer { e.api.uri_unref(uri) }
	job := &CookieJob{
		engine:   &e
		header:   h
		deadline: time.sys_mono_now() + u64(30 * time.second)
	}
	e.jobs[h.request] = job
	if h.op == .cookie_set {
		cookie := e.api.cookie_parse(values[1].str, uri)
		if cookie == unsafe { nil } {
			e.jobs.delete(h.request)
			e.fail(h, 'invalid-cookie')
			return
		}
		e.api.cookie_add(e.cookies, cookie, unsafe { nil }, cookie_added, job)
		e.api.cookie_free(cookie)
	} else {
		e.api.cookies_get(e.cookies, values[0].str, unsafe { nil }, cookies_ready, job)
	}
}

fn cookie_added(manager voidptr, result voidptr, data voidptr) {
	job := unsafe { &CookieJob(data) }
	mut e := job.engine
	mut err := unsafe { &GError(nil) }
	ok := e.api.cookie_add_done(manager, result, &err)
	if err != unsafe { nil } { e.api.error_free(err) }
	e.jobs.delete(job.header.request)
	if ok == 0 { e.fail(job.header, 'cookie-set-failed') } else { e.ack(job.header) }
}

fn cookies_ready(manager voidptr, result voidptr, data voidptr) {
	mut job := unsafe { &CookieJob(data) }
	mut e := job.engine
	mut err := unsafe { &GError(nil) }
	list := e.api.cookies_done(manager, result, &err)
	failed := err != unsafe { nil }
	if failed { e.api.error_free(err) }
	mut node := voidptr(list)
	mut parts := []string{}
	mut total := 0
	for node != unsafe { nil } {
		entry := unsafe { &GList(node) }
		if job.header.op == .cookie_delete && !failed && !e.closed {
			job.remaining << entry.data
		} else {
			if !failed && !e.closed {
				text := e.api.cookie_header(entry.data)
				if text != unsafe { nil } {
					value := unsafe { text.vstring().clone() }
					total += value.len + 2
					if total <= browseripc.max_text { parts << value } else { job.failed = true }
					e.api.free(text)
				}
			}
			e.api.cookie_free(entry.data)
		}
		node = unsafe { entry.next }
	}
	e.api.list_free(list)
	if job.header.op == .cookie_delete && !failed && !e.closed {
		job.delete_next()
		return
	}
	e.jobs.delete(job.header.request)
	if failed || job.failed {
		e.fail(job.header, 'cookie-get-failed')
	} else {
		payload := parts.join('; ').bytes()
		e.enqueue(response(job.header, .cookie_result, payload.len), payload)
	}
}

fn (mut job CookieJob) delete_next() {
	mut e := job.engine
	if e.closed {
		for cookie in job.remaining { e.api.cookie_free(cookie) }
		job.remaining.clear()
		e.jobs.delete(job.header.request)
		return
	}
	if job.remaining.len == 0 {
		e.jobs.delete(job.header.request)
		if job.failed { e.fail(job.header, 'cookie-delete-failed') } else { e.ack(job.header) }
		return
	}
	cookie := job.remaining.last()
	job.remaining.delete_last()
	e.api.cookie_delete(e.cookies, cookie, unsafe { nil }, cookie_deleted, &job)
	e.api.cookie_free(cookie)
}

fn cookie_deleted(manager voidptr, result voidptr, data voidptr) {
	mut job := unsafe { &CookieJob(data) }
	mut err := unsafe { &GError(nil) }
	ok := job.engine.api.cookie_delete_done(manager, result, &err)
	if err != unsafe { nil } { job.engine.api.error_free(err) }
	if ok == 0 { job.failed = true }
	job.delete_next()
}
