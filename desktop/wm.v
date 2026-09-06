// The window manager. It keeps the window list, turns it into a ui2 element
// tree once per frame, and routes pointer events back to the elements that
// tree produced — so what is drawn and what is clickable can never drift
// apart.
module main

import ui2

// Action ids are structured so the handler can read them back without a
// lookup table: 'win.<id>.<part>' addresses one window's chrome, 'task.<id>'
// its taskbar entry.
const action_new_window = 'taskbar.new'
// Launcher buttons and wallpaper shortcuts both carry the index of the
// application they open.
const action_launch_prefix = 'taskbar.launch.'
const action_shortcut_prefix = 'shortcut.'
// The desktop's own actions all begin with one of these. An action that does
// not is an application's, and is routed to whichever window it was clicked
// in — which is what lets a hosted application name its events whatever it
// likes, ui2's `__qml_...` or the file browser's `files.row.3` alike.
const desktop_action_prefixes = ['taskbar.', 'task.', 'win.', 'shortcut.']

enum DragKind {
	none_
	move
}

struct Drag {
mut:
	kind      DragKind = .none_
	window_id int
	// Where in the window the pointer grabbed it, so the window does not jump
	// to have its corner under the cursor.
	offset_x int
	offset_y int
}

struct Desktop {
mut:
	canvas  Canvas
	fonts   []FontFace
	windows []Window // painting order; the last entry is on top
	next_id int = 1
	focus   int
	drag    Drag
	hover   string

	pointer_x       int
	pointer_y       int
	buttons         u32
	pointer_present bool

	frames  int
	running bool = true
	// The screen is only recomposed when something it shows has changed. An
	// idle desktop then costs almost nothing, and — with no garbage collector
	// on this target — stops rebuilding a tree it would only throw away.
	dirty bool = true

	clock_time string
	clock_date string

	// Hit targets collected by the last render pass, in painting order.
	targets []HitTarget

	// Applications the desktop is hosting. A window points into this by index.
	apps []HostedApp

	settings Settings
	// One screen's worth of wallpaper, scaled once and kept. It only changes
	// when the setting does, and rescaling a photograph every frame to paint a
	// backdrop that has not moved would cost more than the rest of a frame.
	wallpaper       []u32
	wallpaper_valid bool

	tz_offset_seconds i64
}

// ── Window list ────────────────────────────────────────────────────

fn (mut d Desktop) spawn(title string, page Page, x int, y int, width int, height int) int {
	id := d.next_id
	d.next_id++
	prefix := 'win.${id}'
	d.windows << Window{
		id: id
		title: title
		page: page
		x: x
		y: y
		width: width
		height: height
		restore_x: x
		restore_y: y
		restore_width: width
		restore_height: height
		id_frame: prefix
		id_titlebar: '${prefix}.titlebar'
		id_title: '${prefix}.title'
		id_close: '${prefix}.close'
		id_maximize: '${prefix}.maximize'
		id_minimize: '${prefix}.minimize'
		id_divider: '${prefix}.divider'
		id_body: '${prefix}.body'
		id_task: 'task.${id}'
	}
	d.focus = id
	d.dirty = true
	return id
}

fn (d &Desktop) window_index(id int) ?int {
	for i, window in d.windows {
		if window.id == id {
			return i
		}
	}
	return none
}

fn (d &Desktop) visible_window_count() int {
	mut count := 0
	for window in d.windows {
		if !window.minimized {
			count++
		}
	}
	return count
}

// next_window_by_age finds the window opened just after `after_id`. The window
// list is kept in painting order, which changes whenever one is raised, while
// the taskbar wants the order they were opened in. Ids only ever increase, so
// repeatedly taking the smallest id above the last one walks that order
// without building a sorted copy every frame.
fn (d &Desktop) next_window_by_age(after_id int) ?int {
	mut found := -1
	for i, window in d.windows {
		if window.id <= after_id {
			continue
		}
		if found < 0 || window.id < d.windows[found].id {
			found = i
		}
	}
	if found < 0 {
		return none
	}
	return found
}

