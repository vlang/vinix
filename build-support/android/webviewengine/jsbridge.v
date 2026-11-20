// SPDX-License-Identifier: GPL-2.0-or-later
module main

import browseripc
import encoding.binary
import time

// WebView.addJavascriptInterface. Android's injected objects are synchronous:
// page code uses their return values directly (GMS sign-in calls
// mm.getAndroidId(), mm.getAccounts() and others). A document-start script
// defines each object; every method calls window.prompt with a private marker.
// The page's JavaScript blocks inside prompt until the script-dialog handler
// closes the dialog, which this engine does once Android replies, keeping the
// GLib loop and other views running meanwhile.
//
// The marker carries a per-engine token so ordinary page prompts are never
// mistaken for bridge calls. It is not a secret from the page: like Android,
// any page in the view may call its injected objects.
const js_bridge_marker = '\x01vinix-bridge:'
const js_bridge_calls = 16
const js_bridge_timeout = 30 * time.second
const webkit_script_dialog_prompt = 2

struct JsBridgeCall {
	view       &EngineView @[required]
	navigation u64
	dialog     voidptr
	deadline   u64
}

// Values cross as tagged text (see browseripc.tagged_list): JavaScript and
// Java both count string length in UTF-16 units, so neither side needs JSON.
fn js_bridge_script(token string, interfaces []browseripc.JsInterface) string {
	mut spec := []string{}
	for iface in interfaces {
		// Names are validated identifiers; they need no escaping in quotes.
		spec << '"' + iface.name + '":["' + iface.methods.join('","') + '"]'
	}
	return '(function(){' +
		'var ask=window.prompt.bind(window),marker="\\u0001vinix-bridge:' + token + '";' +
		'function enc(v){var t=typeof v,s;' +
		'if(v===null)s="z";else if(t==="string")s="s"+v;else if(t==="number")s="n"+String(v);' +
		'else if(t==="boolean")s=v?"b1":"b0";else s="u";return s.length+":"+s;}' +
		'function dec(r){if(r===null)throw new Error("Java bridge unavailable");' +
		'if(r.charAt(0)==="!")throw new Error(r.slice(1));' +
		'var s=r.slice(r.indexOf(":")+1),t=s.charAt(0),d=s.slice(1);' +
		'if(t==="s")return d;if(t==="n")return Number(d);if(t==="b")return d==="1";' +
		'if(t==="z")return null;return undefined;}' +
		'function call(i,m){return function(){var a="";' +
		'for(var j=0;j<arguments.length;j++)a+=enc(arguments[j]);' +
		'return dec(ask(marker,i+"\\n"+m+"\\n"+a));};}' +
		'var d={' + spec.join(',') + '};' +
		'for(var i in d){var o={};for(var j=0;j<d[i].length;j++)o[d[i][j]]=call(i,d[i][j]);' +
		'window[i]=o;}})();'
}

// The prompt result the injected script decodes: "=" and one tagged value, or
// "!" and an exception message.
fn js_bridge_result(status u8, text string) string {
	if status == 0 {
		return '=' + text
	}
	return '!' + if text.len == 0 { 'Java exception' } else { text }
}

fn js_bridge_allowed(interfaces []browseripc.JsInterface, iface string, method string) bool {
	for candidate in interfaces {
		if candidate.name == iface {
			return method in candidate.methods
		}
	}
	return false
}

fn script_dialog(_ voidptr, dialog voidptr, data voidptr) i32 {
	mut v := unsafe { &EngineView(data) }
	mut e := v.engine
	if e.api.dialog_type(dialog) != webkit_script_dialog_prompt {
		return 0
	}
	message := e.api.dialog_message(dialog)
	if message == unsafe { nil } || unsafe { message.vstring() } != js_bridge_marker + e.js_token {
		return 0
	}
	if e.closed || !v.alive || v.navigation == 0 || e.js_calls.len >= js_bridge_calls
		|| e.next_js_call == ~u64(0) {
		e.api.dialog_set_text(dialog, c'!Java bridge is unavailable')
		return 1
	}
	request := e.api.dialog_default(dialog)
	body := if request == unsafe { nil } { '' } else { unsafe { request.vstring().clone() } }
	mut payload := []u8{len: 8}
	binary.little_endian_put_u64(mut payload, e.next_js_call + 1)
	payload << body.bytes()
	call := browseripc.parse_js_call(payload) or {
		e.api.dialog_set_text(dialog, c'!invalid Java bridge call')
		return 1
	}
	if !js_bridge_allowed(v.interfaces, call.iface, call.method) {
		e.api.dialog_set_text(dialog, c'!unknown Java bridge method')
		return 1
	}
	e.next_js_call++
	e.js_calls[call.id] = JsBridgeCall{
		view:       v
		navigation: v.navigation
		dialog:     e.api.dialog_ref(dialog)
		deadline:   time.sys_mono_now() + u64(js_bridge_timeout)
	}
	e.enqueue(browseripc.Header{
		op:           .js_call
		request:      call.id
		view:         v.id
		generation:   v.generation
		navigation:   v.navigation
		payload_size: u32(payload.len)
	}, payload)
	return 1
}

fn (mut e Engine) finish_js_call(id u64, result string) {
	call := e.js_calls[id] or { return }
	e.api.dialog_set_text(call.dialog, result.str)
	e.api.dialog_close(call.dialog)
	e.api.dialog_unref(call.dialog)
	e.js_calls.delete(id)
}

fn (mut e Engine) js_interfaces(h browseripc.Header, bytes []u8, mut v EngineView) {
	interfaces := browseripc.parse_js_interfaces(bytes) or {
		e.closed = true
		return
	}
	v.interfaces = interfaces
	manager := e.api.content_manager(v.view)
	e.api.remove_scripts(manager)
	if interfaces.len > 0 {
		source := js_bridge_script(e.js_token, interfaces)
		// ALL_FRAMES (0) at DOCUMENT_START (0): Android exposes interfaces to
		// every frame, before any page script runs.
		script := e.api.script_new(source.str, 0, 0, unsafe { nil }, unsafe { nil })
		if script == unsafe { nil } {
			e.fail(h, 'javascript-interface-failed')
			return
		}
		e.api.add_script(manager, script)
		e.api.script_unref(script)
	}
	e.ack(h)
}

fn (mut e Engine) js_reply(h browseripc.Header, bytes []u8) {
	id := binary.little_endian_u64(bytes[..8])
	call := e.js_calls[id] or {
		e.fail(h, 'unknown-javascript-call')
		return
	}
	if call.view.id != h.view || call.view.generation != h.generation
		|| call.navigation != h.navigation {
		e.fail(h, 'stale-javascript-call')
		return
	}
	e.finish_js_call(id, js_bridge_result(bytes[8], bytes[9..].bytestr()))
	e.ack(h)
}

// A page that navigated away or a destroyed view can no longer use a reply;
// Android stops calling interface methods for it too.
fn (mut e Engine) expire_js_calls(now u64) {
	mut expired := []u64{}
	for id, call in e.js_calls {
		if now >= call.deadline || !call.view.alive || call.navigation != call.view.navigation {
			expired << id
		}
	}
	for id in expired {
		e.finish_js_call(id, '!Java bridge call was abandoned')
	}
}

fn (mut e Engine) close_js_calls(view u64) {
	mut ids := []u64{}
	for id, call in e.js_calls {
		if call.view.id == view {
			ids << id
		}
	}
	for id in ids {
		e.finish_js_call(id, '!Java bridge view was destroyed')
	}
}
