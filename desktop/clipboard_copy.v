// SPDX-License-Identifier: GPL-2.0-or-later
// Built-in text clients can copy into the bounded guest session clipboard.
module main

const text_copy_magic = u32(0x54584350)
const text_copy_header_size = 12
const text_copy_reply_size = 12

interface ClipboardCopyApp {
mut:
	take_clipboard_copy_request() []u8
	receive_clipboard_copy_reply(payload string)
}

fn text_copy_request(sequence u32, text string) []u8 {
	if sequence == 0 || text.len == 0 || text.len > clipboard_max_bytes { return []u8{} }
	mut bytes := []u8{cap: text_copy_header_size + text.len}
	wire_put_u32(mut bytes, text_copy_magic)
	wire_put_u32(mut bytes, sequence)
	wire_put_u32(mut bytes, u32(text.len))
	for byte in text { bytes << byte }
	return bytes
}

fn text_copy_reply(sequence u32, success bool) []u8 {
	mut bytes := []u8{cap: text_copy_reply_size}
	wire_put_u32(mut bytes, text_copy_magic)
	wire_put_u32(mut bytes, sequence)
	wire_put_u32(mut bytes, u32(if success { 1 } else { 0 }))
	return bytes
}

fn native_app_text_copy_request(mut app NativeApp) []u8 {
	if mut app is ClipboardCopyApp {
		// The returned array promotes this V3 interface wrapper. Own that
		// wrapper while borrowing its application, just as Color Meter does.
		mut copier := &ClipboardCopyApp(app)
		defer { unsafe { free(copier) } }
		return copier.take_clipboard_copy_request()
	}
	return []u8{}
}

fn native_app_receive_text_copy(mut app NativeApp, payload string) {
	if mut app is ClipboardCopyApp {
		mut copier := ClipboardCopyApp(app)
		copier.receive_clipboard_copy_reply(payload)
	}
}

fn (mut app RemoteApp) handle_native_operation(data string) bool {
	if data.len >= text_copy_header_size && color_meter_read_u32(data, 0) == text_copy_magic {
		return app.handle_text_copy(data)
	}
	return app.handle_desktop_service(data)
}

fn (mut app RemoteApp) handle_text_copy(data string) bool {
	if !app.clipboard_copy || app.standalone || app.peer_features & app_feature_text_copy == 0
		|| unsafe { app.desktop == nil } { return false }
	sequence := text_copy_into_session(mut app.desktop.clipboard, data) or { return false }
	bytes := text_copy_reply(sequence, true)
	defer { unsafe { bytes.free() } }
	answer := app.transact(.desktop_service_reply, 0, 0, editor_bytes_text(bytes)) or { return false }
	defer { if answer.payload.cap > 0 { unsafe { answer.payload.free() } } }
	if !answer.ok { return false }
	app.tree_stale = true
	return true
}

fn text_copy_into_session(mut clipboard HostClipboard, data string) ?u32 {
	if data.len <= text_copy_header_size || data.len > text_copy_header_size + clipboard_max_bytes
		|| color_meter_read_u32(data, 0) != text_copy_magic { return none }
	sequence := color_meter_read_u32(data, 4)
	length := color_meter_read_u32(data, 8)
	if sequence == 0 || length != u32(data.len - text_copy_header_size) { return none }
	text := unsafe { tos(&data.str[text_copy_header_size], int(length)) }
	// A prior asynchronous host read cannot replace a newer explicit copy.
	clipboard.close_request()
	if !clipboard.set_local_text(text) { return none }
	return sequence
}

// Search paste is text entry, so copied Enter/Escape/Backspace bytes cannot
// launch applications, dismiss the menu or modify earlier query characters.
fn (mut d Desktop) paste_start_menu_text(text string) {
	unsafe { d.start_menu_query.flags |= .noslices }
	mut at := 0
	for at < text.len {
		byte := text[at]
		if byte == `\n` || byte == `\r` || byte == `\t` {
			if d.start_menu_query.len < start_menu_max_query && d.start_menu_query.len > 0
				&& d.start_menu_query[d.start_menu_query.len - 1] != ` ` { d.start_menu_query << u8(` `) }
			at++
			continue
		}
		length := editor_utf8_length(byte)
		if byte < 32 || byte == 127 || length == 0 || at + length > text.len { at++ continue }
		mut valid := true
		for index in 1 .. length { if !editor_utf8_follows(byte, index, text[at + index]) { valid = false break } }
		if !valid { at++ continue }
		if d.start_menu_query.len + length > start_menu_max_query { break }
		for index in 0 .. length { d.start_menu_query << text[at + index] }
		at += length
	}
	d.start_menu_page = 0
	d.start_menu_searching = true
	d.start_menu_all_apps = false
	d.dirty = true
}
