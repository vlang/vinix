// SPDX-License-Identifier: GPL-2.0-or-later
module main

import desktop.sessioncore

fn open_desktop_outputs(primary_path string) !Framebuffer {
	mut fb := open_framebuffer(primary_path) or {
		mut fallback := Framebuffer{}
		for i in 0 .. 8 {
			path := '/dev/fb${i}'
			next := open_framebuffer(path) or {
				unsafe { path.free() }
				continue
			}
			fallback = next
			unsafe { path.free() }
			break
		}
		if fallback.fd < 0 { return err }
		fallback
	}
	for i in 0 .. 8 {
		path := '/dev/fb${i}'
		if path == fb.identity.str() {
			unsafe { path.free() }
			continue
		}
		mut next := open_framebuffer(path) or {
			unsafe { path.free() }
			continue
		}
		unsafe { path.free() }
		if fb.extra_count == 7 || fb.virtual_width() + next.width > 16384 || u64(fb.virtual_width() + next.width) * u64(if next.height > fb.virtual_height() {
			next.height
		} else {
			fb.virtual_height()
		}) > 64 * 1024 * 1024 {
			next.close()
			continue
		}
		fb.extra[fb.extra_count] = &Framebuffer{ ...next }
		fb.extra_count++
	}
	mut x := fb.width
	height := fb.virtual_height()
	fb.origin_y = height - fb.height
	for i in 0 .. fb.extra_count {
		fb.extra[i].origin_x = x
		fb.extra[i].origin_y = height - fb.extra[i].height
		x += fb.extra[i].width
	}
	return fb
}

fn (fb &Framebuffer) virtual_width() int {
	mut width := fb.width
	for i in 0 .. fb.extra_count { width += fb.extra[i].width }
	return width
}

fn (fb &Framebuffer) virtual_height() int {
	mut height := fb.height
	for i in 0 .. fb.extra_count { if fb.extra[i].height > height { height = fb.extra[i].height } }
	return height
}

fn (fb &Framebuffer) output_geometry_changed() bool {
	if fb.fd < 0 { return true }
	mut geometry := FBVarScreenInfo{}
	if desktop_ioctl(fb.fd, fbioget_vscreeninfo, &geometry) < 0 || int(geometry.xres) != fb.width || int(geometry.yres) != fb.height {
		return true
	}
	for i in 0 .. fb.extra_count {
		if desktop_ioctl(fb.extra[i].fd, fbioget_vscreeninfo, &geometry) < 0 || int(geometry.xres) != fb.extra[i].width || int(geometry.yres) != fb.extra[i].height {
			return true
		}
	}
	for i in 0 .. 8 {
		path := '/dev/fb${i}'
		exists := C.access(&char(path.str), C.F_OK) == 0
		mut known := path == fb.identity.str()
		for j in 0 .. fb.extra_count { if fb.extra[j].identity.str() == path { known = true } }
		unsafe { path.free() }
		if exists != known { return true }
	}
	return false
}

fn (fb &Framebuffer) present_viewport(canvas &Canvas) {
	if fb.fd < 0 || fb.base == unsafe { nil } { return }
	for y in 0 .. fb.height {
		if y + fb.origin_y >= canvas.physical_height { break }
		if fb.direct {
			unsafe { vmemcpy(&fb.base[y * fb.stride], &canvas.pixels[(y + fb.origin_y) * canvas.stride + fb.origin_x], usize(fb.width * 4)) }
		} else {
			for x in 0 .. fb.width {
				unsafe { fb.base[y * fb.stride + x] = fb.pack_pixel(canvas.pixels[(y + fb.origin_y) * canvas.stride + fb.origin_x + x]) }
			}
		}
	}
}

fn (mut d Desktop) configure_display_outputs(fb &Framebuffer) {
	d.session.output_count = 0
	scale := desktop_current_scale()
	d.session.outputs[0] = sessioncore.Display{ id: fb.identity, area: sessioncore.Rect{fb.origin_x / scale, fb.origin_y / scale, desktop_scaled_extent(fb.width, scale), desktop_usable_height(desktop_scaled_extent(fb.height, scale), d.taskbar_height())}, primary: true }
	d.session.output_count = 1
	for i in 0 .. fb.extra_count {
		next := fb.extra[i]
		d.session.outputs[i + 1] = sessioncore.Display{ id: next.identity, area: sessioncore.Rect{next.origin_x / scale, next.origin_y / scale, desktop_scaled_extent(next.width, scale), desktop_usable_height(desktop_scaled_extent(next.height, scale), d.taskbar_height())} }
		d.session.output_count++
	}
	d.shell_display_geometry()
}

