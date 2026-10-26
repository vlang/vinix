// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browseripc
import browsercookies
import encoding.binary
import time

struct Engine {
	api     Api @[required]
	fd      int
	session voidptr
	cookies voidptr
	store   &browsercookies.Store = unsafe { nil }
mut:
	closed           bool
	state            browseripc.State
	header           []u8 = []u8{len: browseripc.header_size}
	header_position  int
	incoming         browseripc.Header
	payload          []u8
	payload_position int
	output           []Packet
	queued           int
	views            map[u64]&EngineView
	jobs             map[u64]&CookieJob
	images           map[u64]&ImageJob
	text_jobs        map[u64]&TextJob
	policies         map[u64]Policy
	next_policy      u64
	input_pending    bool
	input_header     browseripc.Header
	input_deadline   u64
	restore          &CookieRestore = unsafe { nil }
}

@[heap]
struct EngineView {
	engine     &Engine @[required]
	id         u64
	generation u64
	window     voidptr
	view       voidptr
mut:
	alive         bool = true
	width         int
	height        int
	navigation    u64
	load_started  bool
	signals       []u64
	snapshot_busy bool
	next_snapshot u64
}

struct ImageJob {
	view       &EngineView @[required]
	navigation u64
	width      int
	height     int
}

struct Policy {
	view       &EngineView @[required]
	navigation u64
	decision   voidptr
	deadline   u64
}

fn response(h browseripc.Header, op browseripc.Op, size int) browseripc.Header {
	return browseripc.Header{
		op:           op
		request:      h.request
		view:         h.view
		generation:   h.generation
		navigation:   h.navigation
		payload_size: u32(size)
	}
}

fn (mut e Engine) ack(h browseripc.Header) {
	e.enqueue(response(h, .ack, 0), []u8{})
}

fn (mut e Engine) fail(h browseripc.Header, code string) {
	// Only fixed error codes cross the channel; no GLib error/URI/form/cookie
	// text is printed to stderr or returned as an accidental diagnostic.
	e.enqueue(response(h, .failure, code.len), code.bytes())
}

fn (mut e Engine) event(v &EngineView, op browseripc.Op, payload []u8) {
	if !v.alive || v.navigation == 0 { return }
	e.enqueue(browseripc.Header{
		op:           op
		view:         v.id
		generation:   v.generation
		navigation:   v.navigation
		payload_size: u32(payload.len)
	}, payload)
}

fn load_changed(_ voidptr, stage i32, data voidptr) {
	mut v := unsafe { &EngineView(data) }
	if !v.alive || v.navigation == 0 || stage < 0 || stage > 3 { return }
	// Replacing a provisional load can synchronously finish/cancel the old
	// load inside load_uri. Await the new STARTED before forwarding stages.
	if stage == 0 { v.load_started = true }
	if !v.load_started { return }
	uri := v.engine.api.uri(v.view)
	if uri == unsafe { nil } { return }
	text := unsafe { uri.vstring().clone() }
	if text.len == 0 || text.len > 64 * 1024 { return }
	mut payload := [u8(stage)]
	payload << text.bytes()
	v.engine.event(v, .navigation, payload)
}

fn load_failed(_ voidptr, _ i32, _ &char, _ &GError, data voidptr) i32 {
	mut v := unsafe { &EngineView(data) }
	if v.alive && v.load_started { v.engine.event(v, .failure, 'navigation-failed'.bytes()) }
	return 0
}

fn process_failed(_ voidptr, _ i32, data voidptr) {
	mut v := unsafe { &EngineView(data) }
	if v.alive { v.engine.event(v, .failure, 'web-process-terminated'.bytes()) }
}

