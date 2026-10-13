// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.windowfb
import os

fn C.socketpair(i32, i32, i32, &i32) i32

fn fb_test_server(directory string) !FramebufferServer {
	os.mkdir_all(directory)!
	return FramebufferServer{ listener: windowfb.listen(directory + '/windows')!, directory: directory.clone(), key_events: true }
}

fn fb_test_client_features(mut desktop Desktop, mut server FramebufferServer, features int) !&windowfb.Connection {
	mut client := windowfb.connect(server.directory + '/windows')!
	request := windowfb.message(.create, 320, 240, features, 'Raw pixels')!
	client.send(unsafe { &request })!
	started := desktop_monotonic_ms()
	desktop.wait_framebuffer_input(&server, -1, -1, 1000)
	assert desktop_monotonic_ms() - started < 500
	desktop.poll_framebuffer_server(mut server)
	return client
}

fn fb_test_client(mut desktop Desktop, mut server FramebufferServer) !&windowfb.Connection {
	return fb_test_client_features(mut desktop, mut server, 0)
}

fn test_resize_handoff_with_pending_frame_coalescing_and_title() {
	directory := os.join_path(os.temp_dir(), 'vinix-fb-resize-${os.getpid()}')
	mut server := fb_test_server(directory)!
	mut desktop := Desktop{ canvas: new_canvas(800, 600) }
	defer {
		desktop.close_apps(); server.close(); os.rmdir_all(directory) or {}
		unsafe { directory.free(); free(desktop.canvas.pixels) }
	}
	client := fb_test_client_features(mut desktop, mut server, windowfb.client_features)!
	mut event := windowfb.Message{}
	assert client.receive(unsafe { &event })! && event.kind == .created
	old_path := event.text().clone()
	defer { unsafe { old_path.free() } }
	mut window := windowfb.Window{ connection: client, surface: windowfb.open_surface(old_path, 320, 240)! }
	defer { window.close() }
	assert window.receive(unsafe { &event })! && event.kind == .configure && event.length == 0
	assert window.receive(unsafe { &event })! && event.kind == .focus
	window.set_title('Ardent terminal')!
	unsafe { window.surface.back[0] = 0x123456 }
	window.present()!
	desktop.windows[0].width += 100
	desktop.poll_framebuffer_server(mut server)
	assert desktop.windows[0].title == 'Ardent terminal'
	assert window.receive(unsafe { &event })! && event.kind == .configure && event.x == 420 && event.value == 1
	first_path := event.text().clone()
	defer { unsafe { first_path.free() } }
	assert window.surface.width == 420 && window.surface.stride == 1680 && window.frame_pending
	assert os.exists(old_path) && os.exists(first_path)
	assert window.receive(unsafe { &event })! && event.kind == .frame_done && event.value == 0 && !window.frame_pending
	// While the offer is outstanding, repeated resizes don't allocate offers.
	desktop.windows[0].width += 100
	desktop.poll_framebuffer_server(mut server)
	assert !os.exists(old_path)
	assert !window.receive(unsafe { &event })!
	desktop.poll_framebuffer_server(mut server)
	assert window.receive(unsafe { &event })! && event.kind == .configure && event.x == 520 && event.value == 2
	second_path := event.text().clone()
	defer { unsafe { second_path.free() } }
	assert window.surface.width == 520
	unsafe { window.surface.back[520 * 240 - 1] = 0xabcdef }
	window.present()!
	desktop.poll_framebuffer_server(mut server)
	assert !os.exists(first_path)
	assert window.receive(unsafe { &event })! && event.kind == .frame_done && event.value == 2
	surface := open_vinix_surface(second_path) or { panic('missing resized surface') }
	assert surface.pixel(519, 239) == 0xabcdef
	surface.close()
	// Disconnect during a third unacknowledged replacement frees both files.
	desktop.windows[0].width += 10
	desktop.poll_framebuffer_server(mut server)
	assert client.receive(unsafe { &event })! && event.kind == .configure && event.value == 3
	third_path := event.text().clone()
	defer { unsafe { third_path.free() } }
	window.close()
	desktop.poll_framebuffer_server(mut server)
	assert !os.exists(second_path) && !os.exists(third_path) && desktop.windows.len == 0
}

