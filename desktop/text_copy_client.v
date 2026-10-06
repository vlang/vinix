// SPDX-License-Identifier: GPL-2.0-or-later
// Small read-only clients snapshot text until the existing clipboard IPC owns it.
module main

enum TextCopyStatus {
	idle
	pending
	copied
	unavailable
	too_large
	empty
	failed
}

struct TextCopyClient {
mut:
	sequence u32
	packet []u8
	waiting bool
	status TextCopyStatus
}

fn (mut client TextCopyClient) release_packet() {
	unsafe { client.packet.free() }
	client.packet = []u8{}
}

fn (mut client TextCopyClient) reject(status TextCopyStatus) {
	client.release_packet()
	client.waiting = false
	client.status = status
}

// Replace older requests even on rejection: their late acknowledgement cannot
// change the status of the user's most recent explicit Copy action.
fn (mut client TextCopyClient) queue(text string) bool {
	client.release_packet()
	client.waiting = false
	if app_compositor_features & app_feature_text_copy == 0 {
		client.status = .unavailable
		return false
	}
	if text.len == 0 {
		client.status = .empty
		return false
	}
	if text.len > clipboard_max_bytes {
		client.status = .too_large
		return false
	}
	client.sequence++
	if client.sequence == 0 { client.sequence = 1 }
	client.packet = text_copy_request(client.sequence, text)
	client.status = .pending
	return true
}

// Transfer the packet's storage to the IPC caller, which frees it after use.
fn (mut client TextCopyClient) take_request() []u8 {
	if client.packet.len == 0 { return []u8{} }
	packet := client.packet
	client.packet = []u8{}
	client.waiting = true
	return packet
}

// True means this is a valid acknowledgement of the current request; the
// resulting status distinguishes successful copies from rejected copies.
fn (mut client TextCopyClient) receive_reply(payload string) bool {
	if !client.waiting || payload.len != text_copy_reply_size
		|| color_meter_read_u32(payload, 0) != text_copy_magic
		|| color_meter_read_u32(payload, 4) != client.sequence
		|| color_meter_read_u32(payload, 8) > 1 { return false }
	client.waiting = false
	client.status = if color_meter_read_u32(payload, 8) == 1 { .copied } else { .failed }
	return true
}

fn (client &TextCopyClient) status_key() string {
	return match client.status {
		.idle { '' }
		.pending { 'clipboard.copy.pending' }
		.copied { 'clipboard.copy.copied' }
		.unavailable { 'clipboard.copy.unavailable' }
		.too_large { 'clipboard.copy.too_large' }
		.empty { 'clipboard.copy.empty' }
		.failed { 'clipboard.copy.failed' }
	}
}

fn (mut client TextCopyClient) clear_status() {
	if client.status != .pending { client.status = .idle }
}

fn (mut client TextCopyClient) close() {
	client.release_packet()
	client.waiting = false
	client.status = .idle
}