fn decide_policy(_ voidptr, decision voidptr, kind i32, data voidptr) i32 {
	mut v := unsafe { &EngineView(data) }
	// Response policy is left to WebKit (downloads unsupported). Navigation and
	// new-window decisions are retained until Android replies asynchronously.
	if !v.alive || v.navigation == 0 || kind !in [0, 1] { return 0 }
	mut e := v.engine
	if e.policies.len >= 64 || e.next_policy == ~u64(0) {
		e.api.policy_ignore(decision)
		return 1
	}
	action := e.api.policy_action(decision)
	request := e.api.action_request(action)
	uri := e.api.request_uri(request)
	if uri == unsafe { nil } {
		e.api.policy_ignore(decision)
		return 1
	}
	text := unsafe { uri.vstring().clone() }
	if text.len == 0 || text.len > 64 * 1024 {
		e.api.policy_ignore(decision)
		return 1
	}
	e.next_policy++
	id := e.next_policy
	e.policies[id] = Policy{
		view:       v
		navigation: v.navigation
		decision:   e.api.ref(decision)
		deadline:   time.sys_mono_now() + u64(15 * time.second)
	}
	mut payload := []u8{len: 8}
	binary.little_endian_put_u64(mut payload, id)
	payload << text.bytes()
	e.enqueue(browseripc.Header{
		op:           .policy_request
		request:      id
		view:         v.id
		generation:   v.generation
		navigation:   v.navigation
		payload_size: u32(payload.len)
	}, payload)
	return 1
}

fn (mut e Engine) create(h browseripc.Header, bytes []u8) {
	window := e.api.window()
	view := e.api.view_new(e.api.view_type(), c'network-session', e.session, unsafe { nil })
	if window == unsafe { nil } || view == unsafe { nil } {
		if window != unsafe { nil } { e.api.destroy(window) }
		if view != unsafe { nil } { e.api.unref(view) }
		e.fail(h, 'view-creation-failed')
		return
	}
	width := int(binary.little_endian_u32(bytes[..4]))
	height := int(binary.little_endian_u32(bytes[4..8]))
	mut v := &EngineView{
		engine:     &e
		id:         h.view
		generation: h.generation
		window:     window
		view:       view
		width:      width
		height:     height
	}
	e.api.window_size(window, width, height)
	e.api.window_child(window, view)
	settings := e.api.settings(view)
	e.api.javascript(settings, 0)
	// WebKitGTK 2.48.1's NEVER hardware acceleration enum is 1.
	e.api.acceleration(settings, 1)
	v.signals << e.api.connect(view, c'load-changed', voidptr(load_changed), v, unsafe { nil }, 0)
	v.signals << e.api.connect(view, c'load-failed', voidptr(load_failed), v, unsafe { nil }, 0)
	v.signals << e.api.connect(view, c'web-process-terminated', voidptr(process_failed), v, unsafe { nil }, 0)
	v.signals << e.api.connect(view, c'decide-policy', voidptr(decide_policy), v, unsafe { nil }, 0)
	e.views[h.view] = v
	e.api.present(window)
	e.ack(h)
}

fn (mut e Engine) destroy(v &EngineView) {
	mut target := unsafe { &EngineView(v) }
	target.alive = false
	for id in target.signals { e.api.disconnect(target.view, id) }
	mut ids := []u64{}
	for id, policy in e.policies {
		if policy.view.id == v.id { ids << id }
	}
	for id in ids { e.remove_policy(id, false) }
	e.api.destroy(target.window)
	e.views.delete(target.id)
	// Outstanding WebKit async callbacks retain EngineView through ImageJob.
	// They observe alive=false and release textures without touching widgets.
}

fn (mut e Engine) remove_policy(id u64, use bool) {
	p := e.policies[id] or { return }
	if use { e.api.policy_use(p.decision) } else { e.api.policy_ignore(p.decision) }
	e.api.unref(p.decision)
	e.policies.delete(id)
}