fn (d &Desktop) pointer_description() string {
	return if d.pointer_present { '/dev/pointer' } else { 'not available' }
}

// raise moves a window to the top of the painting order and focuses it.
fn (mut d Desktop) raise(id int) {
	index := d.window_index(id) or { return }
	window := d.windows[index]
	d.windows.delete(index)
	d.windows << window
	d.focus = id
	d.dirty = true
}

fn (mut d Desktop) close_window(id int) {
	index := d.window_index(id) or { return }
	d.windows.delete(index)
	if d.focus == id {
		d.focus = if d.windows.len > 0 { d.windows.last().id } else { 0 }
	}
	d.dirty = true
}

fn (mut d Desktop) toggle_maximize(id int) {
	index := d.window_index(id) or { return }
	if d.windows[index].maximized {
		d.windows[index].x = d.windows[index].restore_x
		d.windows[index].y = d.windows[index].restore_y
		d.windows[index].width = d.windows[index].restore_width
		d.windows[index].height = d.windows[index].restore_height
		d.windows[index].maximized = false
	} else {
		d.windows[index].restore_x = d.windows[index].x
		d.windows[index].restore_y = d.windows[index].y
		d.windows[index].restore_width = d.windows[index].width
		d.windows[index].restore_height = d.windows[index].height
		d.windows[index].x = 0
		d.windows[index].y = 0
		d.windows[index].width = d.canvas.width
		d.windows[index].height = d.canvas.height - taskbar_height
		d.windows[index].maximized = true
	}
	d.raise(id)
}

fn (mut d Desktop) minimize(id int) {
	index := d.window_index(id) or { return }
	d.windows[index].minimized = true
	d.dirty = true
	if d.focus == id {
		d.focus = 0
		for i := d.windows.len - 1; i >= 0; i-- {
			if !d.windows[i].minimized {
				d.focus = d.windows[i].id
				break
			}
		}
	}
}

// activate is what a taskbar entry does: restore a minimised window, or
// minimise the one already on top, which is the behaviour a taskbar button is
// expected to have.
fn (mut d Desktop) activate(id int) {
	index := d.window_index(id) or { return }
	if d.windows[index].minimized {
		d.windows[index].minimized = false
		d.raise(id)
		return
	}
	if d.focus == id && d.windows.last().id == id {
		d.minimize(id)
		return
	}
	d.raise(id)
}

// ── Element tree ───────────────────────────────────────────────────

// build_tree describes the whole screen. The root is a transparent view
// because the wallpaper gradient is painted by the compositor before the tree
// is rendered, and ui2 has no gradient to declare.
fn (mut d Desktop) build_tree() ui2.Element {
	mut children := []ui2.Element{}
	// Shortcuts first, so every window paints over them.
	children << d.shortcut_elements()
	for window in d.windows {
		if window.minimized {
			continue
		}
		children << d.window_element(window)
	}
	children << d.taskbar_element()

	return ui2.view('desktop', ui2.rect(0, 0, f64(d.canvas.width), f64(d.canvas.height)),
		ui2.BoxStyle{
		transparent: true
	}, children)
}

