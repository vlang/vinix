// SPDX-License-Identifier: GPL-2.0-or-later
// Ordinary desktop windows for clients using only mmap and a Unix socket.
module main

import desktop.windowfb
import ui2

struct FramebufferServer {
mut:
	listener  windowfb.Listener
	pending   [windowfb.max_clients]&windowfb.Connection
	deadlines [windowfb.max_clients]u64
	directory string
	serial    u64
}

struct FramebufferApp {
mut:
	connection     &windowfb.Connection = unsafe { nil }
	surface        windowfb.Surface
	path           string
	image          string
	title          string
	closed         bool = true
	failed         bool
	content_width  int
	content_height int
	focused        int = -1
}

fn start_framebuffer_server() !FramebufferServer {
	directory := session_runtime_directory()
	mut accepted := false
	defer { if !accepted { unsafe { directory.free() } } }
	if !session_private_directory(directory) {
		return error('window runtime directory is unavailable')
	}
	path := windowfb.socket_path()
	defer { unsafe { path.free() } }
	listener := windowfb.listen(path)!
	accepted = true
	return FramebufferServer{ listener: listener, directory: directory }
}

fn (mut s FramebufferServer) drop_pending(slot int) {
	mut c := s.pending[slot]
	if c != unsafe { nil } {
		c.close()
		unsafe { free(c) }
	}
	s.pending[slot] = unsafe { nil }
}

fn (mut s FramebufferServer) close() {
	for slot in 0 .. s.pending.len { s.drop_pending(slot) }
	s.listener.close()
	unsafe { s.directory.free() }
	s.directory = ''
}

fn framebuffer_title_valid(title string) bool {
	if title.len == 0 || title.len > 128 { return false }
	for byte in title { if byte < 32 || byte == 127 { return false } }
	return true
}

fn (mut d Desktop) attach_framebuffer(mut s FramebufferServer, mut c windowfb.Connection, request &windowfb.Message) ! {
	if request.kind != .create || request.value != 0 || !framebuffer_title_valid(request.text()) {
		return error('invalid window creation request')
	}
	_ = windowfb.surface_size(int(request.x), int(request.y))!
	s.serial++
	pid_text := C.getpid().str()
	serial_text := s.serial.str()
	path := s.directory + '/framebuffer-' + pid_text + '-' + serial_text
	unsafe {
		pid_text.free()
		serial_text.free()
	}
	mut surface := windowfb.create_surface(path, int(request.x), int(request.y)) or {
		unsafe { path.free() }
		return err
	}
	mut accepted := false
	defer { if !accepted {
		surface.close()
		desktop_unlink(path)
		unsafe { path.free() }
	} }
	// Reuse retired app slots: repeated connect/disconnect must not retain a
	// socket buffer or interface box for each window ever created.
	mut slot := -1
	mut app := &FramebufferApp(unsafe { nil })
	for index in 0 .. d.apps.len {
		mut candidate := d.apps[index]
		if mut candidate is FramebufferApp {
			if !candidate.closed { continue }
			slot = index
			app = candidate
			break
		}
	}
	if app == unsafe { nil } { app = &FramebufferApp{} }
	app.connection = &c
	app.surface = surface
	app.path = path
	app.image = vinix_surface_image_prefix + path
	app.title = request.text().clone()
	app.closed = false
	app.failed = false
	app.content_width = 0
	app.content_height = 0
	app.focused = -1
	if slot < 0 {
		d.apps << app
		slot = d.apps.len - 1
	}
	step := ((d.next_id - 1) % 6) * 26
	id := d.spawn(app.title, .app, 120 + step, 60 + step, int(request.x) + 2 * d.theme().frame_border,
		int(request.y) + d.theme().title_height + d.theme().frame_border)
	index := d.window_index(id) or { return error('could not create desktop window') }
	d.windows[index].app_index = slot
	d.windows[index].icon = 'builtin:window'
	d.clamp_to_screen(index)
	accepted = true
	app.emit(.created, app.surface.width, app.surface.height, app.surface.stride, app.path)
}

