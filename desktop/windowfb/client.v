// SPDX-License-Identifier: MIT
module windowfb

pub struct Window {
pub mut:
	connection    &Connection = unsafe { nil }
	surface       Surface
	frame_pending bool
	generation    int
	pending_generation int
}

pub fn open(title string, width int, height int) !Window {
	path := socket_path()
	defer { unsafe { path.free() } }
	return open_at(path, title, width, height)
}

pub fn open_at(path string, title string, width int, height int) !Window {
	_ = surface_size(width, height)!
	if title.len == 0 || title.len > 128 { return error('window title must contain 1..128 bytes') }
	mut c := connect(path)!
	mut accepted := false
	defer { if !accepted {
		c.close()
		unsafe { free(c) }
	} }
	request := message(.create, width, height, client_features, title)!
	c.send(unsafe { &request })!
	mut reply := Message{}
	for !c.receive(unsafe { &reply })! {
		if !c.wait(5000)! { return error('window creation timed out') }
	}
	if reply.kind != .created || reply.x != width || reply.y != height || reply.value != width * 4 {
		return error('invalid window creation reply')
	}
	surface := open_surface(reply.text(), width, height)!
	accepted = true
	return Window{ connection: c, surface: surface }
}

// Send after drawing into surface.back, then wait for FRAME_DONE before drawing
// the next frame. The acknowledgement means copied, not displayed/vsynced.
pub fn (mut w Window) present() ! {
	if w.frame_pending { return error('wait for frame_done before drawing again') }
	m := message(.present, 0, 0, w.generation, '')!
	w.connection.send(unsafe { &m })!
	w.frame_pending = true
	w.pending_generation = w.generation
}

pub fn (mut w Window) receive(m &Message) !bool {
	if !w.connection.receive(m)! { return false }
	if m.kind == .configure && m.length > 0 {
		if m.value <= w.generation { return error('invalid buffer generation') }
		mut replacement := open_surface(m.text(), int(m.x), int(m.y))!
		ack := message(.buffer_ack, 0, 0, int(m.value), '')!
		w.connection.send(unsafe { &ack }) or {
			replacement.close()
			return err
		}
		w.surface.close()
		w.surface = replacement
		w.generation = int(m.value)
	}
	if m.kind == .frame_done {
		if !w.frame_pending || m.value != w.pending_generation { return error('unexpected frame acknowledgement') }
		w.frame_pending = false
	}
	return true
}

pub fn (mut w Window) set_title(title string) ! {
	if title.len == 0 || title.len > 128 { return error('window title must contain 1..128 bytes') }
	for byte in title { if byte < 32 || byte == 127 { return error('invalid window title') } }
	m := message(.set_title, 0, 0, 0, title)!
	w.connection.send(unsafe { &m })!
}

pub fn (w &Window) event_fd() int { return w.connection.fd }

pub fn (mut w Window) close() {
	w.surface.close()
	if w.connection != unsafe { nil } {
		w.connection.close()
		unsafe { free(w.connection) }
		w.connection = unsafe { nil }
	}
}