fn (mut d Desktop) window_element(window Window) ui2.Element {
	theme := d.theme()
	active := window.id == d.focus
	body_height := window.height - theme.title_height

	title_text_color := if active { theme.title_text_active } else { theme.title_text_inactive }
	title_bg := if active { theme.title_active_bg } else { theme.title_inactive_bg }

	// Close, then zoom, then minimise, laid out from whichever end the setting
	// puts them at. Ordering close outermost is what both conventions do.
	buttons_left := d.settings.button_side == .left
	span := 3 * theme.button_size + 2 * theme.button_gap
	mut button_x := if buttons_left {
		theme.button_inset
	} else {
		window.width - theme.button_inset - theme.button_size
	}
	step := if buttons_left { theme.button_size + theme.button_gap } else { -(theme.button_size +
			theme.button_gap) }

	// macOS shows the glyphs in all three discs as soon as the pointer is over
	// any of them, not just the one under it.
	set_hovered := d.hover == window.id_close || d.hover == window.id_minimize
		|| d.hover == window.id_maximize

	maximize_glyph := if window.maximized { 'builtin:restore' } else { 'builtin:maximize' }

	// Traffic lights are read as a group, and red-yellow-green left to right is
	// the whole of what makes them recognisable — so they keep that order at
	// either end, rather than reversing when they move to the right. Flat
	// buttons have no such signature and instead put close outermost, which is
	// what both conventions do.
	mut close_x, mut middle_x, mut inner_x := button_x, button_x + step, button_x + 2 * step
	mut middle, mut inner := window.id_minimize, window.id_maximize
	mut middle_glyph, mut inner_glyph := 'builtin:minimize', maximize_glyph
	if theme.button_look == .traffic {
		left_edge := if buttons_left {
			theme.button_inset
		} else {
			window.width - theme.button_inset - span
		}
		stride := theme.button_size + theme.button_gap
		close_x = left_edge
		middle_x = left_edge + stride
		inner_x = left_edge + 2 * stride
	} else if !buttons_left {
		// Inward from close on the right: zoom, then minimise.
		middle, inner = window.id_maximize, window.id_minimize
		middle_glyph, inner_glyph = maximize_glyph, 'builtin:minimize'
	}

	close := d.title_button(window.id_close, 'builtin:close', close_x, active, set_hovered)
	maximize := d.title_button(middle, middle_glyph, middle_x, active, set_hovered)
	minimize := d.title_button(inner, inner_glyph, inner_x, active, set_hovered)

	// The title takes what the buttons leave. Centred themes centre it over the
	// whole bar and simply accept a shorter run.
	text_inset_left := if buttons_left { theme.button_inset + span + 10 } else { 14 }
	title_limit := window.width - span - theme.button_inset - text_inset_left - 10
	title := ui2.label(window.id_title, window.title, ui2.rect(f64(if theme.title_centered {
		0
	} else {
		text_inset_left
	}), 0, f64(if theme.title_centered { window.width } else { title_limit }), f64(theme.title_height)),
		ui2.TextStyle{
		color: title_text_color
		size: theme.title_size
		bold: theme.title_bold
		align: if theme.title_centered { .center } else { .left }
		lines: 1
	})

	title_bar := ui2.draggable_view(window.id_titlebar, ui2.rect(0, 0, f64(window.width),
		f64(theme.title_height)), ui2.BoxStyle{
		bg: title_bg
	}, [title, minimize, maximize, close])

	divider := ui2.view(window.id_divider, ui2.rect(0, f64(theme.title_height - 1), f64(window.width),
		1), ui2.BoxStyle{
		bg: theme.title_divider
	}, [])

	background, contents := d.window_contents(window, body_height)
	// Clickable so that touching a window anywhere brings it to the front,
	// not only its title bar.
	body := ui2.clickable_view(window.id_body, ui2.rect(0, f64(theme.title_height), f64(window.width),
		f64(body_height)), ui2.BoxStyle{
		bg: background
	}, contents)

	return ui2.view(window.id_frame, window.frame_rect(), ui2.BoxStyle{
		bg: background
		radius: theme.window_radius
	}, [title_bar, divider, body])
}

// window_contents is the body's background colour and its children. A hosted
// application supplies both: what it returns is its QML `Screen`, which inside
// someone else's window is a content area rather than a display, so its
// background becomes the body's and its children are placed straight into it.
fn (mut d Desktop) window_contents(window Window, body_height int) (u32, []ui2.Element) {
	if window.app_index < 0 || window.app_index >= d.apps.len {
		return d.theme().window_body, window.content(window.width, body_height, d)
	}
	size := ui2.rect(0, 0, f64(window.width), f64(body_height))
	root := d.apps[window.app_index].build(size) or {
		// An application that cannot lay itself out should say so in its own
		// window rather than take the desktop down with it.
		return d.theme().window_body, [
			body_line('This application failed to draw:', 18, 18, window.width - 36),
			muted_line(err.msg(), 18, 40, window.width - 36),
		]
	}
	return root.box.bg, root.children
}

