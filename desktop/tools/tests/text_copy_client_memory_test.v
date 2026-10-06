// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include "@VMODROOT/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_text_copy_client_repeated_transfer_replace_ack_and_cleanup_keep_zero_bytes() {
	saved := app_compositor_features
	app_compositor_features = app_features
	defer { app_compositor_features = saved }
	text := 'café\n'.repeat(512)
	defer { unsafe { text.free() } }
	C.vinix_heap_begin()
	mut client := TextCopyClient{}
	for index in 0 .. 300 {
		assert client.queue('undispatched')
		assert client.queue(text)
		packet := client.take_request()
		assert packet.len == text.len + text_copy_header_size
		assert client.packet.cap == 0
		ack := text_copy_reply(client.sequence, index % 2 == 0)
		assert client.receive_reply(editor_bytes_text(ack))
		assert client.status == if index % 2 == 0 { TextCopyStatus.copied } else { TextCopyStatus.failed }
		unsafe { packet.free(); ack.free() }
		client.clear_status()
		assert client.queue('cancel on close')
		client.close()
		client.close()
	}
	assert C.vinix_heap_end() == 0
}

fn test_text_copy_client_denied_and_large_requests_and_abandoned_transfers_release_memory() {
	saved := app_compositor_features
	defer { app_compositor_features = saved }
	maximum := 'x'.repeat(clipboard_max_bytes)
	oversized := 'x'.repeat(clipboard_max_bytes + 1)
	defer { unsafe { maximum.free(); oversized.free() } }
	C.vinix_heap_begin()
	for _ in 0 .. 100 {
		mut client := TextCopyClient{}
		app_compositor_features = app_features
		assert client.queue(maximum)
		assert !client.queue(oversized)
		assert client.queue('frozen')
		packet := client.take_request()
		client.close()
		unsafe { packet.free() }
		app_compositor_features = 0
		assert !client.queue('unsupported')
		client.close()
	}
	assert C.vinix_heap_end() == 0
}
