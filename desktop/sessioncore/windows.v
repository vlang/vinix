// SPDX-License-Identifier: GPL-2.0-or-later
module sessioncore

pub enum Layout {
	floating
	columns
	rows
	grid
	main_stack
}

pub struct Rect {
pub mut:
	x int
	y int
	w int
	h int
}

pub struct Display {
pub mut:
	id      Text
	area    Rect
	primary bool
}

pub struct Workspace {
pub mut:
	name   Text
	layout Layout
	gap    int = 8
}

pub struct Placement {
pub mut:
	app       Text
	instance  int
	frame     Rect
	restore   Rect
	display   Text
	workspace int
	group     int
	snap      int
	maximized bool
	minimized bool
	failed    bool
}

pub struct Windows {
pub mut:
	workspaces      [max_workspaces]Workspace
	workspace_count int = 4
	active          int
	displays        [max_displays]Display
	display_count   int
	windows         [max_windows]Placement
	count           int
	restore_session bool = true
	// Keep a disconnected display's identity so reconnect can return windows.
	return_to_display bool = true
}

pub fn (mut s Windows) configure(count int) ! {
	if count < 1 || count > max_workspaces { return error('workspace count must be 1..16') }
	s.workspace_count = count
	if s.active >= count { s.active = count - 1 }
	for i in 0 .. s.count {
		if s.windows[i].workspace >= count { s.windows[i].workspace = count - 1 }
	}
}

pub fn (mut s Windows) rename(workspace int, name string) ! {
	if workspace < 0 || workspace >= s.workspace_count || name.len == 0 || name.len > 48 {
		return error('invalid workspace name')
	}
	s.workspaces[workspace].name.set(name)!
}

pub fn (mut s Windows) set_layout(workspace int, layout Layout, gap int) ! {
	if workspace < 0 || workspace >= s.workspace_count || gap < 0 || gap > 64 {
		return error('invalid workspace layout')
	}
	s.workspaces[workspace].layout = layout
	s.workspaces[workspace].gap = gap
	s.arrange(workspace)
}

pub fn (s &Windows) display_for(id string) Display {
	for i in 0 .. s.display_count { if s.displays[i].id.str() == id { return s.displays[i] } }
	for i in 0 .. s.display_count { if s.displays[i].primary { return s.displays[i] } }
	return if s.display_count > 0 {
		s.displays[0]
	} else {
		Display{ area: Rect{ w: 1024, h: 720 } }
	}
}

pub fn clamp(frame Rect, area Rect) Rect {
	w := if frame.w < 120 {
		120
	} else if frame.w > area.w {
		area.w
	} else {
		frame.w
	}
	h := if frame.h < 60 {
		60
	} else if frame.h > area.h {
		area.h
	} else {
		frame.h
	}
	x := if frame.x < area.x {
		area.x
	} else if frame.x + w > area.x + area.w {
		area.x + area.w - w
	} else {
		frame.x
	}
	y := if frame.y < area.y {
		area.y
	} else if frame.y + h > area.y + area.h {
		area.y + area.h - h
	} else {
		frame.y
	}
	return Rect{x, y, w, h}
}

pub fn (mut s Windows) update_displays(displays []Display) ! {
	if displays.len == 0 || displays.len > max_displays { return error('invalid display count') }
	mut primary_count := 0
	for i, d in displays {
		if d.id.len == 0 || d.area.w < 120 || d.area.h < 60 {
			return error('invalid display geometry')
		}
		if d.primary { primary_count++ }
		for j in 0 .. i {
			if displays[j].id.str() == d.id.str() { return error('duplicate display identity') }
		}
	}
	if primary_count != 1 { return error('exactly one primary display is required') }
	for i, d in displays { s.displays[i] = d }
	s.display_count = displays.len
	for i in 0 .. s.count {
		d := s.display_for(s.windows[i].display.str())
		if !s.return_to_display { s.windows[i].display = d.id }
		s.windows[i].restore = clamp(s.windows[i].restore, d.area)
		if s.windows[i].maximized {
			s.windows[i].frame = d.area
		} else {
			s.windows[i].frame = clamp(s.windows[i].frame, d.area)
		}
	}
	for i in 0 .. s.workspace_count { s.arrange(i) }
}