// launch opens a window for one of the applications the desktop can host.
fn (mut d Desktop) launch(factory AppFactory) {
	app := factory.open(mut d) or {
		eprintln('vinix-desktop: cannot start ${factory.title}: ${err}')
		return
	}
	d.apps << app
	// Cascade like any other new window, but at the size the application asked
	// for rather than the desktop's default.
	step := ((d.next_id - 1) % 6) * 26
	id := d.spawn(factory.title, .app, 120 + step, 60 + step, factory.width, factory.height)
	index := d.window_index(id) or { return }
	d.windows[index].app_index = d.apps.len - 1
	d.clamp_to_screen(index)
}

// launch_titled opens the application with this title, for a caller that knows
// which one it wants rather than where it sits in the list.
// invalidate_wallpaper throws away the scaled backdrop so the next frame
// paints the newly chosen one.
fn (mut d Desktop) invalidate_wallpaper() {
	d.wallpaper_valid = false
	d.dirty = true
}

// poll_apps gives every application that has something of its own going on a
// chance to say so, and redraws if any of them did.
fn (mut d Desktop) poll_apps() {
	for i := 0; i < d.apps.len; i++ {
		mut app := d.apps[i]
		if mut app is PollingApp {
			if app.poll() {
				d.dirty = true
			}
		}
	}
}

// focused_app_takes_keys reports whether the window on top belongs to an
// application that wants typed input.
fn (d &Desktop) focused_app_takes_keys() bool {
	index := d.focused_app_index() or { return false }
	app := d.apps[index]
	return app is KeyboardApp
}

fn (mut d Desktop) send_keys_to_focused(keys string) {
	index := d.focused_app_index() or { return }
	mut app := d.apps[index]
	if mut app is KeyboardApp {
		app.key_input(keys)
		d.dirty = true
	}
}

// focused_app_index finds the application behind the focused window, if the
// focused window has one.
fn (d &Desktop) focused_app_index() ?int {
	for window in d.windows {
		if window.id == d.focus && !window.minimized && window.app_index >= 0
			&& window.app_index < d.apps.len {
			return window.app_index
		}
	}
	return none
}

fn (mut d Desktop) launch_titled(title string) {
	for factory in available_apps {
		if factory.title == title {
			d.launch(factory)
			return
		}
	}
	eprintln('vinix-desktop: no application called ${title}')
}

fn (mut d Desktop) launch_index(index int) {
	if index >= 0 && index < available_apps.len {
		d.launch(available_apps[index])
	}
}

// forward_to_app hands an action the desktop does not recognise to the
// application under the pointer. Hosted ids are ui2's own — it prefixes them
// `__qml_` — so rather than parse them the window manager routes by where the
// click landed, which is also what decides it between two open applications.
fn (mut d Desktop) forward_to_app(x int, y int, action string) {
	for i := d.windows.len - 1; i >= 0; i-- {
		window := d.windows[i]
		if window.minimized || window.app_index < 0 || window.app_index >= d.apps.len {
			continue
		}
		if x < window.x || y < window.y || x >= window.x + window.width
			|| y >= window.y + window.height {
			continue
		}
		d.apps[window.app_index].handle(action) or {
			eprintln('vinix-desktop: ${window.title}: ${err}')
		}
		d.raise(window.id)
		d.dirty = true
		return
	}
}

