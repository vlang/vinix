// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.windowfb
import os

fn fb_test_server(directory string) !FramebufferServer {
	os.mkdir_all(directory)!
	return FramebufferServer{ listener: windowfb.listen(directory + '/windows')!, directory: directory.clone() }
}

fn fb_test_client(mut desktop Desktop, mut server FramebufferServer) !&windowfb.Connection {
	mut client := windowfb.connect(server.directory + '/windows')!
	request := windowfb.message(.create, 320, 240, 0, 'Raw pixels')!
	client.send(unsafe { &request })!
	started := desktop_monotonic_ms()
	desktop.wait_framebuffer_input(&server, -1, -1, 1000)
	assert desktop_monotonic_ms() - started < 500
	desktop.poll_framebuffer_server(mut server)
	return client
}

fn test_framebuffer_window_publication_input_resize_and_cleanup() {
	directory := os.join_path(os.temp_dir(), 'vinix-fb-window-${os.getpid()}')
	mut server := fb_test_server(directory)!
	mut desktop := Desktop{ canvas: new_canvas(800, 600) }
	defer {
		desktop.close_apps()
		server.close()
		os.rmdir_all(directory) or {}
		unsafe {
			directory.free()
			free(desktop.canvas.pixels)
		}
	}
	mut client := fb_test_client(mut desktop, mut server)!
	defer {
		client.close()
		unsafe { free(client) }
	}
	mut event := windowfb.Message{}
	assert client.receive(unsafe { &event })!
	assert event.kind == .created && event.x == 320 && event.y == 240 && event.value == 1280
	path := event.text().clone()
	defer { unsafe { path.free() } }
	mut mapping := windowfb.open_surface(path, 320, 240)!
	defer { mapping.close() }
	assert client.receive(unsafe { &event })! && event.kind == .configure
	assert client.receive(unsafe { &event })! && event.kind == .focus && event.value == 1
	assert desktop.windows.len == 1
	unsafe {
		mapping.back[0] = 0x123456
		mapping.back[320 * 240 - 1] = 0xabcdef
	}
	request := windowfb.message(.present, 0, 0, 0, '')!
	client.send(unsafe { &request })!
	desktop.poll_framebuffer_server(mut server)
	assert client.receive(unsafe { &event })! && event.kind == .frame_done
	surface := open_vinix_surface(path) or { panic('missing published surface') }
	assert surface.pixel(0, 0) == 0x123456 && surface.pixel(319, 239) == 0xabcdef
	surface.close()
	mut app := desktop.apps[desktop.windows[0].app_index]
	if mut app is FramebufferApp {
		app.pointer_event(.down, .right, 0, 160, 120, 320, 240)
		app.pointer_event(.horizontal_scroll, .no_button, -2, 160, 120, 320, 240)
		app.key_input('\x1b[A')
	}
	assert client.receive(unsafe { &event })! && event.kind == .button_down && event.x == 160 && event.y == 120 && event.value == 3
	assert client.receive(unsafe { &event })! && event.kind == .horizontal_wheel && event.value == -2
	assert client.receive(unsafe { &event })! && event.kind == .keys && event.text() == '\x1b[A'
	desktop.windows[0].width += 100
	desktop.focus = 0
	desktop.poll_framebuffer_server(mut server)
	assert client.receive(unsafe { &event })! && event.kind == .configure && event.x == 420
	assert client.receive(unsafe { &event })! && event.kind == .focus && event.value == 0
	desktop.close_window(desktop.windows[0].id)
	assert client.receive(unsafe { &event })! && event.kind == .close
	assert desktop.windows.len == 0 && !os.exists(path)
	assert desktop.apps.len == 1
	// Closed slots and their interface boxes are reused across client churn.
	for _ in 0 .. 20 {
		mut next := fb_test_client(mut desktop, mut server)!
		assert desktop.apps.len == 1 && desktop.windows.len == 1
		next.close()
		unsafe { free(next) }
		desktop.poll_framebuffer_server(mut server)
		assert desktop.windows.len == 0
	}
}

fn test_incomplete_or_invalid_handshake_does_not_block_compositor() {
	directory := os.join_path(os.temp_dir(), 'vinix-fb-bad-${os.getpid()}')
	mut server := fb_test_server(directory)!
	mut desktop := Desktop{ canvas: Canvas{ width: 800, height: 600 } }
	defer {
		desktop.close_apps()
		server.close()
		os.rmdir_all(directory) or {}
		unsafe { directory.free() }
	}
	mut stalled := windowfb.connect(directory + '/windows')!
	defer {
		stalled.close()
		unsafe { free(stalled) }
	}
	desktop.poll_framebuffer_server(mut server)
	assert desktop.windows.len == 0 && server.pending[0] != unsafe { nil }
	mut valid := fb_test_client(mut desktop, mut server)!
	defer {
		valid.close()
		unsafe { free(valid) }
	}
	assert desktop.windows.len == 1
	server.deadlines[0] = 0
	desktop.poll_framebuffer_server(mut server)
	assert server.pending[0] == unsafe { nil }
	mut invalid := windowfb.connect(directory + '/windows')!
	defer {
		invalid.close()
		unsafe { free(invalid) }
	}
	request := windowfb.message(.create, 8192, 8192, 0, 'Too big')!
	invalid.send(unsafe { &request })!
	desktop.poll_framebuffer_server(mut server)
	assert desktop.windows.len == 1
	bad := windowfb.message(.keys, 0, 0, 0, 'client cannot inject input')!
	valid.send(unsafe { &bad })!
	desktop.poll_framebuffer_server(mut server)
	assert desktop.windows.len == 0
}