fn (mut d Desktop) recover_display_outputs(fb &Framebuffer) {
	d.capture_shell_session()
	old := d.canvas.pixels
	desktop_physical_width = fb.virtual_width()
	desktop_physical_height = fb.virtual_height()
	scale := desktop_current_scale()
	d.canvas = new_scaled_canvas(desktop_scaled_extent(fb.virtual_width(), scale), desktop_scaled_extent(fb.virtual_height(), scale), fb.virtual_width(), fb.virtual_height(), scale)
	unsafe { free(voidptr(old)) }
	d.configure_display_outputs(fb)
	d.apply_session_placements()
	d.pointer_x = d.canvas.width / 2
	d.pointer_y = d.canvas.height / 2
	d.cursor_backing.box = DamageRect{}
	d.clear_hit_targets()
	d.close_window_overlays()
	d.drag = Drag{}
	d.dirty = true
}

fn (d &Desktop) window_display_area(index int) sessioncore.Rect {
	if d.session.state.display_count == 0 || index < 0 || index >= d.windows.len {
		return sessioncore.Rect{ w: d.canvas.width, h: desktop_usable_height(d.canvas.height, d.taskbar_height()) }
	}
	w := d.windows[index]
	if w.display.len > 0 { return d.session.state.display_for(w.display.str()).area }
	for i in 0 .. d.session.state.display_count {
		area := d.session.state.displays[i].area
		if w.x + w.width / 2 >= area.x && w.x + w.width / 2 < area.x + area.w && w.y + w.height / 2 >= area.y && w.y + w.height / 2 < area.y + area.h {
			return area
		}
	}
	return d.session.state.display_for('').area
}

// A theme change moves the work area's bottom edge as well as the bar.
fn (mut d Desktop) resize_taskbar_work_area(previous_height int) {
	for i in 0 .. d.session.output_count {
		d.session.outputs[i].area.h += previous_height - d.taskbar_height()
	}
	d.shell_display_geometry()
	for i in 0 .. d.windows.len {
		area := d.window_display_area(i)
		if d.windows[i].maximized {
			d.windows[i].x = area.x
			d.windows[i].y = area.y
			d.windows[i].width = area.w
			d.windows[i].height = area.h
		} else if d.windows[i].snap != .none_ {
			d.apply_snap_geometry(i, d.windows[i].snap, area.w, area.h + d.taskbar_height())
			d.windows[i].x += area.x
			d.windows[i].y += area.y
		} else {
			d.clamp_to_screen(i)
		}
	}
	d.close_window_overlays()
	d.close_taskbar_preview()
	d.hide_tooltip()
	d.clear_hit_targets()
}

fn (mut d Desktop) apply_session_placements() {
	mut slot := 0
	for i in 0 .. d.windows.len {
		if d.windows[i].factory_index < 0 && d.windows[i].page != .system { continue }
		if slot >= d.session.state.count { break }
		p := d.session.state.windows[slot]
		slot++
		d.windows[i].x = p.frame.x
		d.windows[i].y = p.frame.y
		d.windows[i].width = p.frame.w
		d.windows[i].height = p.frame.h
		d.windows[i].restore_x = p.restore.x
		d.windows[i].restore_y = p.restore.y
		d.windows[i].restore_width = p.restore.w
		d.windows[i].restore_height = p.restore.h
		d.windows[i].display = p.display
	}
}

fn (mut d Desktop) clamp_to_display(index int) {
	area := d.window_display_area(index)
	frame := sessioncore.clamp(sessioncore.Rect{d.windows[index].x, d.windows[index].y, d.windows[index].width, d.windows[index].height}, area)
	d.windows[index].x = frame.x
	d.windows[index].y = frame.y
	d.windows[index].width = frame.w
	d.windows[index].height = frame.h
}

fn (mut d Desktop) remember_window_display(id int) {
	index := d.window_index(id) or { return }
	w := d.windows[index]
	for i in 0 .. d.session.state.display_count {
		area := d.session.state.displays[i].area
		if w.x + w.width / 2 >= area.x && w.x + w.width / 2 < area.x + area.w && w.y + w.height / 2 >= area.y && w.y + w.height / 2 < area.y + area.h {
			d.windows[index].display = d.session.state.displays[i].id
			return
		}
	}
}