// shortcut_elements lays the application shortcuts down the left edge of the
// wallpaper, where windows are least likely to sit on top of them. Each is a
// transparent view that only shows a panel while the pointer is on it, so an
// idle desktop is just the wallpaper and its icons.
fn (d &Desktop) shortcut_elements() []ui2.Element {
	mut out := []ui2.Element{cap: available_apps.len}
	for index, factory in available_apps {
		id := '${action_shortcut_prefix}${index}'
		theme := d.theme()
		hovered := d.hover == id
		y := shortcut_top + index * (shortcut_height + shortcut_gap)
		icon_x := (shortcut_width - shortcut_icon) / 2
		out << ui2.clickable_view(id, ui2.rect(f64(shortcut_left), f64(y), f64(shortcut_width),
			f64(shortcut_height)), ui2.BoxStyle{
			bg: theme.shortcut_panel
			radius: 8
			transparent: !hovered
		}, [
			ui2.button_with_image('', '', factory.icon, ui2.rect(f64(icon_x), 10, f64(shortcut_icon),
				f64(shortcut_icon)), ui2.BoxStyle{
				transparent: true
			}, ui2.TextStyle{
				color: if hovered { theme.shortcut_hover } else { theme.shortcut_label }
			}),
			ui2.label('', factory.title, ui2.rect(0, f64(shortcut_icon + 16), f64(shortcut_width),
				18), ui2.TextStyle{
				color: if hovered { theme.shortcut_hover } else { theme.shortcut_label }
				shadow: true
				size: 12
				align: .center
			}),
		])
	}
	return out
}

// desktop_owns reports whether an action is the window manager's own. Anything
// else is an application's, wherever it came from.
fn desktop_owns(action string) bool {
	for prefix in desktop_action_prefixes {
		if action.starts_with(prefix) {
			return true
		}
	}
	return false
}

fn (d &Desktop) title_button(id string, glyph string, x int, active bool, set_hovered bool) ui2.Element {
	theme := d.theme()
	y := (theme.title_height - theme.button_size) / 2
	hovered := d.hover == id
	is_close := glyph == 'builtin:close'

	if theme.button_look == .traffic {
		// A disc: coloured when the window is focused, grey when it is not, and
		// carrying its glyph only while the pointer is over the set. Radius is
		// half the size, which is how a rounded rect becomes a circle.
		fill := if !active {
			theme.traffic_idle
		} else if is_close {
			theme.traffic_close
		} else if glyph == 'builtin:minimize' {
			theme.traffic_minimize
		} else {
			theme.traffic_zoom
		}
		return ui2.button_with_image(id, '', if set_hovered { glyph } else { '' }, ui2.rect(f64(x),
			f64(y), f64(theme.button_size), f64(theme.button_size)), ui2.BoxStyle{
			bg: fill
			radius: theme.button_size / 2
		}, ui2.TextStyle{
			color: theme.glyph_color
		})
	}

	bg := if !hovered {
		u32(0)
	} else if is_close {
		theme.button_close_hover
	} else {
		theme.button_hover
	}
	return ui2.button_with_image(id, '', glyph, ui2.rect(f64(x), f64(y), f64(theme.button_size),
		f64(theme.button_size)), ui2.BoxStyle{
		bg: bg
		radius: 5
		transparent: !hovered
	}, ui2.TextStyle{
		color: if hovered && is_close { theme.glyph_on_close } else { theme.glyph_color }
	})
}

