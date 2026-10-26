// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time
import desktop.windowfb

fn open_window(path string, width int, height int, lifetime int) !windowfb.Window {
	deadline := time.sys_mono_now() + 5 * time.second
	mut connection := connect_window(path, lifetime, deadline)!
	return create_window_before(connection, width, height, lifetime, deadline) or {
		connection.close()
		unsafe { free(connection) }
		return err
	}
}

fn create_window(connection &windowfb.Connection, width int, height int, lifetime int) !windowfb.Window {
	return create_window_before(connection, width, height, lifetime, time.sys_mono_now() + 5 * time.second)
}

fn create_window_before(connection &windowfb.Connection, width int, height int, lifetime int, deadline i64) !windowfb.Window {
	mut c := unsafe { connection }
	// Feature 0 gives a fixed framebuffer, coordinates scaled by the desktop,
	// and ordinary UTF-8/escape-sequence keys matching the existing WsEvent ABI.
	request := windowfb.message(.create, width, height, 0, 'Google account')!
	c.send(unsafe { &request })!
	mut reply := windowfb.Message{}
	for !c.receive(unsafe { &reply })! {
		if !lifetime_alive(lifetime)! { return error('account UI request expired') }
		if time.sys_mono_now() >= deadline { return error('account UI window creation timed out') }
		c.wait(16)!
	}
	if reply.kind != .created || reply.x != width || reply.y != height || reply.value != width * 4 {
		return error('invalid account UI window creation reply')
	}
	surface := windowfb.open_surface(reply.text(), width, height)!
	return windowfb.Window{ connection: c, surface: surface }
}

fn bridge_tick(mut window windowfb.Window, source &Source, mut input InputQueue, input_fd int) !bool {
	window.connection.flush()!
	input.flush(input_fd)!
	event := unsafe { &input.event }
	for _ in 0 .. 64 {
		if !window.connection.receive(event)! { break }
		if event.kind == .close { return false }
		// A replacement buffer was never negotiated. Reject it before accepting
		// any changed geometry into the source-copy path.
		if event.kind == .configure && event.length != 0 {
			return error('unexpected account UI buffer replacement')
		}
		if event.kind == .frame_done {
			if !window.frame_pending || event.value != window.pending_generation || event.length != 0 {
				return error('unexpected account UI frame acknowledgement')
			}
			window.frame_pending = false
		}
		input.enqueue(event, source.width, source.height)!
		unsafe { C.memset(&event.payload[0], 0, usize(windowfb.max_payload)) }
		input.flush(input_fd)!
	}
	if !window.frame_pending && source.copy_to(&window.surface)! { window.present()! }
	return true
}