fn (mut d Desktop) poll_framebuffer_server(mut s FramebufferServer) {
	if s.listener.fd < 0 { return }
	// Each pending handshake and each open window occupies one of 32 slots.
	mut live := 0
	for window in d.windows {
		if window.app_index >= 0 && d.apps[window.app_index] is FramebufferApp { live++ }
	}
	for pending in s.pending { if pending != unsafe { nil } { live++ } }
	for _ in 0 .. windowfb.max_clients {
		mut c := s.listener.accept() or { break }
		if live >= windowfb.max_clients {
			c.close()
			unsafe { free(c) }
			continue
		}
		peer := session_peer(c.fd) or {
			c.close()
			unsafe { free(c) }
			continue
		}
		_ = peer
		for slot in 0 .. s.pending.len {
			if s.pending[slot] == unsafe { nil } {
				s.pending[slot] = c
				s.deadlines[slot] = desktop_monotonic_ms() + 5000
				live++
				break
			}
		}
	}
	for slot in 0 .. s.pending.len {
		mut c := s.pending[slot]
		if c == unsafe { nil } { continue }
		if desktop_monotonic_ms() >= s.deadlines[slot] {
			s.drop_pending(slot)
			continue
		}
		mut request := windowfb.Message{}
		ready := c.receive(unsafe { &request }) or {
			unsafe { err.free() }
			s.drop_pending(slot)
			continue
		}
		if !ready { continue }
		d.attach_framebuffer(mut s, mut c, unsafe { &request }) or {
			unsafe { err.free() }
			s.drop_pending(slot)
			continue
		}
		// The app now owns this connection.
		s.pending[slot] = unsafe { nil }
	}
	mut index := 0
	for index < d.windows.len {
		slot := d.windows[index].app_index
		if slot < 0 {
			index++
			continue
		}
		mut app := d.apps[slot]
		if mut app is FramebufferApp {
			app.sync_window(d.windows[index], d)
			app.connection.flush() or {
				unsafe { err.free() }
				app.failed = true
			}
			// Bound work per pass, including a client flooding PRESENT commands.
			for _ in 0 .. 8 {
				if app.failed { break }
				mut request := windowfb.Message{}
				ready := app.connection.receive(unsafe { &request }) or {
					unsafe { err.free() }
					app.failed = true
					break
				}
				if !ready { break }
				if request.kind == .close && request.length == 0 {
					app.failed = true
					break
				}
				if request.kind != .present || request.length != 0 || request.x != 0 || request.y != 0 || request.value != 0 {
					app.failed = true
					break
				}
				app.surface.copy_frame()
				app.emit(.frame_done, 0, 0, 0, '')
				d.damage_window(index)
			}
			if app.failed {
				d.close_window(d.windows[index].id)
				continue
			}
		}
		index++
	}
}

fn (mut app FramebufferApp) emit(kind windowfb.Kind, x int, y int, value int, text string) {
	if app.closed || app.failed { return }
	m := windowfb.message(kind, x, y, value, text) or {
		unsafe { err.free() }
		app.failed = true
		return
	}
	app.connection.send(unsafe { &m }) or {
		unsafe { err.free() }
		app.failed = true
	}
}

fn (mut app FramebufferApp) sync_window(w Window, d &Desktop) {
	border := d.window_border(&w)
	width := w.width - 2 * border
	height := w.height - d.theme().title_height - border
	if width != app.content_width || height != app.content_height {
		app.content_width = width
		app.content_height = height
		app.emit(.configure, width, height, 0, '')
	}
	focused := if w.id == d.focus && !w.minimized && w.workspace == d.current_workspace {
		1
	} else {
		0
	}
	if focused != app.focused {
		app.focused = focused
		app.emit(.focus, 0, 0, focused, '')
	}
}

fn (mut app FramebufferApp) build(size ui2.Rect) !ui2.Element {
	return ui2.screen(0, [ui2.image('', app.image, size)])
}

fn (mut app FramebufferApp) handle(_ string) ! {}

fn (mut app FramebufferApp) key_input(text string) { app.emit(.keys, 0, 0, 0, text) }

fn (mut app FramebufferApp) pointer_input_enabled() bool { return !app.closed && !app.failed }

fn (mut app FramebufferApp) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int) {
	if width <= 0 || height <= 0 { return }
	kind := match phase {
		.move { windowfb.Kind.motion }
		.down { windowfb.Kind.button_down }
		.up { windowfb.Kind.button_up }
		.scroll { windowfb.Kind.wheel }
		.horizontal_scroll { windowfb.Kind.horizontal_wheel }
	}
	value := if phase in [.scroll, .horizontal_scroll] { scroll } else { int(button) }
	app.emit(kind, x * app.surface.width / width, y * app.surface.height / height, value, '')
}

fn (mut app FramebufferApp) close() {
	if app.closed { return }
	app.emit(.close, 0, 0, 0, '')
	app.closed = true
	app.connection.close()
	unsafe { free(app.connection) }
	app.connection = unsafe { nil }
	app.surface.close()
	desktop_unlink(app.path)
	unsafe {
		app.path.free()
		app.image.free()
		app.title.free()
	}
	app.path = ''
	app.image = ''
	app.title = ''
}

// Add the listener, pending handshakes and client sockets to the compositor's
// idle poll. Frame publication therefore wakes an otherwise idle desktop.
fn (d &Desktop) wait_framebuffer_input(s &FramebufferServer, pointer_fd int, keyboard_fd int, milliseconds i64) {
	if milliseconds <= 0 { return }
	mut fds := [windowfb.max_clients + 3]C.pollfd{}
	mut count := 0
	for fd in [pointer_fd, keyboard_fd, s.listener.fd]! {
		if fd >= 0 {
			fds[count] = C.pollfd{ fd: fd, events: C.POLLIN }
			count++
		}
	}
	for c in s.pending {
		if c != unsafe { nil } {
			fds[count] = C.pollfd{ fd: c.fd, events: C.POLLIN }
			count++
		}
	}
	for w in d.windows {
		if w.app_index < 0 { continue }
		app := d.apps[w.app_index]
		if app is FramebufferApp && !app.closed && count < fds.len {
			fds[count] = C.pollfd{ fd: app.connection.fd, events: i16(C.POLLIN | if app.connection.wants_write() {
				C.POLLOUT
			} else {
				0
			}) }
			count++
		}
	}
	timeout := if milliseconds > 1000 { 1000 } else { int(milliseconds) }
	C.poll(&fds[0], usize(count), timeout)
}