fn (d &Desktop) taskbar_element() ui2.Element {
	theme := d.theme()
	width := d.canvas.width
	// A dock is a panel wide enough for what is in it, centred and floating
	// clear of the screen's edge. A taskbar is the whole width of the bottom.
	dock := theme.dock
	edge_padding := if dock { theme.dock_padding } else { taskbar_padding }

	mut children := []ui2.Element{}
	item_y := (taskbar_height - taskbar_item_height) / 2

	// Left: a button that opens another window, so the taskbar list can be
	// seen growing and shrinking.
	new_button_width := 96
	children << ui2.button(action_new_window, 'New window', ui2.rect(f64(edge_padding),
		f64(item_y), f64(new_button_width), f64(taskbar_item_height)), ui2.BoxStyle{
		bg: if d.hover == action_new_window { theme.accent } else { theme.accent_dim }
		radius: 6
	}, ui2.TextStyle{
		color: theme.taskbar_text_active
		size: 12
		bold: true
		align: .center
	})

	// Then a launcher per application the desktop can host, so a ui2
	// application is one click away rather than something only the startup
	// arrangement can open.
	mut launcher_x := edge_padding + new_button_width + 8
	for index, factory in available_apps {
		id := '${action_launch_prefix}${index}'
		children << ui2.button_with_image(id, factory.title, factory.icon, ui2.rect(f64(launcher_x),
			f64(item_y), f64(launcher_width), f64(taskbar_item_height)), ui2.BoxStyle{
			bg: if d.hover == id { theme.taskbar_item_hover } else { theme.taskbar_item_bg }
			radius: 6
		}, ui2.TextStyle{
			color: theme.taskbar_text
			size: 12
			align: .center
		})
		launcher_x += launcher_width + 6
	}

	// Middle: what is open. `standard` gives every window an entry, the way
	// Windows XP did; `combined` gives each application one entry however many
	// windows it has, the way Windows 7 did.
	entries := d.taskbar_entries()
	mut x := launcher_x + 8
	// Where the entries must stop. A dock stops where its contents do, but no
	// wider than the screen: it is centred, so a panel that outgrew the display
	// would hang off both ends at once.
	room := width - edge_padding - clock_area_width - 12
	clock_left := if dock {
		wanted := x + entries.len * (dock_item_width + taskbar_item_gap)
		if wanted < room { wanted } else { room }
	} else {
		width - clock_area_width
	}

	// Entries share whatever room is left rather than each taking a fixed
	// slot: with a fixed one the last window opened simply had no entry, which
	// is the opposite of what a list of open windows is for.
	mut item_width := if dock { dock_item_width } else { taskbar_item_width }
	if entries.len > 0 {
		limit := if dock { room } else { clock_left }
		share := (limit - x + taskbar_item_gap) / entries.len - taskbar_item_gap
		if share < item_width {
			item_width = share
		}
		if item_width < taskbar_item_min_width {
			item_width = taskbar_item_min_width
		}
	}

	for entry in entries {
		if x + item_width > clock_left - taskbar_item_gap {
			break
		}
		bg := if entry.active {
			theme.taskbar_item_active
		} else if d.hover == entry.id {
			theme.taskbar_item_hover
		} else {
			theme.taskbar_item_bg
		}
		// A minimised window is dimmed rather than marked with a character:
		// the baked faces are ASCII, so a nice bullet would come out blank.
		text_color := if entry.active {
			theme.taskbar_text_active
		} else if entry.minimized {
			theme.taskbar_muted
		} else {
			theme.taskbar_text
		}
		children << ui2.button(entry.id, entry.label, ui2.rect(f64(x), f64(item_y), f64(item_width),
			f64(taskbar_item_height)), ui2.BoxStyle{
			bg: bg
			radius: 6
		}, ui2.TextStyle{
			color: text_color
			size: 12
			align: .left
		})
		x += item_width + taskbar_item_gap
	}

	// The clock. A taskbar pins it to the far corner; a dock carries it as its
	// last item, so the panel grows to hold it rather than leaving it stranded
	// off to one side of a centred bar.
	clock_x := if dock { x + 6 } else { width - clock_area_width }
	clock_width := clock_area_width - taskbar_padding
	children << ui2.label('clock.time', d.clock_time, ui2.rect(f64(clock_x), 6, f64(clock_width),
		20), ui2.TextStyle{
		color: theme.clock_time
		size: 17
		bold: true
		align: .right
	})
	children << ui2.label('clock.date', d.clock_date, ui2.rect(f64(clock_x), 26, f64(clock_width),
		16), ui2.TextStyle{
		color: theme.clock_date
		size: 11
		align: .right
	})
	if dock {
		x = clock_x + clock_width + 6
	}

	// A hairline along the top edge separates a full-width bar from the
	// wallpaper without a shadow, which would read as heavy at this size. A
	// dock has its own rounded outline instead.
	if !dock {
		children << ui2.view('taskbar.edge', ui2.rect(0, 0, f64(width), 1), ui2.BoxStyle{
			bg: theme.taskbar_edge
		}, [])
	}

	if dock {
		panel_width := x - taskbar_item_gap + theme.dock_padding
		panel_x := (width - panel_width) / 2
		// Clear of the bottom edge, the way a dock sits.
		panel_y := d.canvas.height - taskbar_height - dock_bottom_gap
		return ui2.view('taskbar', ui2.rect(f64(panel_x), f64(panel_y), f64(panel_width),
			f64(taskbar_height)), ui2.BoxStyle{
			bg: theme.dock_bg
			radius: theme.dock_radius
		}, children)
	}

	return ui2.view('taskbar', ui2.rect(0, f64(d.canvas.height - taskbar_height), f64(width),
		f64(taskbar_height)), ui2.BoxStyle{
		bg: theme.taskbar_bg
	}, children)
}