pub fn (mut s Windows) move(index int, workspace int, include_group bool) ! {
	if index < 0 || index >= s.count || workspace < 0 || workspace >= s.workspace_count {
		return error('invalid window or workspace')
	}
	group := s.windows[index].group
	for i in 0 .. s.count {
		if i == index || (include_group && group > 0 && s.windows[i].group == group) {
			s.windows[i].workspace = workspace
		}
	}
	s.arrange(workspace)
}

pub fn (mut s Windows) arrange(workspace int) {
	if workspace < 0 || workspace >= s.workspace_count { return }
	layout := s.workspaces[workspace].layout
	if layout == .floating { return }
	for di in 0 .. s.display_count {
		mut indices := [max_windows]int{}
		mut count := 0
		for i in 0 .. s.count {
			w := s.windows[i]
			if w.workspace == workspace && !w.minimized && s.display_for(w.display.str()).id.str() == s.displays[di].id.str() {
				indices[count] = i
				count++
			}
		}
		if count == 0 { continue }
		area := s.displays[di].area
		gap := s.workspaces[workspace].gap
		mut columns := count
		mut rows := 1
		if layout == .rows {
			columns = 1
			rows = count
		}
		if layout == .grid {
			columns = 1
			for columns * columns < count { columns++ }
			rows = (count + columns - 1) / columns
		}
		for slot in 0 .. count {
			index := indices[slot]
			mut frame := Rect{}
			if layout == .main_stack && count > 1 {
				left := (area.w - 3 * gap) * 3 / 5
				if slot == 0 {
					frame = Rect{area.x + gap, area.y + gap, left, area.h - 2 * gap}
				} else {
					top := area.y + gap + (area.h - gap) * (slot - 1) / (count - 1)
					bottom := area.y + gap + (area.h - gap) * slot / (count - 1)
					frame = Rect{area.x + left + 2 * gap, top, area.w - left - 3 * gap, bottom - top - gap}
				}
			} else {
				col := slot % columns
				row := slot / columns
				x := area.x + gap + (area.w - gap) * col / columns
				y := area.y + gap + (area.h - gap) * row / rows
				right := area.x + gap + (area.w - gap) * (col + 1) / columns
				bottom := area.y + gap + (area.h - gap) * (row + 1) / rows
				frame = Rect{x, y, right - x - gap, bottom - y - gap}
			}
			// Leave a crowded workspace floating rather than creating unusable
			// tiles, overlaps or negative dimensions.
			if frame.w < 120 || frame.h < 60 { return }
		}
		for slot in 0 .. count {
			// Computation is deterministic; apply only after every tile fits.
			index := indices[slot]
			mut frame := Rect{}
			if layout == .main_stack && count > 1 {
				left := (area.w - 3 * gap) * 3 / 5
				if slot == 0 {
					frame = Rect{area.x + gap, area.y + gap, left, area.h - 2 * gap}
				} else {
					top := area.y + gap + (area.h - gap) * (slot - 1) / (count - 1)
					bottom := area.y + gap + (area.h - gap) * slot / (count - 1)
					frame = Rect{area.x + left + 2 * gap, top, area.w - left - 3 * gap, bottom - top - gap}
				}
			} else {
				col := slot % columns
				row := slot / columns
				x := area.x + gap + (area.w - gap) * col / columns
				y := area.y + gap + (area.h - gap) * row / rows
				right := area.x + gap + (area.w - gap) * (col + 1) / columns
				bottom := area.y + gap + (area.h - gap) * (row + 1) / rows
				frame = Rect{x, y, right - x - gap, bottom - y - gap}
			}
			s.windows[index].frame = frame
			s.windows[index].maximized = false
			s.windows[index].snap = 0
		}
	}
}

