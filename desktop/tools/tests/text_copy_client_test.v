// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_text_copy_client_snapshots_raw_bytes_and_requires_matching_acknowledgement() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	mut client := TextCopyClient{}
	defer { client.close() }
	mut source := 'café\n\x00\x1b'.bytes()
	defer { unsafe { source.free() } }
	assert client.queue(editor_bytes_text(source))
	assert client.status_key() == 'clipboard.copy.pending'
	source[0] = `X`
	packet := client.take_request()
	defer { unsafe { packet.free() } }
	assert packet.len == text_copy_header_size + source.len
	assert color_meter_read_u32(editor_bytes_text(packet), 8) == u32(source.len)
	assert console_borrow(editor_bytes_text(packet), text_copy_header_size, packet.len) == 'café\n\x00\x1b'
	assert client.packet.len == 0 && client.waiting
	assert client.take_request().len == 0
	assert !client.receive_reply('short')
	assert client.waiting
	ack := text_copy_reply(client.sequence, true)
	defer { unsafe { ack.free() } }
	assert client.receive_reply(editor_bytes_text(ack))
	assert client.status_key() == 'clipboard.copy.copied'
	assert !client.receive_reply(editor_bytes_text(ack))
	client.clear_status()
	assert client.status_key() == ''
}

fn test_text_copy_client_replacement_rejection_and_stale_or_malformed_replies() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	mut client := TextCopyClient{}
	defer { client.close() }
	assert client.queue('older')
	old_sequence := client.sequence
	old_packet := client.take_request()
	defer { unsafe { old_packet.free() } }
	assert client.queue('newer')
	assert client.sequence != old_sequence
	packet := client.take_request()
	defer { unsafe { packet.free() } }
	old_ack := text_copy_reply(old_sequence, true)
	defer { unsafe { old_ack.free() } }
	assert !client.receive_reply(editor_bytes_text(old_ack))
	assert client.status == .pending
	mut ack := text_copy_reply(client.sequence, true)
	defer { unsafe { ack.free() } }
	ack[0] ^= 1
	assert !client.receive_reply(editor_bytes_text(ack))
	ack[0] ^= 1
	ack[8] = 2
	assert !client.receive_reply(editor_bytes_text(ack))
	ack[8] = 0
	assert client.receive_reply(editor_bytes_text(ack))
	assert client.status_key() == 'clipboard.copy.failed'
	assert client.queue('pending')
	assert !client.queue('')
	assert client.packet.len == 0 && !client.waiting
	assert client.status_key() == 'clipboard.copy.empty'
	assert client.queue('before close')
	before_close := client.sequence
	last_packet := client.take_request()
	defer { unsafe { last_packet.free() } }
	client.close()
	assert client.queue('after close')
	assert client.sequence != before_close
	new_packet := client.take_request()
	defer { unsafe { new_packet.free() } }
	late_ack := text_copy_reply(before_close, true)
	defer { unsafe { late_ack.free() } }
	assert !client.receive_reply(editor_bytes_text(late_ack))
}

fn test_text_copy_client_bounds_capability_and_sequence_wrap() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	mut client := TextCopyClient{sequence: u32(0xffffffff)}
	defer { client.close() }
	text := 'x'.repeat(clipboard_max_bytes)
	oversized := 'x'.repeat(clipboard_max_bytes + 1)
	defer { unsafe { text.free(); oversized.free() } }
	assert client.queue(text)
	assert client.sequence == 1
	assert client.packet.len == clipboard_max_bytes + text_copy_header_size
	assert !client.queue(oversized)
	assert client.status_key() == 'clipboard.copy.too_large'
	assert client.packet.len == 0
	app_compositor_features = app_features & ~app_feature_text_copy
	assert !client.queue('valid')
	assert client.status_key() == 'clipboard.copy.unavailable'
	client.close()
	client.close()
	assert client.packet.cap == 0 && !client.waiting && client.status == .idle
}

fn test_text_copy_client_factory_permissions_are_limited_to_text_clients() {
	for name in ['vinix-terminal', 'vinix-calculator', 'vinix-dictionary', 'vinix-editor']! {
		factory := app_factory_named(name) or { panic(name) }
		assert factory.clipboard_copy && !factory.desktop_services
	}
	terminal := app_factory_named('vinix-terminal') or { panic('terminal missing') }
	assert terminal.pointer && terminal.keyboard && terminal.polling
	preview := app_factory_named('vinix-preview') or { panic('preview missing') }
	assert !preview.clipboard_copy
}