// TaskbarEntry is one button in the middle of the bar. In standard mode it is
// a window; in combined mode it is an application, and its id names the window
// clicking it should raise.
struct TaskbarEntry {
	id        string
	label     string
	active    bool
	minimized bool
}

fn (d &Desktop) taskbar_entries() []TaskbarEntry {
	mut out := []TaskbarEntry{}
	if d.settings.taskbar_mode == .standard {
		mut last_id := 0
		for {
			index := d.next_window_by_age(last_id) or { break }
			window := d.windows[index]
			last_id = window.id
			out << TaskbarEntry{
				id: window.id_task
				label: window.title
				active: window.id == d.focus && !window.minimized
				minimized: window.minimized
			}
		}
		return out
	}

	// Combined: one entry per title, labelled with how many windows share it.
	// Clicking it activates the most recently raised of them, which is what
	// makes a second click minimise the one you just brought up.
	mut seen := []string{}
	for window in d.windows {
		if window.title in seen {
			continue
		}
		seen << window.title
		mut count := 0
		mut newest := window.id
		mut active := false
		mut all_minimized := true
		for other in d.windows {
			if other.title != window.title {
				continue
			}
			count++
			if other.id == d.focus && !other.minimized {
				active = true
			}
			if !other.minimized {
				all_minimized = false
			}
		}
		// The last in painting order is the one on top.
		for i := d.windows.len - 1; i >= 0; i-- {
			if d.windows[i].title == window.title {
				newest = d.windows[i].id
				break
			}
		}
		out << TaskbarEntry{
			id: 'task.${newest}'
			label: if count > 1 { '${window.title}  (${count})' } else { window.title }
			active: active
			minimized: all_minimized
		}
	}
	return out
}

// ── Pointer handling ───────────────────────────────────────────────

fn (mut d Desktop) on_pointer_move(x int, y int) {
	if x != d.pointer_x || y != d.pointer_y {
		d.dirty = true
	}
	d.pointer_x = x
	d.pointer_y = y

	// The button level, not just the release edge, ends a drag. The driver
	// reports the current state on every read, so a release that was missed
	// between two frames cannot leave a window stuck to the cursor.
	if d.drag.kind == .move && d.buttons & button_left == 0 {
		d.drag = Drag{}
	}

	if d.drag.kind == .move {
		index := d.window_index(d.drag.window_id) or {
			d.drag = Drag{}
			return
		}
		// A maximised window that is dragged goes back to its own size, with
		// the grab kept proportionally along the title bar.
		if d.windows[index].maximized {
			ratio := f64(d.drag.offset_x) / f64(d.windows[index].width)
			d.toggle_maximize(d.drag.window_id)
			new_index := d.window_index(d.drag.window_id) or { return }
			d.drag.offset_x = int(ratio * f64(d.windows[new_index].width))
			d.drag.offset_y = d.theme().title_height / 2
		}
		moved := d.window_index(d.drag.window_id) or { return }
		d.windows[moved].x = x - d.drag.offset_x
		d.windows[moved].y = y - d.drag.offset_y
		d.clamp_to_screen(moved)
		d.dirty = true
		return
	}

	hover := d.hit_action(x, y)
	if hover != d.hover {
		d.hover = hover
		d.dirty = true
	}
}

