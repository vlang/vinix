// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// The window manager. It keeps the window list, turns it into a ui2 element
// tree once per frame, and routes pointer events back to the elements that
// tree produced — so what is drawn and what is clickable can never drift
// apart.
module main

import ui2

// Action ids are structured so the handler can read them back without a
// lookup table: 'win.<id>.<part>' addresses one window's chrome, 'task.<id>'
// its taskbar entry.
// Wallpaper shortcuts carry the index of the application they open.
const action_shortcut_prefix = 'shortcut.'
// The desktop's own actions all begin with one of these. An action that does
// not is an application's, and is routed to whichever window it was clicked
// in — which is what lets a native application name its events whatever it
// likes, ui2's `__qml_...` or the file browser's `files.row.3` alike.
const desktop_action_prefixes = ['taskbar.', 'task.', 'win.', 'shortcut.', 'start.',
	action_switch_prefix]

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
	pointer_capture int
	// A Start-menu press is consumed through its release even when the press
	// launches something and closes the menu before that release arrives.
	start_menu_pointer bool

	frames  int
	running bool = true
	// What to do with the machine once the loop has ended and the session has
	// been torn down. Only init may set anything but keep_running.
	power PowerAction
	// The screen is only recomposed when something it shows has changed. An
	// idle desktop then costs almost nothing, and — with no garbage collector
	// on this target — stops rebuilding a tree it would only throw away.
	dirty bool = true
	// The taskbar clock owns its text so unchanged seconds do not allocate. It
	// occupies a fixed logical status area, which the framebuffer presenter
	// scales together with every other desktop coordinate.
	taskbar_clock_time    string
	taskbar_clock_date    string
	taskbar_clock_sampled bool
	taskbar_clock_seconds i64

	// Hit targets collected by the last render pass, in painting order.
	targets []HitTarget

	// Application clients. Native apps live in separate processes; a window
	// points to its compositor-side proxy by index.
	apps []NativeApp
	// An exclusive application is started by the main loop after it has
	// released the framebuffer, pointer and raw console keyboard.
	pending_external       string
	pending_external_title string
	pending_external_icon  string
	external_error         string
	external_error_title   string
	external_error_note    string
	external_error_hint    string

	settings Settings
	// Screenshot and video requests originate in the native Capture app, but
	// the compositor owns the pixels and the output stream.
	capture CaptureService
	// Cmd-Tab's session: which windows it is stepping through and whether it
	// has been held long enough to show them.
	switcher Switcher
	// The Start menu is compositor UI rather than a window. Search is kept on
	// the desktop so typed input can filter applications without an app process.
	start_menu_open      bool
	start_menu_all_apps  bool
	start_menu_searching bool
	start_menu_query     []u8
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
	closing_capture := d.windows[index].title == capture_app_title
	app_index := d.windows[index].app_index
	if app_index >= 0 && app_index < d.apps.len {
		mut app := d.apps[app_index]
		if mut app is RemoteApp {
			app.close()
		}
	}
	d.windows.delete(index)
	if closing_capture {
		d.capture_close()
	}
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

// activate is what a taskbar entry does: restore a minimised window, then put
// that window on top. A taskbar button is a focus target; only the window's
// explicit minimise control hides an already focused window.
fn (mut d Desktop) activate(id int) {
	index := d.window_index(id) or { return }
	if d.windows[index].minimized {
		d.windows[index].minimized = false
	}
	d.raise(id)
}

// ── Element tree ───────────────────────────────────────────────────

// build_tree describes the whole screen. The root is a transparent view
// because the wallpaper gradient is painted by the compositor before the tree
// is rendered, and ui2 has no gradient to declare.
fn (mut d Desktop) build_tree() ui2.Element {
	begin_frame_elements()
	mut children := frame_elements(available_apps.len + d.windows.len + 3)
	// Shortcuts first, so every window paints over them.
	shortcuts := d.shortcut_elements()
	children << shortcuts
	// The elements (and their nested child arrays) were copied into children;
	// only this temporary outer array is no longer needed.
	unsafe { shortcuts.free() }
	for window_index in 0 .. d.windows.len {
		if d.windows[window_index].minimized {
			continue
		}
		children << d.window_element(window_index)
	}
	children << d.taskbar_element()
	// The Start menu paints over windows and the taskbar, and its panel consumes
	// clicks in otherwise empty areas so they do not reach the window below.
	if d.start_menu_open {
		children << d.start_menu_element()
	}
	// Last, so the switcher is over everything it is a picture of.
	if d.switcher.shown {
		children << d.switcher_element()
	}

	return ui2.view('desktop', ui2.rect(0, 0, f64(d.canvas.width), f64(d.canvas.height)), ui2.BoxStyle{
		transparent: true
	}, children)
}