fn test_kitty_keyboard_encoding_and_modifier_state() {
	assert kitty_key(23, 4, 1, .us, '\t').text() == '\x1b[105;5:1u' // Ctrl-I
	assert kitty_key(15, 0, 1, .us, '\t').text() == '\x1b[9;1:1u' // Tab
	assert kitty_key(1, 0, 0, .us, '').text() == '\x1b[27;1:3u'
	assert kitty_key(19, 5, 1, .us, '').text() == '\x1b[114:82;6:1u' // Ctrl-Shift-R
	assert kitty_key(30, 0, 2, .us, 'a').text() == '\x1b[97;1:2;97u'
	assert kitty_key(30, 1, 1, .us, 'A').text() == '\x1b[97:65;2:1;65u'
	assert kitty_key(30, 64, 1, .us, 'A').text() == '\x1b[97;65:1;65u'
	assert kitty_key(46, 4, 1, .russian, '').text() == '\x1b[1089::99;5:1u'
	assert kitty_key(18, 0, 1, .us, 'é🙂').text() == '\x1b[101;1:1;233:128578u'
	assert kitty_key(103, 5, 0, .us, '').text() == '\x1b[1;6:3A'
	assert kitty_key(79, 128, 1, .us, '1').text() == '\x1b[57400;129:1;49u'
	assert kitty_key(79, 0, 1, .us, '').text() == '\x1b[57424;1:1u'
	assert kitty_key(18, 0, 1, .us, '\xc2\x85').text() == '\x1b[101;1:1u' // no C1 text
	mut keyboard := Keyboard{}
	keyboard.held[29] = true; keyboard.held[97] = true
	keyboard.held[29] = false
	assert keyboard.modifiers() == 4
	assert kitty_key(29, keyboard.modifiers(), 0, .us, '').text() == '\x1b[57442;5:3u'
	keyboard.held[97] = false
	assert keyboard.modifiers() == 0
	packet := '\x1b[?224;1h'
	key, value := physical_packet(packet.str, packet.len)
	assert key == 29 && value == 1
}

fn test_physical_press_repeat_release_reaches_only_its_window() {
	directory := os.join_path(os.temp_dir(), 'vinix-fb-keys-${os.getpid()}')
	mut server := fb_test_server(directory)!
	mut desktop := Desktop{ canvas: new_canvas(800, 600) }
	defer {
		desktop.close_apps(); server.close(); os.rmdir_all(directory) or {}
		unsafe { directory.free(); free(desktop.canvas.pixels) }
	}
	mut client := fb_test_client_features(mut desktop, mut server, windowfb.client_features)!
	defer { client.close(); unsafe { free(client) } }
	mut event := windowfb.Message{}
	for client.receive(unsafe { &event })! {}
	mut keyboard := Keyboard{ fd: -1 }
	desktop.pump_physical_key(mut keyboard, 23, 1)
	desktop.pump_physical_key(mut keyboard, 23, 2)
	desktop.pump_physical_key(mut keyboard, 23, 0)
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[105;1:1;105u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[105;1:2;105u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[105;1:3u'
	desktop.pump_physical_key(mut keyboard, 29, 1)
	desktop.pump_physical_key(mut keyboard, 23, 1)
	desktop.focus = 0
	desktop.pump_physical_key(mut keyboard, 23, 0)
	desktop.pump_physical_key(mut keyboard, 29, 0)
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[57442;5:1u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[105;5:1u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[105;5:3u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[57442;1:3u'
	desktop.focus = desktop.windows[0].id
	desktop.pump_physical_key(mut keyboard, 56, 1)
	desktop.pump_physical_key(mut keyboard, 26, 1)
	desktop.pump_physical_key(mut keyboard, 26, 0)
	desktop.pump_physical_key(mut keyboard, 56, 0)
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[57443;3:1u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[91;3:1;91u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[91;3:3u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[57443;1:3u'
	// A physical packet split across terminal reads must retain its identity.
	mut pair := [2]i32{}
	assert C.socketpair(C.AF_UNIX, C.SOCK_STREAM, 0, unsafe { &pair[0] }) == 0
	mut input := windowfb.adopt(int(pair[0]))!
	defer { input.close(); desktop_close(int(pair[1])); unsafe { free(input) } }
	keyboard.fd = input.fd
	keyboard.key_events = true
	packet := '\x1b[?23;1k\x1b[?23;0k'
	for i in 0 .. packet.len {
		assert unsafe { C.write(int(pair[1]), packet.str + i, 1) } == 1
		desktop.pump_keyboard(mut keyboard)
	}
	assert keyboard.packet_used == 0 && !keyboard.held[23]
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[105;1:1;105u'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[105;1:3u'
	// Fn-Left is Home even if Fn is let go before the arrow is released.
	desktop.pump_physical_key(mut keyboard, 255, 1)
	desktop.pump_physical_key(mut keyboard, 105, 1)
	desktop.pump_physical_key(mut keyboard, 255, 0)
	desktop.pump_physical_key(mut keyboard, 105, 0)
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[1;1:1H'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[1;1:3H'
	mut app := desktop.apps[desktop.windows[0].app_index]
	if mut app is FramebufferApp { app.key_input('é🙂') }
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[0;1:1;233:128578u'
	desktop.pump_physical_key(mut keyboard, 59, 1)
	desktop.pump_physical_key(mut keyboard, 59, 0)
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[1;1:1P'
	assert client.receive(unsafe { &event })! && event.text() == '\x1b[1;1:3P'
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