// clamp_to_screen keeps enough of a window reachable that it can always be
// dragged back: the title bar may not leave the screen or slide under the
// taskbar.
fn (mut d Desktop) clamp_to_screen(index int) {
	margin := 60
	max_x := d.canvas.width - margin
	max_y := d.canvas.height - taskbar_height - d.theme().title_height
	if d.windows[index].x > max_x {
		d.windows[index].x = max_x
	}
	if d.windows[index].x + d.windows[index].width < margin {
		d.windows[index].x = margin - d.windows[index].width
	}
	if d.windows[index].y < 0 {
		d.windows[index].y = 0
	}
	if d.windows[index].y > max_y {
		d.windows[index].y = max_y
	}
}

fn (mut d Desktop) on_pointer_down(x int, y int) {
	action := d.hit_action(x, y)
	d.hover = action
	d.dirty = true

	if action == '' {
		// Empty desktop: drop focus so no title bar claims to be active.
		if y < d.canvas.height - taskbar_height {
			d.focus = 0
		}
		return
	}

	if action == action_new_window {
		d.spawn_scattered()
		return
	}

	if !desktop_owns(action) {
		d.forward_to_app(x, y, action)
		return
	}

	if action.starts_with(action_launch_prefix) {
		d.launch_index(action[action_launch_prefix.len..].int())
		return
	}

	if action.starts_with(action_shortcut_prefix) {
		d.launch_index(action[action_shortcut_prefix.len..].int())
		return
	}

	if action.starts_with('task.') {
		id := action[5..].int()
		d.activate(id)
		return
	}

	if action.starts_with('win.') {
		rest := action[4..]
		dot := rest.index('.') or { return }
		id := rest[..dot].int()
		part := rest[dot + 1..]
		match part {
			'titlebar' {
				d.raise(id)
				index := d.window_index(id) or { return }
				d.drag = Drag{
					kind: .move
					window_id: id
					offset_x: x - d.windows[index].x
					offset_y: y - d.windows[index].y
				}
			}
			'close' {
				d.close_window(id)
			}
			'maximize' {
				d.toggle_maximize(id)
			}
			'minimize' {
				d.minimize(id)
			}
			else {
				d.raise(id)
			}
		}
	}
}

fn (mut d Desktop) on_pointer_up(x int, y int) {
	d.drag = Drag{}
	d.hover = d.hit_action(x, y)
	d.dirty = true
}

// hit_action returns the action id of the topmost target under a point. The
// targets come from the render pass in painting order, so walking backwards
// finds what the user can actually see.
fn (d &Desktop) hit_action(x int, y int) string {
	for i := d.targets.len - 1; i >= 0; i-- {
		target := d.targets[i]
		if x >= target.x && y >= target.y && x < target.x + target.width
			&& y < target.y + target.height {
			return target.action_id
		}
	}
	return ''
}

// spawn_scattered opens the next window slightly offset from the last one, the
// cascade a window manager traditionally uses so a new window never lands
// exactly on top of its predecessor.
fn (mut d Desktop) spawn_scattered() {
	pages := [Page.welcome, .system, .palette, .notes]
	titles := ['Welcome', 'System', 'Palette', 'Notes']
	slot := (d.next_id - 1) % pages.len
	step := ((d.next_id - 1) % 6) * 26
	width := 380
	height := 240
	x := 90 + step
	y := 70 + step
	id := d.spawn(titles[slot], pages[slot], x, y, width, height)
	index := d.window_index(id) or { return }
	d.clamp_to_screen(index)
}
