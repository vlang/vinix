// SPDX-License-Identifier: GPL-2.0-or-later
module pointer

// Fixed-width /dev/pointer snapshot ABI, matching the shared Vinix desktop.
pub struct Packet {
pub mut:
	x i32
	y i32
	max_x i32
	max_y i32
	buttons u32
	pressed u32
	released u32
	scroll i32
	scroll_x i32
}

pub struct State {
pub mut:
	packet Packet
	changed bool
}

pub fn (mut state State) attach(extent_width u32, extent_height u32) {
	if state.packet.max_x != 0 { return }
	w := if extent_width >= 2 && extent_width <= 16384 { extent_width } else { u32(1024) }
	h := if extent_height >= 2 && extent_height <= 16384 { extent_height } else { u32(768) }
	state.packet = Packet{x: i32(w / 2), y: i32(h / 2), max_x: i32(w - 1), max_y: i32(h - 1)}
	state.changed = true
}

pub fn (mut state State) move(dx i32, dy i32, buttons u32) {
	if state.packet.max_x == 0 { return }
	mut p := unsafe { &state.packet }
	old_x := p.x
	old_y := p.y
	p.x = if dx < -p.x { i32(0) } else if dx > p.max_x - p.x { p.max_x } else { p.x + dx }
	p.y = if dy < -p.y { i32(0) } else if dy > p.max_y - p.y { p.max_y } else { p.y + dy }
	current := buttons & 7
	state.changed = state.changed || p.x != old_x || p.y != old_y || current != p.buttons
	p.pressed |= current & ~p.buttons
	p.released |= p.buttons & ~current
	p.buttons = current
}

pub fn (mut state State) take() Packet {
	result := state.packet
	state.packet.pressed = 0
	state.packet.released = 0
	state.packet.scroll = 0
	state.packet.scroll_x = 0
	state.changed = false
	return result
}