fn (mut d Desktop) window_element(window_index int) ui2.Element {
	window := &d.windows[window_index]
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
	step := if buttons_left {
		theme.button_size + theme.button_gap
	} else {
		-(theme.button_size + theme.button_gap)
	}

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
	}), 0, f64(if theme.title_centered { window.width } else { title_limit }), f64(theme.title_height)), ui2.TextStyle{
		color: title_text_color
		size: theme.title_size
		bold: theme.title_bold
		align: if theme.title_centered { .center } else { .left }
		lines: 1
	})

	mut title_children := frame_elements(4)
	title_children << title
	title_children << minimize
	title_children << maximize
	title_children << close
	title_bar := ui2.draggable_view(window.id_titlebar, ui2.rect(0, 0, f64(window.width), f64(theme.title_height)), ui2.BoxStyle{
		bg: title_bg
	}, title_children)

	divider := ui2.view(window.id_divider, ui2.rect(0, f64(theme.title_height - 1), f64(window.width), 1), ui2.BoxStyle{
		bg: theme.title_divider
	}, [])

	background, contents := d.window_contents(window_index, body_height)
	// Clickable so that touching a window anywhere brings it to the front,
	// not only its title bar.
	body := ui2.clickable_view(window.id_body, ui2.rect(0, f64(theme.title_height), f64(window.width), f64(body_height)), ui2.BoxStyle{
		bg: background
	}, contents)

	mut window_children := frame_elements(3)
	window_children << title_bar
	window_children << divider
	window_children << body
	return ui2.view(window.id_frame, window.frame_rect(), ui2.BoxStyle{
		bg: background
		radius: theme.window_radius
	}, window_children)
}

// window_contents is the body's background colour and its children. A native
// application supplies both: what it returns is its QML `Screen`, which inside
// someone else's window is a content area rather than a display, so its
// background becomes the body's and its children are placed straight into it.
fn (mut d Desktop) window_contents(window_index int, body_height int) (u32, []ui2.Element) {
	window := &d.windows[window_index]
	if window.app_index < 0 || window.app_index >= d.apps.len {
		return d.theme().window_body, window.content(window.width, body_height, d)
	}
	size := ui2.rect(0, 0, f64(window.width), f64(body_height))
	root := d.apps[window.app_index].build(size) or {
		// An application that cannot lay itself out should say so in its own
		// window rather than take the desktop down with it.
		mut error_children := frame_elements(2)
		error_children << body_line('This application failed to draw:', 18, 18, window.width - 36)
		error_children << muted_line(err.msg(), 18, 40, window.width - 36)
		return d.theme().window_body, error_children
	}
	return root.box.bg, root.children
}