pub fn (s &Windows) encode() string {
	mut w := Writer{}
	w.add('vinix-session\t1\t')
	w.number(s.workspace_count)
	w.add('\t')
	w.number(s.active)
	w.add('\t')
	w.number(int(s.restore_session))
	w.add('\t')
	w.number(int(s.return_to_display))
	w.add('\n')
	for i in 0 .. s.workspace_count {
		ws := s.workspaces[i]
		w.add('workspace\t')
		w.number(i)
		w.add('\t')
		w.field(ws.name.str())
		w.add('\t')
		w.number(int(ws.layout))
		w.add('\t')
		w.number(ws.gap)
		w.add('\n')
	}
	for i in 0 .. s.count {
		p := s.windows[i]
		w.add('window\t')
		w.field(p.app.str())
		w.add('\t')
		w.number(p.instance)
		w.add('\t')
		w.field(p.display.str())
		for n in [p.workspace, p.group, p.frame.x, p.frame.y, p.frame.w, p.frame.h, p.restore.x,
			p.restore.y, p.restore.w, p.restore.h, p.snap, int(p.maximized), int(p.minimized),
			int(p.failed)]! {
			w.add('\t')
			w.number(n)
		}
		w.add('\n')
	}
	return w.finish()
}

pub fn decode_windows(record string) !Windows {
	if record.len == 0 || record.len > 256 * 1024 { return error('invalid session record size') }
	mut s := Windows{}
	mut start := 0
	mut header := false
	mut workspaces := u32(0)
	for end in 0 .. record.len + 1 {
		if end < record.len && record[end] != `\n` { continue }
		if end == start {
			start = end + 1
			continue
		}
		f := fields(unsafe { tos(&record.str[start], end - start) })!
		start = end + 1
		if !header {
			if f.count != 6 || f.values[0] != 'vinix-session' || f.values[1] != '1' {
				return error('invalid session header')
			}
			s.workspace_count = int(number(f.values[2], 1, max_workspaces)!)
			s.active = int(number(f.values[3], 0, s.workspace_count - 1)!)
			s.restore_session = number(f.values[4], 0, 1)! != 0
			s.return_to_display = number(f.values[5], 0, 1)! != 0
			header = true
			continue
		}
		if f.values[0] == 'workspace' {
			if f.count != 5 { return error('invalid workspace record') }
			i := int(number(f.values[1], 0, s.workspace_count - 1)!)
			if workspaces & (u32(1) << i) != 0 { return error('duplicate workspace') }
			workspaces |= u32(1) << i
			s.workspaces[i].name = unfield(f.values[2])!
			if s.workspaces[i].name.len > 48 { return error('workspace name too long') }
			s.workspaces[i].layout = unsafe { Layout(number(f.values[3], 0, 4)!) }
			s.workspaces[i].gap = int(number(f.values[4], 0, 64)!)
		} else if f.values[0] == 'window' {
			if f.count != 18 || s.count == max_windows { return error('invalid window record') }
			mut p := Placement{ app: unfield(f.values[1])!, instance: int(number(f.values[2], 0, max_windows)!), display: unfield(f.values[3])! }
			if !identifier(p.app.str()) { return error('invalid application identity') }
			p.workspace = int(number(f.values[4], 0, s.workspace_count - 1)!)
			p.group = int(number(f.values[5], 0, max_windows)!)
			p.frame = parse_rect(f, 6)!
			p.restore = parse_rect(f, 10)!
			p.snap = int(number(f.values[14], 0, 6)!)
			p.maximized = number(f.values[15], 0, 1)! != 0
			p.minimized = number(f.values[16], 0, 1)! != 0
			p.failed = number(f.values[17], 0, 1)! != 0
			for i in 0 .. s.count {
				if s.windows[i].app.str() == p.app.str() && s.windows[i].instance == p.instance {
					return error('duplicate window instance')
				}
			}
			s.windows[s.count] = p
			s.count++
		} else {
			return error('unknown session record')
		}
	}
	if !header || workspaces != (u32(1) << s.workspace_count) - 1 {
		return error('incomplete session record')
	}
	return s
}

fn parse_rect(f Fields, start int) !Rect {
	return Rect{int(number(f.values[start], -32768, 32768)!), int(number(f.values[start + 1], -32768, 32768)!), int(number(f.values[start + 2], 1, 32768)!), int(number(f.values[start + 3], 1, 32768)!)}
}
