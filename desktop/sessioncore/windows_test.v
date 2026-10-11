// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

fn fixture() Windows {
	mut s := Windows{}
	s.update_displays([Display{ id: text('panel') or { panic(err) }, area: Rect{ w: 1200, h: 800 }, primary: true }]) or { panic(err) }
	for i in 0 .. 3 {
		s.windows[i] = Placement{ app: text('vinix-editor') or { panic(err) }, instance: i, display: text('panel') or { panic(err) }, frame: Rect{10, 20, 500, 300}, restore: Rect{10, 20, 500, 300} }
	}
	s.count = 3
	return s
}

fn test_workspace_resize_moves_windows_and_groups() {
	mut s := fixture()
	s.configure(12) or { panic(err) }
	s.rename(11, 'Work\tResearch') or { panic(err) }
	s.windows[0].group = 2
	s.windows[1].group = 2
	s.move(0, 11, true) or { panic(err) }
	assert s.windows[0].workspace == 11 && s.windows[1].workspace == 11
	assert s.windows[2].workspace == 0
	s.active = 11
	s.configure(2) or { panic(err) }
	assert s.active == 1 && s.windows[0].workspace == 1
	if _ := s.configure(17) {
		assert false
	}
}

fn test_layout_is_coordinated_and_crowding_is_atomic() {
	mut s := fixture()
	s.set_layout(0, .columns, 8) or { panic(err) }
	assert s.windows[0].frame.x == 8
	assert s.windows[1].frame.x >= s.windows[0].frame.x + s.windows[0].frame.w + 8
	assert s.windows[2].frame.x + s.windows[2].frame.w == 1192
	before := s.windows
	s.displays[0].area.w = 200
	s.arrange(0)
	assert s.windows == before
}

fn test_display_disconnect_recovers_every_window_including_minimized() {
	mut s := fixture()
	s.windows[0].frame.x = 1800
	s.windows[1].minimized = true
	s.windows[1].frame.y = -900
	s.windows[2].maximized = true
	s.update_displays([Display{ id: text('external') or { panic(err) }, area: Rect{ w: 640, h: 480 }, primary: true }]) or { panic(err) }
	for i in 0 .. s.count {
		assert s.windows[i].frame.x >= 0 && s.windows[i].frame.y >= 0
		assert s.windows[i].frame.x + s.windows[i].frame.w <= 640
		assert s.windows[i].frame.y + s.windows[i].frame.h <= 480
		assert s.windows[i].display.str() == 'panel'
	}
	assert s.windows[2].frame == Rect{ w: 640, h: 480 }
}

fn test_roundtrip_rejects_corruption_and_duplicate_instances() {
	mut s := fixture()
	s.rename(0, 'Development') or { panic(err) }
	s.windows[1].failed = true
	record := s.encode()
	defer { unsafe { record.free() } }
	loaded := decode_windows(record) or { panic(err) }
	assert loaded.count == 3 && loaded.windows[1].failed
	assert loaded.workspaces[0].name.str() == 'Development'
	if _ := decode_windows(record.replace('workspace\t1', 'workspace\t0')) {
		assert false
	}
	if _ := decode_windows(record[..record.len / 2]) {
		assert false
	}
	if _ := number('9223372036854775808', 0, 100) {
		assert false
	}
}