// launch starts a native app process or queues an external application for the main
// loop to run after releasing the physical display and input devices.
fn (mut d Desktop) launch(factory AppFactory) {
	if factory.exclusive_command != '' {
		d.pending_external = factory.exclusive_command
		d.pending_external_title = factory.title
		d.pending_external_icon = factory.icon
		d.dirty = true
		return
	}
	if factory.open == unsafe { nil } || factory.process_name == '' {
		eprintln('vinix-desktop: ${factory.title} has no launcher')
		return
	}
	app := start_remote_app(factory, mut d) or {
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
	d.windows[index].icon = factory.icon
	d.clamp_to_screen(index)
}

// external_finished restores the native desktop after an exclusive program.
// Successful exits need only a redraw. Failures get a visible window because
// the console log is hidden as soon as the compositor takes the display back.
fn (mut d Desktop) external_finished(result ExternalProgramResult) {
	d.buttons = 0
	d.drag = Drag{}
	d.hover = ''
	d.wallpaper_valid = false
	d.dirty = true
	title := if d.pending_external_title == '' {
		'External application'
	} else {
		d.pending_external_title
	}
	icon := if d.pending_external_icon == '' { 'builtin:window' } else { d.pending_external_icon }
	d.pending_external_title = ''
	d.pending_external_icon = ''
	if result == .success {
		return
	}
	d.external_error = match result {
		.unavailable { '${title} is not installed in this desktop image.' }
		.spawn_failed { 'Vinix could not create the ${title} launcher process.' }
		.wait_failed { 'Vinix lost track of the ${title} launcher process.' }
		.failed { '${title} or Xorg exited with an error.' }
		.success { '' }
	}
	d.external_error_title = '${title} could not start'
	d.external_error_note = '${title} runs in an exclusive X11 session; the native desktop resumes when it exits.'
	d.external_error_hint = 'Build Firefox/Xorg, then rebuild the userland and desktop image.'
	id := d.spawn(title, .external_error, 180, 120, 560, 220)
	index := d.window_index(id) or { return }
	d.windows[index].icon = icon
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
	// Walk live windows rather than the backing store. Application slots
	// stay stable after a window closes, but a closed terminal or clock should
	// not keep doing background work forever. Minimized applications do keep
	// polling: a shell pipe must still be drained while its window is hidden.
	for window in d.windows {
		if window.app_index < 0 || window.app_index >= d.apps.len {
			continue
		}
		mut app := d.apps[window.app_index]
		if mut app is PollingApp {
			if app.poll() {
				d.dirty = true
			}
		}
	}
}

// The event-driven idle wait needs a timeout only for work that cannot signal
// a descriptor. Most desktops therefore wake once a second for their clock;
// opening a stopwatch or a continuously hosted framebuffer lowers the timeout
// to that application's requested cadence.
fn (d &Desktop) idle_wait_interval(maximum i64, frame_interval i64) i64 {
	mut interval := maximum
	for window in d.windows {
		if window.app_index < 0 || window.app_index >= d.apps.len {
			continue
		}
		app := d.apps[window.app_index]
		if app is RemoteApp && app.polling {
			// Keyboard and pointer delivery can invalidate the normal deadline.
			// Come back on the active cadence so the forced poll happens promptly.
			if !app.poll_sampled {
				return frame_interval
			}
			if app.poll_interval_ms == 0 {
				return frame_interval
			}
			candidate := i64(app.poll_interval_ms)
			if candidate < interval {
				interval = candidate
			}
		}
	}
	return interval
}

// focused_app_takes_keys reports whether the window on top belongs to an
// application that wants typed input.
fn (d &Desktop) focused_app_takes_keys() bool {
	index := d.focused_app_index() or { return false }
	app := d.apps[index]
	if app is RemoteApp {
		return app.keyboard
	}
	return app is KeyboardApp
}

fn (mut d Desktop) send_keys_to_focused(keys string) {
	index := d.focused_app_index() or { return }
	mut app := d.apps[index]
	if mut app is RemoteApp {
		if app.keyboard {
			app.key_input(keys)
			d.dirty = true
		}
		return
	}
	if mut app is KeyboardApp {
		app.key_input(keys)
		d.dirty = true
	}
}

// End the session, and take the machine with it when this compositor is the
// machine's init. Started from a shell on the full image it is an ordinary
// process that happens to own the screen: there, ending the session means
// giving the console back to that shell and nothing more.
fn (mut d Desktop) end_session(action PowerAction) {
	if desktop_is_init() {
		d.power = action
	}
	d.running = false
}

// The Start menu's power button.
fn (mut d Desktop) request_power_off() {
	d.end_session(.power_off)
}

// A power signal ends the session at a frame boundary, so applications are
// closed and the console is restored before the machine goes down.
fn (mut d Desktop) take_power_signal() {
	action := desktop_pending_power_action()
	if action == .keep_running {
		return
	}
	d.end_session(action)
}

// close_apps shuts every native client down before the compositor exits. App
// slots are intentionally stable while windows are open, so walk the slots
// themselves: a closed window has already closed its process and is harmless.
fn (mut d Desktop) close_apps() {
	for index in 0 .. d.apps.len {
		mut app := d.apps[index]
		if mut app is RemoteApp {
			app.close()
		}
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
		// Capture the desktop, not the Capture window. The compositor will wait
		// until it has presented a frame with this window hidden before writing
		// the first pixel. Its taskbar entry remains the way back to Stop.
		if action == capture_action_take_screenshot || action == capture_action_start_video {
			d.capture.owner_window_id = window.id
			d.minimize(window.id)
		}
		d.dirty = true
		return
	}
}

// forward_pointer_to_app routes raw pointer input only to applications that
// explicitly request it. A press captures the surface until release so a drag
// does not get lost merely because it crossed the content edge.
fn (mut d Desktop) forward_pointer_to_app(x int, y int, phase AppPointerPhase, button AppPointerButton, scroll int) bool {
	mut selected := -1
	if d.pointer_capture != 0 {
		selected = d.window_index(d.pointer_capture) or { -1 }
	} else {
		for i := d.windows.len - 1; i >= 0; i-- {
			window := &d.windows[i]
			body_top := window.y + d.theme().title_height
			if !window.minimized && window.app_index >= 0 && x >= window.x
				&& x < window.x + window.width && y >= body_top
				&& y < window.y + window.height {
				selected = i
				break
			}
		}
	}
	if selected < 0 || selected >= d.windows.len {
		if phase == .up {
			d.pointer_capture = 0
		}
		return false
	}
	window := &d.windows[selected]
	if window.app_index < 0 || window.app_index >= d.apps.len {
		return false
	}
	mut app := d.apps[window.app_index]
	if mut app is PointerApp {
		if !app.pointer_input_enabled() {
			return false
		}
		window_id := window.id
		body_height := window.height - d.theme().title_height
		mut local_x := x - window.x
		mut local_y := y - window.y - d.theme().title_height
		if local_x < 0 {
			local_x = 0
		}
		if local_y < 0 {
			local_y = 0
		}
		if local_x >= window.width {
			local_x = window.width - 1
		}
		if local_y >= body_height {
			local_y = body_height - 1
		}
		app.pointer_event(phase, button, scroll, local_x, local_y, window.width, body_height)
		if phase == .down {
			d.pointer_capture = window_id
			// A foreign surface has no ui2 action id to focus through the
			// ordinary click path. Treat its content like any other window:
			// clicking it raises the native frame and gives its keyboard bridge
			// focus for shortcuts and typing.
			d.raise(window_id)
		} else if phase == .up
			&& d.buttons & (button_left | button_right | button_middle) == 0 {
			d.pointer_capture = 0
		}
		return true
	}
	return false
}

// shortcut_elements lays the application shortcuts down the left edge of the
// wallpaper, where windows are least likely to sit on top of them. Each is a
// transparent view that only shows a panel while the pointer is on it, so an
// idle desktop is just the wallpaper and its icons.
fn (d &Desktop) shortcut_elements() []ui2.Element {
	mut out := frame_elements(available_apps.len)
	rows := shortcut_rows_for_height(d.canvas.height)
	for index in 0 .. available_apps.len {
		factory := &available_apps[index]
		id := app_shortcut_actions[index]
		theme := d.theme()
		hovered := d.hover == id
		column := index / rows
		row := index % rows
		x := shortcut_left + column * (shortcut_width + shortcut_gap)
		y := shortcut_top + row * (shortcut_height + shortcut_gap)
		icon_x := (shortcut_width - shortcut_icon) / 2
		mut shortcut_children := frame_elements(2)
		shortcut_children << ui2.button_with_image('', '', factory.icon, ui2.rect(f64(icon_x), 10, f64(shortcut_icon), f64(shortcut_icon)), ui2.BoxStyle{
			transparent: true
		}, ui2.TextStyle{
			color: if hovered { theme.shortcut_hover } else { theme.shortcut_label }
		})
		shortcut_children << ui2.label('', factory.title, ui2.rect(0, f64(shortcut_icon + 16), f64(shortcut_width), 18), ui2.TextStyle{
			color: if hovered { theme.shortcut_hover } else { theme.shortcut_label }
			shadow: true
			size: 12
			align: .center
		})
		out << ui2.clickable_view(id, ui2.rect(f64(x), f64(y), f64(shortcut_width), f64(shortcut_height)), ui2.BoxStyle{
			bg: theme.shortcut_panel
			radius: 8
			transparent: !hovered
		}, shortcut_children)
	}
	return out
}

// Shortcuts fill the usable height, then continue in another column. The
// Eight fit in one column on a MacBook's 720 logical pixels; the ninth begins
// a second column. A deliberately short display still keeps every utility
// above the taskbar.
fn shortcut_rows_for_height(height int) int {
	usable := height - taskbar_height - shortcut_top
	mut rows := usable / (shortcut_height + shortcut_gap)
	if rows < 1 {
		rows = 1
	}
	return rows
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
		return ui2.button_with_image(id, '', if set_hovered { glyph } else { '' }, ui2.rect(f64(x), f64(y), f64(theme.button_size), f64(theme.button_size)), ui2.BoxStyle{
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
	return ui2.button_with_image(id, '', glyph, ui2.rect(f64(x), f64(y), f64(theme.button_size), f64(theme.button_size)), ui2.BoxStyle{
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

	mut children := frame_elements(d.windows.len + 4)
	item_y := (taskbar_height - taskbar_item_height) / 2

	// The Start orb is the taskbar's anchor. Its standalone V is the first
	// letterform of the wallpaper wordmark, not a font-dependent character.
	children << ui2.button_with_image(action_start_toggle, '', 'builtin:vinix', ui2.rect(f64(edge_padding), f64(item_y), f64(start_button_width), f64(taskbar_item_height)), ui2.BoxStyle{
		bg: if d.start_menu_open || d.hover == action_start_toggle {
			theme.accent
		} else {
			theme.accent_dim
		}
		radius: taskbar_item_height / 2
	}, ui2.TextStyle{
		color: theme.taskbar_text_active
	})

	// After Start, show only what is open. `standard` gives every window an entry, the way
	// Windows XP did; `combined` gives each application one entry however many
	// windows it has, the way Windows 7 did.
	entries := d.taskbar_entries()
	defer {
		unsafe { entries.free() }
	}
	mut x := edge_padding + start_button_width + 8
	// Reserve this space before sizing entries. The clock is therefore visible
	// at the physical lower-right corner after 2x M1 presentation as well as
	// on an unscaled framebuffer.
	clock_width := taskbar_clock_width
	entry_right := width - edge_padding - clock_width - taskbar_item_gap

	// Entries share whatever room is left rather than each taking a fixed
	// slot: with a fixed one the last window opened simply had no entry, which
	// is the opposite of what a list of open windows is for.
	mut item_width := if dock { dock_item_width } else { taskbar_item_width }
	if entries.len > 0 {
		share := (entry_right - x + taskbar_item_gap) / entries.len - taskbar_item_gap
		if share < item_width {
			item_width = share
		}
		if item_width < taskbar_item_min_width {
			item_width = taskbar_item_min_width
		}
	}

	for entry in entries {
		if x + item_width > entry_right {
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
		children << ui2.button(entry.id, entry.label, ui2.rect(f64(x), f64(item_y), f64(item_width), f64(taskbar_item_height)), ui2.BoxStyle{
			bg: bg
			radius: 6
		}, ui2.TextStyle{
			color: text_color
			size: 12
			align: .left
		})
		x += item_width + taskbar_item_gap
	}

	// A regular taskbar pins the status area to the lower-right corner. A dock
	// keeps the same clock immediately after its task buttons so it remains
	// inside the floating panel instead of being stranded at the screen edge.
	clock_x := if dock { x } else { width - edge_padding - clock_width }
	children << ui2.label('clock.time', d.taskbar_clock_time, ui2.rect(f64(clock_x), 3, f64(clock_width), 21), ui2.TextStyle{
		color: theme.taskbar_text_active
		size: 17
		bold: true
		align: .right
	})
	children << ui2.label('clock.date', d.taskbar_clock_date, ui2.rect(f64(clock_x), 25, f64(clock_width), 17), ui2.TextStyle{
		color: theme.taskbar_muted
		size: 11
		align: .right
	})
	if dock {
		x = clock_x + clock_width + taskbar_item_gap
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
		return ui2.view('taskbar', ui2.rect(f64(panel_x), f64(panel_y), f64(panel_width), f64(taskbar_height)), ui2.BoxStyle{
			bg: theme.dock_bg
			radius: theme.dock_radius
		}, children)
	}

	return ui2.view('taskbar', ui2.rect(0, f64(d.canvas.height - taskbar_height), f64(width), f64(taskbar_height)), ui2.BoxStyle{
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
	mut out := []TaskbarEntry{cap: d.windows.len}
	unsafe { out.flags |= .noslices }
	if d.settings.taskbar_mode == .standard {
		mut last_id := 0
		for {
			index := d.next_window_by_age(last_id) or { break }
			window := &d.windows[index]
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
	mut seen := []string{cap: d.windows.len}
	unsafe { seen.flags |= .noslices }
	for window_index in 0 .. d.windows.len {
		window := &d.windows[window_index]
		if window.title in seen {
			continue
		}
		seen << window.title
		mut count := 0
		mut newest_index := window_index
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
				newest_index = i
				break
			}
		}
		out << TaskbarEntry{
			id: d.windows[newest_index].id_task
			label: if count > 1 { '${window.title}  (${count})' } else { window.title }
			active: active
			minimized: all_minimized
		}
	}
	unsafe { seen.free() }
	return out
}

// ── Pointer handling ───────────────────────────────────────────────

fn (mut d Desktop) on_pointer_move(x int, y int) {
	pointer_moved := x != d.pointer_x || y != d.pointer_y
	if pointer_moved {
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
		old_x := d.windows[moved].x
		old_y := d.windows[moved].y
		d.windows[moved].x = x - d.drag.offset_x
		d.windows[moved].y = y - d.drag.offset_y
		d.clamp_to_screen(moved)
		if d.windows[moved].x != old_x || d.windows[moved].y != old_y {
			d.dirty = true
		}
		return
	}
	if !d.start_menu_open && !d.start_menu_pointer {
		d.forward_pointer_to_app(x, y, .move, .no_button, 0)
	}

	hover := d.hit_action(x, y)
	if hover != d.hover {
		d.hover = hover
		d.dirty = true
	}
}

// clamp_to_screen keeps a window wholly visible when it fits. Oversized
// windows retain the looser reachable-title-bar rule so they can still be
// dragged to every clipped edge.
fn (mut d Desktop) clamp_to_screen(index int) {
	margin := 60
	available_width := d.canvas.width
	available_height := d.canvas.height - taskbar_height
	if d.windows[index].width <= available_width {
		if d.windows[index].x < 0 {
			d.windows[index].x = 0
		}
		if d.windows[index].x + d.windows[index].width > available_width {
			d.windows[index].x = available_width - d.windows[index].width
		}
	}
	if d.windows[index].height <= available_height {
		if d.windows[index].y + d.windows[index].height > available_height {
			d.windows[index].y = available_height - d.windows[index].height
		}
	}
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

	if d.switcher.active {
		// A click on a tile switches to that window; a click anywhere else
		// dismisses the switcher and then means whatever it would have meant.
		if action.starts_with(action_switch_prefix) {
			d.switcher_select(action[action_switch_prefix.len..].int())
			return
		}
		d.switcher_close()
	}

	if action == action_start_toggle {
		d.start_menu_pointer = true
		d.toggle_start_menu()
		return
	}

	if d.start_menu_open {
		d.start_menu_pointer = true
		if action.starts_with('start.') {
			d.handle_start_action(action)
			return
		}
		// Clicking anywhere outside the panel dismisses it, then performs the
		// action underneath, matching the Windows menu's click-away behavior.
		d.close_start_menu()
	}

	if d.forward_pointer_to_app(x, y, .down, .left, 0) {
		// Raw-surface clicks were already delivered and focused above. Falling
		// through would interpret their deliberately action-less content as an
		// empty-desktop click and immediately clear that focus again.
		return
	}

	if action == '' {
		// Empty desktop: drop focus so no title bar claims to be active.
		if y < d.canvas.height - taskbar_height {
			d.focus = 0
		}
		return
	}

	if !desktop_owns(action) {
		d.forward_to_app(x, y, action)
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
	if d.start_menu_pointer {
		d.start_menu_pointer = false
	} else {
		d.forward_pointer_to_app(x, y, .up, .left, 0)
	}
	d.drag = Drag{}
	d.hover = d.hit_action(x, y)
	d.dirty = true
}

// Non-primary buttons and the wheel have no desktop chrome meaning yet, but a
// native pixel-surface client needs them for its own interaction model.
fn (mut d Desktop) on_app_pointer_button(x int, y int, phase AppPointerPhase, button AppPointerButton) {
	if d.switcher.active || d.start_menu_open {
		return
	}
	if d.forward_pointer_to_app(x, y, phase, button, 0) {
		d.dirty = true
	}
}

fn (mut d Desktop) on_app_pointer_scroll(x int, y int, scroll int) {
	if scroll == 0 || d.switcher.active || d.start_menu_open {
		return
	}
	if d.forward_pointer_to_app(x, y, .scroll, .no_button, scroll) {
		d.dirty = true
	}
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