fn (mut e Engine) handle(h browseripc.Header, bytes []u8) {
	if h.op == .cookie_flush {
		e.cookie_flush(h)
		return
	}
	if h.op == .cookie_clear {
		e.cookie_clear(h, bytes[0] != 0)
		return
	}
	if h.op in [.cookie_set, .cookie_get, .cookie_delete] {
		e.cookie(h, bytes)
		return
	}
	if h.op == .create {
		e.create(h, bytes)
		return
	}
	mut v := e.views[h.view] or {
		e.closed = true
		return
	}
	match h.op {
		.resize {
			v.width = int(binary.little_endian_u32(bytes[..4]))
			v.height = int(binary.little_endian_u32(bytes[4..8]))
			e.api.window_size(v.window, v.width, v.height)
			e.ack(h)
		}
		.navigate {
			v.navigation = h.navigation
			v.load_started = false
			uri := bytes.bytestr()
			e.api.load(v.view, uri.str)
			e.ack(h)
		}
		.javascript {
			e.api.javascript(e.api.settings(v.view), i32(bytes[0]))
			e.ack(h)
		}
		.pointer, .key, .scroll { e.input(h, bytes, v) }
		.text { e.text(h, bytes, v) }
		.destroy {
			e.destroy(v)
			e.ack(h)
		}
		.policy_reply {
			id := binary.little_endian_u64(bytes[..8])
			p := e.policies[id] or {
				e.fail(h, 'unknown-policy')
				return
			}
			if p.view.id != h.view || p.view.generation != h.generation || p.navigation != h.navigation {
				e.fail(h, 'stale-policy')
				return
			}
			e.remove_policy(id, bytes[8] != 0)
			e.ack(h)
		}
		else { e.closed = true }
	}
}

fn image_ready(view voidptr, result voidptr, data voidptr) {
	job := unsafe { &ImageJob(data) }
	mut v := job.view
	mut e := v.engine
	// GLib owns its callback data outside the V heap. Keep an explicit V root
	// until completion, including after Android destroys the visible view.
	e.images.delete(v.id)
	mut err := unsafe { &GError(nil) }
	texture := e.api.snapshot_done(view, result, &err)
	v.snapshot_busy = false
	if err != unsafe { nil } { e.api.error_free(err) }
	if texture == unsafe { nil } { return }
	defer { e.api.unref(texture) }
	if e.closed || !v.alive || v.navigation != job.navigation || v.width != job.width
		|| v.height != job.height {
		return
	}
	width := e.api.width(texture)
	height := e.api.height(texture)
	if width <= 0 || height <= 0 || width > browseripc.max_dimension || height > browseripc.max_dimension {
		return
	}
	mut bytes := []u8{len: 16 + int(width) * int(height) * 4}
	binary.little_endian_put_u32(mut bytes[..4], u32(width))
	binary.little_endian_put_u32(mut bytes[4..8], u32(height))
	binary.little_endian_put_u32(mut bytes[8..12], u32(width * 4))
	binary.little_endian_put_u32(mut bytes[12..16], 1)
	e.api.download(texture, unsafe { &bytes[16] }, u64(width * 4))
	e.event(v, .pixels, bytes)
}

fn (mut e Engine) tick() {
	now := time.sys_mono_now()
	e.drain_input(now)
	if e.closed { return }
	mut expired := []u64{}
	for id, p in e.policies {
		if now >= p.deadline || !p.view.alive || p.navigation != p.view.navigation { expired << id }
	}
	for id in expired { e.remove_policy(id, false) }
	for _, mut v in e.views {
		if !v.alive || v.navigation == 0 || v.snapshot_busy || now < v.next_snapshot
			|| e.queued > browseripc.max_payload {
			continue
		}
		v.snapshot_busy = true
		v.next_snapshot = now + u64(100 * time.millisecond)
		job := &ImageJob{ view: v, navigation: v.navigation, width: v.width, height: v.height }
		e.images[v.id] = job
		// VISIBLE region=0 gives viewport pixels, not a page-sized allocation.
		e.api.snapshot(v.view, 0, 0, unsafe { nil }, image_ready, job)
	}
}
