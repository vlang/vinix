// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browseripc
import encoding.binary
import time

struct TextJob {
	view     &EngineView @[required]
	header   browseripc.Header
	text     string
	deadline u64
}

fn (mut e Engine) text(h browseripc.Header, bytes []u8, view &EngineView) {
	job := &TextJob{
		view:     view
		header:   h
		text:     bytes.bytestr()
		deadline: time.sys_mono_now() + u64(30 * time.second)
	}
	e.text_jobs[h.request] = job
	// Native committed text goes through WebCore's focused-frame editing path.
	// No DOM script, synthetic success or temporary X11 keymap is involved.
	e.api.can_edit(view.view, c'InsertText', unsafe { nil }, text_ready, job)
}

fn text_ready(view voidptr, result voidptr, data voidptr) {
	job := unsafe { &TextJob(data) }
	mut v := job.view
	mut e := v.engine
	e.text_jobs.delete(job.header.request)
	mut err := unsafe { &GError(nil) }
	enabled := e.api.can_edit_done(view, result, &err)
	if err != unsafe { nil } { e.api.error_free(err) }
	if e.closed || !v.alive || v.navigation != job.header.navigation { return }
	if enabled == 0 || err != unsafe { nil } {
		e.fail(job.header, 'text-focus-unavailable')
		return
	}
	e.api.edit_text(view, c'InsertText', job.text.str)
	// ACK admits the command to the real engine. It does not assert that a
	// website accepted its value or that authentication succeeded.
	e.ack(job.header)
}

fn scroll_steps(bytes []u8) ![2]i32 {
	mut result := [2]i32{}
	for index in 0 .. 2 {
		delta := i32(binary.little_endian_u32(bytes[index * 4..index * 4 + 4]))
		if delta < -32 || delta > 32 { return error('scroll-step-limit') }
		result[index] = delta
	}
	return result
}

// XTest events enter the real X11/GTK event path. These operations never run
// JavaScript as a substitute for user input. The X server is private to this
// principal, so focus and input cannot be directed at another desktop client.
fn (mut e Engine) input(h browseripc.Header, bytes []u8, v &EngineView) {
	if h.op == .pointer && bytes[8] != 0 && bytes[9] == 0 {
		e.fail(h, 'invalid-input-button')
		return
	}
	// Validate both axes before sending any event; a rejected operation must
	// not partially scroll the page first.
	steps := if h.op == .scroll {
		scroll_steps(bytes) or {
			e.fail(h, 'scroll-step-limit')
			return
		}
	} else {
		[2]i32{}
	}
	surface := e.api.native_surface(v.window)
	if surface == unsafe { nil } {
		e.fail(h, 'input-surface-unavailable')
		return
	}
	xid := e.api.xid(surface)
	display := e.api.xdisplay(e.api.display_default())
	if xid == 0 || display == unsafe { nil } {
		e.fail(h, 'input-display-unavailable')
		return
	}
	e.api.xfocus(display, xid, 2, 0) // RevertToParent, CurrentTime.
	match h.op {
		.pointer {
			x := i32(binary.little_endian_u32(bytes[..4]))
			y := i32(binary.little_endian_u32(bytes[4..8]))
			if x >= v.width || y >= v.height {
				e.fail(h, 'input-outside-viewport')
				return
			}
			mut root_x := i32(0)
			mut root_y := i32(0)
			mut child := u64(0)
			if e.api.xtranslate(display, xid, e.api.xroot(display), x, y, &root_x, &root_y, &child) == 0 {
				e.fail(h, 'input-position-unavailable')
				return
			}
			if e.api.xmotion(display, -1, root_x, root_y, 0) == 0 {
				e.fail(h, 'pointer-injection-failed')
				return
			}
			if bytes[8] != 0 {
				if e.api.xbutton(display, u32(bytes[9]), if bytes[8] == 1 { 1 } else { 0 }, 0) == 0 {
					e.fail(h, 'button-injection-failed')
					return
				}
			}
		}
		.key {
			keysym := u64(binary.little_endian_u32(bytes[..4]))
			keycode := e.api.xkeycode(display, keysym)
			if keycode == 0 {
				e.fail(h, 'key-not-in-keymap')
				return
			}
			if e.api.xkey(display, u32(keycode), i32(bytes[4]), 0) == 0 {
				e.fail(h, 'key-injection-failed')
				return
			}
		}
		.scroll {
			for index in 0 .. 2 {
				delta := steps[index]
				button := if index == 0 {
					if delta < 0 { 6 } else { 7 }
				} else {
					if delta < 0 { 4 } else { 5 }
				}
				count := if delta < 0 { -delta } else { delta }
				for _ in 0 .. count {
					if e.api.xbutton(display, u32(button), 1, 0) == 0
						|| e.api.xbutton(display, u32(button), 0, 0) == 0 {
						e.fail(h, 'scroll-injection-failed')
						return
					}
				}
			}
		}
		else {
			e.fail(h, 'invalid-input-operation')
			return
		}
	}
	e.api.xflush(display)
	// Ensure subsequent native editing commands cannot overtake XTest focus
	// and key events that are still waiting in the private X server's queue.
	e.api.xsync(display, 0)
	e.input_pending = true
	e.input_header = h
	e.input_deadline = time.sys_mono_now() + u64(30 * time.second)
}

fn (mut e Engine) drain_input(now u64) {
	if !e.input_pending { return }
	for _ in 0 .. 64 {
		if e.api.iterate(unsafe { nil }, 0) == 0 {
			e.input_pending = false
			e.ack(e.input_header)
			return
		}
	}
	// Keep the main loop bounded while preserving command order if GTK has
	// more than one batch of events. A non-quiescing loop fails the channel.
	if now >= e.input_deadline { e.closed = true }
}
