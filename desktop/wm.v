// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
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
// These prefixes identify the desktop's own selectors only when the hit target
// came from the desktop world. An application's selectors are opaque, even if
// their spelling collides with one of these prefixes.
const desktop_action_prefixes = ['taskbar.', 'task.', 'win.', 'shortcut.', 'start.',
	action_switch_prefix, action_workspace_prefix, taskbar_pin_action_prefix,
	taskbar_preview_prefix, 'tray.']

enum DragKind {
	none_
	move
	resize
}

struct Drag {
mut:
	kind      DragKind = .none_
	window_id int
	// Where in the window the pointer grabbed it, so the window does not jump
	// to have its corner under the cursor.
	offset_x int
	offset_y int
	// A resize is measured from the frame at pointer-down, so grabbing anywhere
	// in the corner does not make the edge jump under the pointer. The grabbed
	// edges follow the pointer; the opposite edges stay put.
	start_pointer_x int
	start_pointer_y int
	start_x         int
	start_y         int
	start_width     int
	start_height    int
	resize_left     bool
	resize_top      bool
	resize_horizontal bool = true
	resize_vertical   bool = true
	// Edge placement is a drag gesture, not a side effect of clicking an
	// already edge-touching title bar without moving it.
	moved               bool
	snap_on_release     WindowSnap
	maximize_on_release bool
	shake               WindowShake
}

// DamageRect describes the part of the composed canvas that differs from the
// last presented frame. It stays in logical coordinates; Canvas and
// Framebuffer each map it to their physical pixels.
struct DamageRect {
mut:
	x     int
	y     int
	w     int
	h     int
	valid bool
}

struct Desktop {
mut:
	// Where the compositor keeps its own lists (pins, history, preferences).
	home          string = desktop_home
	canvas        Canvas
	preview_cache VinixPreviewCache
	fonts         []FontFace
	// The bundled app artwork at each size it has been drawn at, made the
	// first time. Native app helper processes never rasterize frames, so
	// theirs stays empty. See sized_bundled_icon.
	sized_icons []SizedIcon
	// PNG resources loaded lazily for installed native UI2 applications.
	native_asset_icons map[string]&AppIcon
	windows            []Window // painting order; the last entry is on top
	next_id            int = 1
	focus              int
	current_workspace  int
	drag               Drag
	hover              string // owned; update through set_hover

	pointer_x       int
	pointer_y       int
	buttons         u32
	pointer_present bool
	pointer_capture int
	shortcut_order  []int
	pinned_apps     []int
	shortcut_press  ShortcutPress
	// Window chrome owns the primary-button gesture through its release, even
	// when the button-up packet ends the drag during the move pass first.
	chrome_pointer_capture bool
	// A Start-menu press is consumed through its release even when the press
	// launches something and closes the menu before that release arrives.
	start_menu_pointer bool

	frames  int
	running bool = true
	// What to do once the loop has ended and the session has been torn down.
	// Only init may set anything but keep_running; reload_desktop returns to the
	// supervisor without asking the kernel to power-cycle the machine.
	power PowerAction
	// The screen is only recomposed when something it shows has changed. An
	// idle desktop then costs almost nothing, and — with no garbage collector
	// on this target — stops rebuilding a tree it would only throw away.
	dirty bool = true
	// A moving top-level window can reuse the last complete canvas. Motion
	// accumulates its old and new bounds here until the next frame consumes it.
	drag_damage DamageRect
	// Changes confined to a known area (the taskbar clock ticking, one
	// application redrawing its window) accumulate here instead of setting
	// `dirty`, so the next frame recomposes only that area. See frame_damage.v.
	frame_damage FrameDamage
	// Whether the frame being built repaints everything. Only such a frame
	// asks applications for a tree just because the one it has is old.
	paint_full bool = true
	// Set while rendering paints a window that is not focused, whose default
	// button and focus ring the macOS theme leaves out.
	inactive_window bool
	// The pixels under the software pointer, so a pointer that only moved can
	// be redrawn without recomposing anything else.
	cursor_backing CursorBacking
	// Set by the last pointer packet when it moved the pointer and everything
	// else it changed was recorded in `frame_damage`: no button, no scroll, no
	// drag and no hover change outside the two controls involved.
	pointer_moved_only bool
	// The taskbar clock owns its text so unchanged seconds do not allocate. It
	// occupies a fixed logical status area, which the framebuffer presenter
	// scales together with every other desktop coordinate.
	taskbar_clock_time    string
	taskbar_clock_date    string
	taskbar_build_time    string
	taskbar_build_date    string
	taskbar_clock_sampled bool
	taskbar_clock_seconds i64

	// Hit targets collected by the last render pass, in painting order.
	targets []HitTarget
	// Optional monitor for high-level pointer selectors from both UI worlds.
	trace_selectors bool

	// Application clients. Native apps live in separate processes; a window
	// points to its compositor-side proxy by index.
	apps []NativeApp
	// An exclusive application is started by the main loop after it has
	// released the framebuffer, pointer and raw console keyboard.
	pending_external       string
	// The taskbar status file for the application process being started.
	pending_status_path    string
	pending_external_title string
	pending_external_icon  string
	external_error         string
	external_error_title   string
	external_error_note    string
	external_error_hint    string
	// What the external-error window reports, kept so that its text can be
	// composed again when the language changes.
	external_error_app     string
	external_error_package string
	external_error_result  ExternalProgramResult
	external_error_missing bool

	settings Settings
	// What typing goes through first: the input source's dead keys and the
	// Ctrl-Space panel.
	keyboard  KeyboardInput
	clipboard HostClipboard
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
	start_menu_page      int
	start_menu_query     []u8
	// Programs pinned to the Start menu and the most recently launched ones,
	// both catalog indices persisted by process name.
	start_pins      []int
	recent_programs []int
	// The program whose recent items fill the right column, start_recent_all
	// for Recent Items, or start_recent_none for the system links.
	start_menu_recent_app    int = start_recent_none
	start_menu_recent_items  []RecentItem
	start_menu_recent_titles []string
	start_menu_recent_dirs   []bool
	// Taskbar interaction beyond plain clicks: dragging buttons, thumbnails and
	// peeking, Show Desktop and the notification area.
	taskbar_press            TaskbarPress
	taskbar_preview          TaskbarPreview
	show_desktop             ShowDesktop
	window_isolation         [workspace_count]WindowIsolation
	overview                 WindowOverview
	window_layout            WindowLayout
	window_layout_right_release bool
	snap_assist              WindowSnapAssist
	window_actions           WindowActions
	overlay_input            WindowOverlayInput
	tray                     TrayState
	version_check            VersionCheck
	next_status_token        int
	taskbar_status_polled_ms i64
	taskbar_marquee_ms       i64
	// The backdrop, prepared once and kept. It only changes when the setting
	// does, and rescaling a photograph every frame to paint a backdrop that has
	// not moved would cost more than the rest of a frame. A photograph is one
	// screen's worth of pixels in `wallpaper`; a colour is `wallpaper_rows`, one
	// colour per row, and the wordmark's box. See build_wallpaper.
	wallpaper             []u32
	wallpaper_rows        []u32
	wallpaper_logo        LogoBox
	wallpaper_logo_pixels []u32
	wallpaper_width       int
	wallpaper_height      int
	wallpaper_valid       bool

	tz_offset_seconds i64
}

// ── Window list ────────────────────────────────────────────────────

fn (mut d Desktop) spawn(title string, page Page, x int, y int, width int, height int) int {
	id := d.next_id
	d.next_id++
	prefix := 'win.${id}'
	d.windows << Window{
		id:             id
		title:          title
		page:           page
		x:              x
		y:              y
		width:          width
		height:         height
		restore_x:      x
		restore_y:      y
		restore_width:  width
		restore_height: height
		workspace:      d.current_workspace
		id_frame:       prefix
		id_titlebar:    '${prefix}.titlebar'
		id_title:       '${prefix}.title'
		id_close:       '${prefix}.close'
		id_maximize:    '${prefix}.maximize'
		id_minimize:    '${prefix}.minimize'
		id_divider:     '${prefix}.divider'
		id_body:        '${prefix}.body'
		id_resize:      '${prefix}.resize'
		id_resize_sw:   '${prefix}.resize_sw'
		id_resize_nw:   '${prefix}.resize_nw'
		id_resize_ne:   '${prefix}.resize_ne'
		id_resize_n:    '${prefix}.resize_n'
		id_resize_s:    '${prefix}.resize_s'
		id_resize_e:    '${prefix}.resize_e'
		id_resize_w:    '${prefix}.resize_w'
		id_task:        'task.${id}'
		task_rank:      id
		id_preview:       '${taskbar_preview_prefix}${id}'
		id_preview_close: '${taskbar_preview_prefix}${id}.close'
		id_thumbnail:     '${window_thumbnail_image_prefix}${id}'
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
		if window.workspace == d.current_workspace && !window.minimized {
			count++
		}
	}
	return count
}

fn (d &Desktop) pointer_description() string {
	return if d.pointer_present { '/dev/pointer' } else { tr('window.system.no_pointer') }
}

// raise moves a window to the top of the painting order and focuses it.
fn (mut d Desktop) raise(id int) {
	index := d.window_index(id) or { return }
	window := d.windows[index]
	d.windows.delete(index)
	// Transfer the deleted slot's owned strings and thumbnail to the tail.
	// An ordinary append deep-clones the Window and strands its old payload.
	unsafe { d.windows.push_many(&window, 1) }
	d.focus = id
	d.acknowledge_attention(id)
	d.dirty = true
}

fn (mut d Desktop) close_window(id int) {
	index := d.window_index(id) or { return }
	closing_capture := d.windows[index].title == capture_app_title
	app_index := d.windows[index].app_index
	if app_index >= 0 && app_index < d.apps.len {
		mut app := d.apps[app_index]
		if !native_app_prepare_close(mut app) {
			d.activate(id)
			d.dirty = true
			return
		}
		if mut app is RemoteApp {
			app.close()
		}
	}
	d.release_window_thumbnail(index)
	d.release_taskbar_status(index)
	for slot, hidden in d.show_desktop.hidden {
		if hidden == id {
			d.show_desktop.hidden.delete(slot)
			break
		}
	}
	if d.taskbar_preview.peek_window == id {
		d.end_peek()
	}
	d.windows.delete(index)
	if closing_capture {
		d.capture_close()
	}
	if d.focus == id {
		d.focus_top_window_in_current_workspace()
	}
	d.dirty = true
}

fn (mut d Desktop) remember_restore_frame(index int) {
	d.windows[index].restore_x = d.windows[index].x
	d.windows[index].restore_y = d.windows[index].y
	d.windows[index].restore_width = d.windows[index].width
	d.windows[index].restore_height = d.windows[index].height
}

fn (mut d Desktop) restore_window(id int) {
	index := d.window_index(id) or { return }
	d.windows[index].x = d.windows[index].restore_x
	d.windows[index].y = d.windows[index].restore_y
	d.windows[index].width = d.windows[index].restore_width
	d.windows[index].height = d.windows[index].restore_height
	d.windows[index].maximized = false
	d.windows[index].snap = .none_
	d.raise(id)
}

fn (mut d Desktop) maximize(id int) {
	index := d.window_index(id) or { return }
	if d.windows[index].maximized {
		return
	}
	// A snapped window already remembers the normal frame it should return to.
	if d.windows[index].snap == .none_ {
		d.remember_restore_frame(index)
	}
	d.windows[index].x = 0
	d.windows[index].y = 0
	d.windows[index].width = d.canvas.width
	d.windows[index].height = d.canvas.height - taskbar_height
	d.windows[index].maximized = true
	d.windows[index].snap = .none_
	d.raise(id)
}

fn (mut d Desktop) toggle_maximize(id int) {
	index := d.window_index(id) or { return }
	if d.windows[index].maximized {
		d.restore_window(id)
	} else {
		d.maximize(id)
	}
}

fn (mut d Desktop) snap_window(id int, snap WindowSnap) {
	if snap == .none_ {
		return
	}
	index := d.window_index(id) or { return }
	// Moving between arranged states must not replace the original normal
	// frame with a maximized or half-screen frame.
	if !d.windows[index].maximized && d.windows[index].snap == .none_ {
		d.remember_restore_frame(index)
	}
	d.apply_snap_geometry(index, snap, d.canvas.width, d.canvas.height)
	d.windows[index].maximized = false
	d.windows[index].snap = snap
	d.raise(id)
}

fn (mut d Desktop) minimize(id int) {
	index := d.window_index(id) or { return }
	d.windows[index].hidden_by_isolation = false
	d.windows[index].minimized = true
	d.dirty = true
	if d.focus == id {
		d.focus_top_window_in_current_workspace()
	}
}

// activate is what a taskbar entry does: restore a minimised window, then put
// that window on top. A taskbar button is a focus target; only the window's
// explicit minimise control hides an already focused window.
fn (mut d Desktop) activate(id int) {
	mut index := d.window_index(id) or { return }
	if d.windows[index].workspace != d.current_workspace {
		d.switch_workspace(d.windows[index].workspace)
	}
	index = d.window_index(id) or { return }
	if d.windows[index].minimized {
		d.windows[index].minimized = false
	}
	d.windows[index].hidden_by_isolation = false
	// Bringing a window back by hand ends the Show Desktop session for it.
	for slot, hidden in d.show_desktop.hidden {
		if hidden == id {
			d.show_desktop.hidden.delete(slot)
			break
		}
	}
	d.raise(id)
}

// ── Element tree ───────────────────────────────────────────────────

// build_tree describes the whole screen. The root is a transparent view
// because the wallpaper gradient is painted by the compositor before the tree
// is rendered, and ui2 has no gradient to declare.
fn (mut d Desktop) build_tree() ui2.Element {
	begin_frame_elements()
	mut children := frame_elements(available_apps.len + d.windows.len + 6)
	// Shortcuts first, so every window paints over them.
	shortcuts := d.shortcut_elements()
	children << shortcuts
	// The elements (and their nested child arrays) were copied into children;
	// only this temporary outer array is no longer needed.
	unsafe { shortcuts.free() }
	// Aero Peek keeps one window solid, or none for the desktop, and draws the
	// rest as glass. A peeked window shows even if it is minimized, or on
	// another workspace, since a pinned button covers all of its windows.
	peek := d.peek_target()
	for window_index in 0 .. d.windows.len {
		window_id := d.windows[window_index].id
		if window_id != peek && (d.windows[window_index].workspace != d.current_workspace
			|| d.windows[window_index].minimized) {
			continue
		}
		if peek != 0 && window_id != peek {
			children << d.peek_ghost_element(window_index)
			continue
		}
		children << d.window_element(window_index)
	}
	if placement := d.window_placement_element() {
		children << ui2.Element{ ...placement }
	}
	children << d.taskbar_element()
	// Taskbar popups rise from the bar, over the windows but under the Start
	// menu, which closes them when it opens anyway.
	if preview := d.taskbar_preview_element() {
		children << preview
	}
	if flyout := d.tray_flyout_element() {
		children << flyout
	}
	if tooltip := d.taskbar_tooltip_element() {
		children << tooltip
	}
	// The Start menu paints over windows and the taskbar, and its panel consumes
	// clicks in otherwise empty areas so they do not reach the window below.
	if d.start_menu_open {
		children << d.start_menu_element()
	}
	// Last, so the switcher is over everything it is a picture of.
	if d.switcher.shown {
		children << d.switcher_element()
	}
	if hud := d.keyboard_hud_element() {
		children << hud
	}
	if layout := d.window_layout_element() {
		children << ui2.Element{ ...layout }
	}
	if d.overview.active {
		children << d.window_overview_element()
	}
	if assist := d.window_snap_assist_element() {
		children << ui2.Element{ ...assist }
	}
	if actions := d.window_actions_element() {
		children << ui2.Element{ ...actions }
	}

	return ui2.view('desktop', ui2.rect(0, 0, f64(d.canvas.width), f64(d.canvas.height)), ui2.BoxStyle{
		transparent: true
	}, children)
}

// An application's first element with this id is its toolbar. Under the macOS
// theme the window draws it in the title bar, titled with the toolbar's text
// and its image, if the application gives them; see window_element.
const app_toolbar_id = 'app.toolbar'

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

	maximize_glyph := if theme.button_look == .traffic {
		// Catalina calls this the zoom control. Its mark stays a plus while the
		// standard window frame toggles between its two sizes.
		'builtin:zoom'
	} else {
		if window.maximized { 'builtin:restore' } else { 'builtin:maximize' }
	}

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
		middle_glyph = 'builtin:traffic_minimize'
		inner_glyph = 'builtin:zoom'
	} else if !buttons_left {
		// Inward from close on the right: zoom, then minimise.
		middle, inner = window.id_maximize, window.id_minimize
		middle_glyph, inner_glyph = maximize_glyph, 'builtin:minimize'
	}

	close_glyph := if theme.button_look == .traffic {
		'builtin:traffic_close'
	} else {
		'builtin:close'
	}
	close := d.title_button(window.id_close, close_glyph, close_x, active, set_hovered)
	maximize := d.title_button(middle, middle_glyph, middle_x, active, set_hovered)
	minimize := d.title_button(inner, inner_glyph, inner_x, active, set_hovered)

	background, mut contents := d.window_contents(window_index, body_height)
	// Catalina draws a window's toolbar in its title bar, under one gradient,
	// and Finder titles the window after the folder it shows. An application
	// asks for both by leading with an app_toolbar_id view: it moves here, out
	// of the body, so each of its elements is in the tree -- and freed -- once.
	// The body keeps its place, and the application its coordinates.
	mut toolbar := ui2.Element{}
	mut toolbar_height := 0
	if d.settings.theme == .macos && contents.len > 0 && contents[0].id == app_toolbar_id
		&& contents[0].frame.height >= 1 && int(contents[0].frame.height) < body_height {
		toolbar = contents[0]
		toolbar_height = int(toolbar.frame.height)
		for index in 1 .. contents.len {
			contents[index - 1] = contents[index]
		}
		unsafe {
			contents.len = contents.len - 1
		}
	}
	title_text := if toolbar.text.len > 0 { toolbar.text } else { app_title_text(window.title) }
	title_style := ui2.TextStyle{
		color: title_text_color
		size:  theme.title_size
		bold:  theme.title_bold
		align: if theme.title_centered { .center } else { .left }
		lines: 1
	}

	// The title takes what the buttons leave. Centred themes centre it over the
	// whole bar and simply accept a shorter run.
	text_inset_left := if buttons_left { theme.button_inset + span + 10 } else { 14 }
	title_limit := window.width - span - theme.button_inset - text_inset_left - 10
	// A folder's title carries its icon, as Finder's does, the two centred as one.
	title_icon_width := if toolbar.image_path.len > 0 && theme.title_centered && d.fonts.len > 0 {
		20
	} else {
		0
	}
	title := ui2.label(window.id_title, title_text, ui2.rect(f64(if theme.title_centered {
		title_icon_width / 2
	} else {
		text_inset_left
	}), 0, f64(if theme.title_centered { window.width } else { title_limit }), f64(theme.title_height)),
		title_style)

	mut title_children := frame_elements(6)
	// These controls borrow persistent window ids, model strings and frame
	// arrays. V3 deep-clones a named Element on append; transfer its fields.
	title_children << ui2.Element{ ...title }
	if title_icon_width > 0 {
		text_width := d.face_for(title_style).text_width(title_text)
		title_children << ui2.Element{
			...ui2.image('', toolbar.image_path, ui2.rect(f64((window.width - text_width) / 2 +
				title_icon_width / 2 - title_icon_width), f64((theme.title_height - 16) / 2), 16, 16))
			text_style: ui2.TextStyle{
				color: toolbar.text_style.color
			}
		}
	}
	title_children << ui2.Element{ ...minimize }
	title_children << ui2.Element{ ...maximize }
	title_children << ui2.Element{ ...close }
	if toolbar_height > 0 {
		title_children << ui2.Element{
			...toolbar
			frame: ui2.rect(0, f64(theme.title_height), f64(window.width), f64(toolbar_height))
			box:   ui2.BoxStyle{
				transparent: true
			}
		}
	}
	title_bar := ui2.draggable_view(window.id_titlebar, ui2.rect(0, 0, f64(window.width), f64(theme.title_height +
		toolbar_height)), ui2.BoxStyle{
		bg: title_bg
	}, title_children)

	divider := ui2.view(window.id_divider, ui2.rect(0, f64(theme.title_height + toolbar_height - 1),
		f64(window.width), 1), ui2.BoxStyle{
		bg: if active { theme.title_divider } else { theme.title_inactive_divider }
	}, [])

	// Clickable so that touching a window anywhere brings it to the front,
	// not only its title bar.
	body := ui2.clickable_view(window.id_body, ui2.rect(0, f64(theme.title_height), f64(window.width), f64(body_height)), ui2.BoxStyle{
		bg: background
	}, contents)

	mut window_children := frame_elements(13)
	// The body goes first: a toolbar's title bar reaches down over its top.
	// Transfer the app tree without cloning its borrowed text and pooled arrays.
	window_children << ui2.Element{ ...body }
	window_children << ui2.Element{ ...title_bar }
	window_children << ui2.Element{ ...divider }
	// Arranged windows already fill a desktop-defined region. A normal window
	// retains an invisible target along every edge and corner for resizing, without
	// adding chrome over the application's surface.
	if !window.maximized && window.snap == .none_ {
		grip := window_resize_grip_size
		edge := window_resize_edge_size
		right := window.width - grip
		bottom := window.height - grip
		window_children << resize_grip(window.id_resize_n, grip, 0, window.width - 2 * grip,
			edge, ui2.cursor_resize_ns)
		window_children << resize_grip(window.id_resize_s, grip, window.height - edge,
			window.width - 2 * grip, edge, ui2.cursor_resize_ns)
		window_children << resize_grip(window.id_resize_w, 0, grip, edge,
			window.height - 2 * grip, ui2.cursor_resize_ew)
		window_children << resize_grip(window.id_resize_e, window.width - edge, grip, edge,
			window.height - 2 * grip, ui2.cursor_resize_ew)
		window_children << resize_grip(window.id_resize, right, bottom, grip, grip, ui2.cursor_resize_nwse)
		window_children << resize_grip(window.id_resize_sw, 0, bottom, grip, grip, ui2.cursor_resize_nesw)
		// The upper corners are the title bar's, whose buttons sit a few pixels
		// in from them. There the grip is an L along the two outer edges, so
		// the buttons and the bar's own drag keep the rest.
		window_children << resize_grip(window.id_resize_nw, 0, 0, grip, edge, ui2.cursor_resize_nwse)
		window_children << resize_grip(window.id_resize_nw, 0, 0, edge, grip, ui2.cursor_resize_nwse)
		window_children << resize_grip(window.id_resize_ne, right, 0, grip, edge, ui2.cursor_resize_nesw)
		window_children << resize_grip(window.id_resize_ne, window.width - edge, 0, edge, grip,
			ui2.cursor_resize_nesw)
	}
	// `focused` tells the renderer which window's controls are drawn as the
	// key window's.
	return ui2.Element{
		...ui2.view(window.id_frame, window.frame_rect(), ui2.BoxStyle{
			bg:     background
			radius: theme.window_radius
		}, window_children)
		focused: active
	}
}

// resize_grip is one invisible, draggable part of an edge or corner target.
fn resize_grip(id string, x int, y int, width int, height int, cursor string) ui2.Element {
	return ui2.draggable_view_with_cursor(id, ui2.rect(f64(x), f64(y), f64(width), f64(height)),
		ui2.BoxStyle{
			transparent: true
		}, cursor, frame_elements(0))
}

// window_resize_action recognizes the resize selectors of the window chrome.
fn window_resize_action(action string) bool {
	return action.starts_with('win.') && (action.ends_with('.resize')
		|| action.ends_with('.resize_sw') || action.ends_with('.resize_nw')
		|| action.ends_with('.resize_ne') || action.ends_with('.resize_n')
		|| action.ends_with('.resize_s') || action.ends_with('.resize_e')
		|| action.ends_with('.resize_w'))
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
	// V3 promotes this dispatch wrapper because the returned tree escapes.
	// Own the wrapper explicitly; the application and its strings stay in apps.
	mut app := &NativeApp(d.apps[window.app_index])
	defer { unsafe { free(app) } }
	if mut app is RemoteApp {
		app.tree_age_limited = d.paint_full
	}
	root := app.build(size) or {
		// An application that cannot lay itself out should say so in its own
		// window rather than take the desktop down with it.
		mut error_children := frame_elements(2)
		error_children << body_line(tr('wm.app_failed'), 18, 18, window.width - 36)
		error_children << muted_line(err.msg(), 18, 40, window.width - 36)
		return d.theme().window_body, error_children
	}
	return root.box.bg, root.children
}

// launch starts a native app process or queues an external application for the main
// loop to run after releasing the physical display and input devices.
fn (mut d Desktop) launch(factory AppFactory) {
	d.launch_with_timeout(factory, app_response_timeout_ms)
}

// launch_with_timeout keeps normal interactive launches responsive while
// allowing the boot path to tolerate cold persistent storage.
fn (mut d Desktop) launch_with_timeout(factory AppFactory, timeout_ms int) {
	factory_index := shortcut_app_index_named(factory.process_name)
	if factory.exclusive_command != '' {
		d.pending_external = factory.exclusive_command
		d.pending_external_title = factory.title
		d.pending_external_icon = factory.icon
		d.record_recent_program_in(d.home, factory_index)
		d.dirty = true
		return
	}
	if (factory.open == unsafe { nil } && !factory.standalone) || factory.process_name == '' {
		eprintln('vinix-desktop: ${factory.title} has no launcher')
		return
	}
	if factory.install_package != '' && !native_app_installed(factory) {
		d.show_app_not_installed(factory)
		return
	}
	// The process and everything it starts can report taskbar progress
	// through this file; see taskbar_status.v.
	status_path := d.next_taskbar_status_path()
	d.pending_status_path = status_path
	app := start_remote_app_with_timeout(factory, mut d, timeout_ms) or {
		d.pending_status_path = ''
		if status_path.len > 0 {
			unsafe { status_path.free() }
		}
		eprintln('vinix-desktop: cannot start ${factory.title}: ${err}')
		return
	}
	d.pending_status_path = ''
	d.record_recent_program_in(d.home, factory_index)
	if factory.install_package != '' {
		// The icon was looked up, and found missing, before pkg installed it.
		if cached := d.native_asset_icons[factory.icon] {
			if cached.width == 0 {
				d.native_asset_icons.delete(factory.icon)
			}
		}
	}
	d.apps << app
	// Most windows cascade. Games that leave the centred wallpaper logo visible
	// open against the right edge with the same small margin as the top edge.
	step := ((d.next_id - 1) % 6) * 26
	x := if factory.launch_top_right { d.canvas.width - factory.width - 24 } else { 120 + step }
	y := if factory.launch_top_right { 24 } else { 60 + step }
	id := d.spawn(factory.title, .app, x, y, factory.width, factory.height)
	index := d.window_index(id) or { return }
	d.windows[index].app_index = d.apps.len - 1
	d.windows[index].factory_index = factory_index
	d.windows[index].status_path = status_path
	d.windows[index].icon = factory.icon
	d.windows[index].hide_body_cursor = factory.hide_body_cursor
	d.clamp_to_screen(index)
}

// external_finished restores the native desktop after an exclusive program.
// Successful exits need only a redraw. Failures get a visible window because
// the console log is hidden as soon as the compositor takes the display back.
fn (mut d Desktop) external_finished(result ExternalProgramResult) {
	d.buttons = 0
	d.drag = Drag{}
	d.set_hover('')
	d.wallpaper_valid = false
	d.dirty = true
	title := if d.pending_external_title == '' {
		external_app_title
	} else {
		d.pending_external_title
	}
	icon := if d.pending_external_icon == '' { 'builtin:window' } else { d.pending_external_icon }
	d.pending_external_title = ''
	d.pending_external_icon = ''
	if result == .success {
		return
	}
	d.external_error_app = title
	d.external_error_result = result
	d.external_error_missing = false
	d.compose_external_error()
	id := d.spawn(title, .external_error, 180, 120, 560, 220)
	index := d.window_index(id) or { return }
	d.windows[index].icon = icon
	d.clamp_to_screen(index)
}

// The title of an external-error window when the program had none.
const external_app_title = 'External application'

// compose_external_error writes the external-error window's text in the
// desktop's language, from what it reports.
fn (mut d Desktop) compose_external_error() {
	title := app_title_text(d.external_error_app)
	if d.external_error_missing {
		d.external_error_title = tr_fill('wm.not_installed.title', title)
		d.external_error = tr_fill('wm.not_installed.command', d.external_error_package)
		d.external_error_note = tr('wm.not_installed.note')
		d.external_error_hint = tr('wm.not_installed.hint')
		return
	}
	d.external_error = match d.external_error_result {
		.unavailable { tr_fill('wm.external.unavailable', title) }
		.spawn_failed { tr_fill('wm.external.spawn_failed', title) }
		.wait_failed { tr_fill('wm.external.wait_failed', title) }
		.failed { tr_fill('wm.external.failed', title) }
		.success { '' }
	}
	d.external_error_title = tr_fill('wm.external.title', title)
	d.external_error_note = tr_fill('wm.external.note', title)
	d.external_error_hint = tr('wm.external.hint')
}

fn native_app_installed(factory AppFactory) bool {
	path := native_app_directory + factory.process_name
	defer { unsafe { path.free() } }
	return C.access(&char(path.str), C.X_OK) == 0
}

// show_app_not_installed answers a shortcut for an optional app with a window
// naming its package, instead of a launch that fails without any feedback.
fn (mut d Desktop) show_app_not_installed(factory AppFactory) {
	d.external_error_app = factory.title
	d.external_error_package = factory.install_package
	d.external_error_missing = true
	d.compose_external_error()
	id := d.spawn(factory.title, .external_error, 180, 120, 560, 220)
	index := d.window_index(id) or { return }
	d.windows[index].icon = factory.icon
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
	for index in 0 .. d.windows.len {
		app_index := d.windows[index].app_index
		if app_index < 0 || app_index >= d.apps.len {
			continue
		}
		mut app := d.apps[app_index]
		if mut app is PollingApp {
			// A minimised window still has to be polled — a shell pipe has to
			// be drained whether or not anyone can see it — but recomposing
			// the screen for a picture nobody is looking at is pure waste. A
			// visible one only needs its own window repainted.
			mut poller := PollingApp(app)
			if poller.poll() {
				d.damage_window(index)
			}
		}
	}
}

// The event-driven idle wait needs a timeout only for work that cannot signal
// a descriptor. Most desktops therefore wake once a second for their clock;
// opening a stopwatch or a continuously hosted framebuffer lowers the timeout
// to that application's requested cadence.
fn (d &Desktop) idle_wait_interval(maximum i64, frame_interval i64) i64 {
	if d.clipboard.pid > 0 {
		return frame_interval
	}
	mut interval := d.keyboard_hud_wait(maximum)
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
			// The next poll is due an interval after the last one. The caller
			// takes this pass's own time off the wait, so aim a few
			// milliseconds past the due time: waking just before it would cost
			// a pass that finds the poll not yet due.
			mut candidate := i64(app.next_poll_interval())
			now := desktop_monotonic_ms()
			if app.last_poll_ms != 0 && now != ~u64(0) && now >= app.last_poll_ms {
				since := i64(now - app.last_poll_ms)
				candidate = if since < candidate { candidate - since + poll_wake_margin_ms } else { 1 }
			}
			if candidate < interval {
				interval = candidate
			}
		}
	}
	return interval
}

const poll_wake_margin_ms = i64(4)

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
		mut keyboard := KeyboardApp(app)
		keyboard.key_input(keys)
		d.dirty = true
	}
}

// End the session, and take the machine with it when this compositor owns the
// supervised system session. Started from a shell on the full image it is an
// ordinary process that happens to own the screen: there, ending the session
// means giving the console back to that shell and nothing more.
fn (mut d Desktop) end_session(action PowerAction) {
	// Ask every live client before closing any transport. A failed save keeps
	// the session running and brings its draft back into view.
	for index in 0 .. d.apps.len {
		mut app := d.apps[index]
		if !native_app_prepare_close(mut app) {
			for window in d.windows {
				if window.app_index == index { d.activate(window.id) break }
			}
			d.dirty = true
			return
		}
	}
	if desktop_is_system_session() {
		d.power = action
	}
	d.running = false
}

// The Start menu's power button.
fn (mut d Desktop) request_power_off() {
	d.end_session(.power_off)
}

// A supervisor signal ends the session at a frame boundary, so applications
// are closed and the console is restored before reload or machine powerdown.
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
	d.preview_cache.clear()
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

// launch_titled_at_startup is only for applications requested as the desktop
// comes up. It prevents a cold Files directory scan from being mistaken for a
// hung application and killed after the normal interactive timeout.
fn (mut d Desktop) launch_titled_at_startup(title string) {
	for factory in available_apps {
		if factory.title == title {
			d.launch_with_timeout(factory, app_startup_response_timeout_ms)
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
		if window.workspace != d.current_workspace || window.minimized || window.app_index < 0
			|| window.app_index >= d.apps.len {
			continue
		}
		if x < window.x || y < window.y || x >= window.x + window.width
			|| y >= window.y + window.height {
			continue
		}
		if window.title == 'Files' && action == files_action_settings {
			d.open_files_settings_window()
			return
		}
		if window.title == files_settings_window_title && action == files_settings_close {
			d.close_window(window.id)
			d.refresh_files_settings_clients(window.app_index)
			return
		}
		d.apps[window.app_index].handle(action) or {
			eprintln('vinix-desktop: ${window.title}: ${err}')
		}
		d.raise(window.id)
		if window.title == files_settings_window_title || action.starts_with(files_picker_toggle_prefix) {
			d.refresh_files_settings_clients(window.app_index)
		}
		// Capture the desktop, not the Capture window. The compositor will wait
		// until it has presented a frame with this window hidden before writing
		// the first pixel. Its taskbar entry remains the way back to Stop.
		if window.title == capture_app_title
			&& (action == capture_action_take_screenshot || action == capture_action_start_video) {
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
	return d.forward_pointer_to_window(x, y, phase, button, scroll) >= 0
}

// forward_pointer_to_window delivers a pointer event to the application under
// it and returns the index of that application's window, or -1 when no
// application took it.
fn (mut d Desktop) forward_pointer_to_window(x int, y int, phase AppPointerPhase, button AppPointerButton, scroll int) int {
	mut selected := -1
	if d.pointer_capture != 0 {
		selected = d.window_index(d.pointer_capture) or { -1 }
	} else {
		for i := d.windows.len - 1; i >= 0; i-- {
			window := &d.windows[i]
			body_top := window.y + d.theme().title_height
			if window.workspace == d.current_workspace && !window.minimized
				&& window.app_index >= 0 && x >= window.x
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
		return -1
	}
	window := &d.windows[selected]
	if window.app_index < 0 || window.app_index >= d.apps.len {
		return -1
	}
	mut app := d.apps[window.app_index]
	if mut app is PointerApp {
		if !app.pointer_input_enabled() {
			return -1
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
			&& d.buttons & (button_left | button_right | button_middle | button_back) == 0 {
			d.pointer_capture = 0
		}
		return selected
	}
	return -1
}

// app_pointer_changed reports whether the pointer event just delivered to the
// window's application could have changed what it shows.
fn (d &Desktop) app_pointer_changed(window_index int) bool {
	app_index := d.windows[window_index].app_index
	if app_index < 0 || app_index >= d.apps.len {
		return true
	}
	app := d.apps[app_index]
	if app is RemoteApp {
		return app.pointer_changed
	}
	return true
}

// shortcut_elements lays the application shortcuts down the left edge of the
// wallpaper, where windows are least likely to sit on top of them. Each is a
// transparent view that only shows a panel while the pointer is on it, so an
// idle desktop is just the wallpaper and its icons.
fn (d &Desktop) shortcut_elements() []ui2.Element {
	mut out := frame_elements(available_apps.len)
	rows := shortcut_rows_for_height(d.canvas.height)
	for slot in 0 .. available_apps.len {
		app_index := d.shortcut_app_at_slot(slot)
		if app_index < 0 {
			continue
		}
		factory := &available_apps[app_index]
		id := app_shortcut_actions[app_index]
		theme := d.theme()
		hovered := d.hover == id
		dragging := d.shortcut_press.dragging && d.shortcut_press.app_index == app_index
		column := slot / rows
		row := slot % rows
		x := shortcut_left + column * (shortcut_width + shortcut_gap)
		y := shortcut_top + row * (shortcut_height + shortcut_gap)
		icon_x := (shortcut_width - shortcut_icon) / 2
		mut shortcut_children := frame_elements(2)
		shortcut_children << ui2.button_with_image('', '', factory.icon, ui2.rect(f64(icon_x), 10, f64(shortcut_icon), f64(shortcut_icon)), ui2.BoxStyle{
			transparent: true
		}, ui2.TextStyle{
			color: if hovered || dragging { theme.shortcut_hover } else { theme.shortcut_label }
		})
		shortcut_children << ui2.label('', app_title_text(factory.title), ui2.rect(0, f64(shortcut_icon + 16), f64(shortcut_width), 18), ui2.TextStyle{
			color:  if hovered || dragging { theme.shortcut_hover } else { theme.shortcut_label }
			shadow: true
			size:   12
			align:  .center
		})
		out << ui2.clickable_view(id, ui2.rect(f64(x), f64(y), f64(shortcut_width), f64(shortcut_height)), ui2.BoxStyle{
			bg:          theme.shortcut_panel
			radius:      8
			transparent: !hovered && !dragging
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

// desktop_owns recognizes compositor selector names after origin has been
// checked. A matching name supplied by an application remains its own action.
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
	is_close := glyph == 'builtin:close' || glyph == 'builtin:traffic_close'

	if theme.button_look == .traffic {
		// A disc: coloured when the window is focused, grey when it is not, and
		// carrying its glyph only while the pointer is over the set. Radius is
		// half the size, which is how a rounded rect becomes a circle.
		is_minimize := glyph == 'builtin:minimize' || glyph == 'builtin:traffic_minimize'
		fill := if !active {
			theme.traffic_idle
		} else if is_close {
			theme.traffic_close
		} else if is_minimize {
			theme.traffic_minimize
		} else {
			theme.traffic_zoom
		}
		edge := if !active {
			theme.traffic_idle_edge
		} else if is_close {
			theme.traffic_close_edge
		} else if is_minimize {
			theme.traffic_minimize_edge
		} else {
			theme.traffic_zoom_edge
		}
		glyph_color := if is_close {
			theme.traffic_close_glyph
		} else if is_minimize {
			theme.traffic_minimize_glyph
		} else {
			theme.traffic_zoom_glyph
		}
		return ui2.button_with_image(id, '', if set_hovered { glyph } else { '' }, ui2.rect(f64(x), f64(y), f64(theme.button_size), f64(theme.button_size)), ui2.BoxStyle{
			bg:            fill
			radius:        theme.button_size / 2
			border_color:  edge
			border_left:   1
			border_top:    1
			border_right:  1
			border_bottom: 1
		}, ui2.TextStyle{
			color: glyph_color
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
		bg:          bg
		radius:      5
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
	icon_only := theme.taskbar_icon_only
	edge_padding := if dock { theme.dock_padding } else { taskbar_padding }

	// Pinned apps stay here after closing. Other apps appear while open:
	// `standard` gives every window an entry, while `combined` groups them.
	entries := d.taskbar_entries()
	defer {
		unsafe { entries.free() }
	}
	mut children := frame_elements(3 * entries.len + workspace_count + tray_item_count + 10)
	item_height := if icon_only { taskbar_icon_item_height } else { taskbar_item_height }
	item_y := (taskbar_height - item_height) / 2

	// The Start orb is the taskbar's anchor. Its standalone V is the first
	// letterform of the wallpaper wordmark, not a font-dependent character.
	children << ui2.button_with_image(action_start_toggle, '', 'builtin:vinix', ui2.rect(f64(edge_padding), f64(item_y), f64(start_button_width), f64(item_height)), ui2.BoxStyle{
		bg:     if d.start_menu_open || d.hover == action_start_toggle {
			theme.accent
		} else {
			theme.accent_dim
		}
		radius: item_height / 2
	}, ui2.TextStyle{
		color: theme.taskbar_text_active
	})
	children << ui2.button_with_image(action_window_overview, '', 'builtin:overview',
		ui2.rect(f64(edge_padding + start_button_width + 8), f64(item_y),
			f64(window_overview_button_width), f64(item_height)), ui2.BoxStyle{
		bg: if d.overview.active || d.hover == action_window_overview {
			theme.taskbar_item_hover
		} else {
			theme.taskbar_item_bg
		}
		radius: 5
	}, ui2.TextStyle{ color: theme.taskbar_text_active })

	layout := d.taskbar_layout(entries.len)
	entries_left := layout.entries_left
	entry_right := layout.entries_right
	item_width := layout.item_width
	workspace_x_fixed := layout.workspace_x
	status_right := layout.status_right
	status_width := layout.status_width
	tray_span := layout.tray_span
	workspace_width := layout.workspace_width
	clock_width := taskbar_clock_width
	build_width := taskbar_build_width
	show_desktop_width := if dock { 0 } else { taskbar_show_desktop_width }
	mut x := entries_left

	// A dragged button follows the pointer. Its slot stays reserved, so the
	// other buttons only move when the drag actually crosses one of them.
	mut dragged := -1
	for index, entry in entries {
		if x + item_width > entry_right {
			break
		}
		if d.taskbar_press.dragging && entry.key == d.taskbar_press.key {
			dragged = index
		} else {
			d.taskbar_entry_elements(mut children, entry, x, item_y, item_width, item_height,
				icon_only, false)
		}
		x += item_width + taskbar_item_gap
	}
	if dragged >= 0 {
		mut drag_x := d.pointer_x - d.taskbar_press.grab_offset
		if drag_x > x - taskbar_item_gap - item_width {
			drag_x = x - taskbar_item_gap - item_width
		}
		if drag_x < entries_left {
			drag_x = entries_left
		}
		d.taskbar_entry_elements(mut children, entries[dragged], drag_x, item_y, item_width,
			item_height, icon_only, true)
	}

	// A compact pager makes workspaces discoverable without opening an
	// overview. Numbered buttons match the Super+1..4 shortcuts and dim empty
	// workspaces while keeping every destination clickable.
	workspace_x := if dock { x } else { workspace_x_fixed }
	for workspace in 0 .. workspace_count {
		id := workspace_action_ids[workspace]
		active := workspace == d.current_workspace
		occupied := d.workspace_window_count(workspace) > 0
		children << ui2.button(id, workspace_labels[workspace], ui2.rect(f64(workspace_x +
			workspace * (workspace_button_width + workspace_button_gap)), f64(item_y),
			f64(workspace_button_width), f64(item_height)), ui2.BoxStyle{
			bg:     if active {
				theme.accent
			} else if d.hover == id {
				theme.taskbar_item_hover
			} else {
				theme.taskbar_item_bg
			}
			radius: 5
		}, ui2.TextStyle{
			color: if active || occupied { theme.taskbar_text_active } else { theme.taskbar_muted }
			size:  12
			bold:  active
			align: .center
		})
	}
	if dock {
		x = workspace_x + workspace_width + taskbar_item_gap
	}

	// The notification area sits left of the build date, then the build date
	// immediately left of the live clock, as the Windows 7 tray did. The input
	// source goes right up against the time, in the room its box leaves free.
	tray_x := if dock { x } else { status_right - status_width }
	d.tray_elements(mut children, tray_x, item_y, item_height)
	build_x := tray_x + tray_span
	clock_x := build_x + build_width + taskbar_item_gap + d.input_menu_span()
	if d.input_menu_shown() {
		children << d.input_menu_button(clock_x + clock_width - d.clock_text_width() -
			taskbar_item_gap - tray_input_width, item_y, item_height)
	}
	children << ui2.label('build.time', d.taskbar_build_time, ui2.rect(f64(build_x), 3, f64(build_width), 21), ui2.TextStyle{
		color: theme.taskbar_text_active
		size:  15
		bold:  true
		align: .right
	})
	children << ui2.label('build.date', d.taskbar_build_date, ui2.rect(f64(build_x), 25, f64(build_width), 17), ui2.TextStyle{
		color: theme.taskbar_muted
		size:  11
		align: .right
	})
	children << ui2.label('clock.time', d.taskbar_clock_time, ui2.rect(f64(clock_x), 3, f64(clock_width), 21), ui2.TextStyle{
		color: theme.taskbar_text_active
		size:  taskbar_clock_time_size
		bold:  true
		align: .right
	})
	children << ui2.label('clock.date', d.taskbar_clock_date, ui2.rect(f64(clock_x), 25, f64(clock_width), 17), ui2.TextStyle{
		color: theme.taskbar_muted
		size:  taskbar_clock_date_size
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
		// Show Desktop fills the lower-right corner, where a pointer pushed
		// against both edges always lands on it.
		children << ui2.button(action_show_desktop, '', ui2.rect(f64(width - show_desktop_width), 1,
			f64(show_desktop_width), f64(taskbar_height - 1)), ui2.BoxStyle{
			bg: if d.hover == action_show_desktop || d.show_desktop.active {
				theme.taskbar_item_hover
			} else {
				theme.taskbar_item_bg
			}
		}, ui2.TextStyle{})
	}

	if dock {
		panel_width := x - taskbar_item_gap + theme.dock_padding
		panel_x := (width - panel_width) / 2
		// Clear of the bottom edge, the way a dock sits.
		panel_y := d.canvas.height - taskbar_height - dock_bottom_gap
		return ui2.view('taskbar', ui2.rect(f64(panel_x), f64(panel_y), f64(panel_width), f64(taskbar_height)), ui2.BoxStyle{
			bg:     theme.dock_bg
			radius: theme.dock_radius
		}, children)
	}

	return ui2.view('taskbar', ui2.rect(0, f64(d.canvas.height - taskbar_height), f64(width), f64(taskbar_height)), ui2.BoxStyle{
		bg: theme.taskbar_bg
	}, children)
}

// TaskbarLayout is where the bar's parts go, in the taskbar's coordinates.
// Drawing and dragging share it, so a dragged button lands in the slot that is
// actually drawn under the pointer.
struct TaskbarLayout {
	entries_left    int
	entries_right   int
	item_width      int
	workspace_x     int
	workspace_width int
	status_right    int
	status_width    int
	tray_span       int
}

fn (d &Desktop) taskbar_layout(entry_count int) TaskbarLayout {
	theme := d.theme()
	dock := theme.dock
	edge_padding := if dock { theme.dock_padding } else { taskbar_padding }
	entries_left := edge_padding + start_button_width + 8 + window_overview_button_width + taskbar_item_gap
	// Reserve the status area before sizing entries. The clock therefore stays
	// in the physical lower-right corner, just inside Show Desktop, after 2x M1
	// presentation as well as on an unscaled framebuffer.
	tray_width := d.tray_width()
	tray_span := if tray_width > 0 { tray_width + taskbar_item_gap } else { 0 }
	status_width := tray_span + taskbar_build_width + taskbar_item_gap + d.input_menu_span() +
		taskbar_clock_width
	status_right := if dock {
		0
	} else {
		d.canvas.width - taskbar_show_desktop_width - taskbar_item_gap
	}
	workspace_width := workspace_count * workspace_button_width +
		(workspace_count - 1) * workspace_button_gap
	workspace_x := status_right - status_width - taskbar_item_gap - workspace_width
	entries_right := if dock { d.canvas.width } else { workspace_x - taskbar_item_gap }
	// Entries share whatever room is left rather than each taking a fixed
	// slot: with a fixed one the last window opened simply had no entry, which
	// is the opposite of what a list of open windows is for.
	return TaskbarLayout{
		entries_left:    entries_left
		entries_right:   entries_right
		item_width:      d.taskbar_item_width(entry_count, entries_left, entries_right)
		workspace_x:     workspace_x
		workspace_width: workspace_width
		status_right:    status_right
		status_width:    status_width
		tray_span:       tray_span
	}
}

fn (d &Desktop) taskbar_item_width(count int, left int, right int) int {
	theme := d.theme()
	mut item_width := if theme.dock {
		dock_item_width
	} else if theme.taskbar_icon_only {
		taskbar_icon_item_width
	} else {
		taskbar_item_width
	}
	item_min_width := if theme.taskbar_icon_only {
		taskbar_icon_item_min_width
	} else {
		taskbar_item_min_width
	}
	if count > 0 {
		share := (right - left + taskbar_item_gap) / count - taskbar_item_gap
		if share < item_width {
			item_width = share
		}
		if item_width < item_min_width {
			item_width = item_min_width
		}
	}
	return item_width
}

// taskbar_entry_elements appends one button, then its progress and badge
// overlays, which paint over the button and are not themselves clickable.
fn (d &Desktop) taskbar_entry_elements(mut children []ui2.Element, entry TaskbarEntry, x int, y int,
	width int, height int, icon_only bool, dragging bool) {
	theme := d.theme()
	bg := if entry.status.attention && !entry.active {
		taskbar_attention_bg
	} else if entry.active {
		theme.taskbar_item_active
	} else if dragging || d.hover == entry.id {
		theme.taskbar_item_hover
	} else {
		theme.taskbar_item_bg
	}
	// A minimised window is dimmed rather than marked with a character:
	// the baked faces are ASCII, so a nice bullet would come out blank.
	text_color := if entry.active || entry.status.attention {
		theme.taskbar_text_active
	} else if entry.minimized {
		theme.taskbar_muted
	} else {
		theme.taskbar_text
	}
	radius := if icon_only { 4 } else { 6 }
	button_frame := ui2.rect(f64(x), f64(y), f64(width), f64(height))
	button_style := ui2.BoxStyle{
		bg:     bg
		radius: radius
	}
	if icon_only {
		// An icon consumes the full button when it has no label, making an
		// app identifiable at a glance without stealing room from the clock.
		icon := if entry.icon == 'asset:calendar' {
			'builtin:calendar_today'
		} else {
			entry.icon
		}
		children << ui2.button_with_image(entry.id, '', icon, button_frame, button_style, ui2.TextStyle{
			color: text_color
		})
	} else {
		children << ui2.button(entry.id, entry.label, button_frame, button_style, ui2.TextStyle{
			color: text_color
			size:  12
			align: .left
		})
	}
	d.taskbar_status_elements(mut children, entry.status, x, y, width, height, radius)
}

// TaskbarEntry is one button in the middle of the bar. A pinned app keeps its
// own action id when closed; an open window uses its task action id.
struct TaskbarEntry {
	id        string
	label     string
	icon      string
	active    bool
	minimized bool
	app_index int = -1
	window_id int
	// What the button stands for, independently of which of its windows is on
	// top: the pin's action, a window's task id, or a combined group's title.
	// Hover previews and drags follow the key while the action id changes.
	key          string
	pinned       bool
	window_count int
	// The most significant progress, badge and attention of its windows.
	status TaskStatus
}

fn (d &Desktop) taskbar_entries() []TaskbarEntry {
	mut out := []TaskbarEntry{cap: d.windows.len + d.pinned_apps.len}
	unsafe { out.flags |= .noslices }
	for index in d.pinned_apps {
		if index < 0 || index >= available_apps.len || index >= taskbar_pin_actions.len {
			continue
		}
		window_id := d.taskbar_window_for_app(index)
		mut active := false
		mut minimized := false
		mut count := 0
		mut status := TaskStatus{}
		for window in d.windows {
			if window.factory_index != index {
				continue
			}
			count++
			status = merge_task_status(status, window.status, window.id == d.focus)
			if window.id == d.focus && !window.minimized {
				active = true
			}
		}
		if window_id != 0 {
			window_index := d.window_index(window_id) or { -1 }
			if window_index >= 0 {
				minimized = d.windows[window_index].minimized
			}
		}
		out << TaskbarEntry{
			id:           taskbar_pin_actions[index]
			label:        app_title_text(available_apps[index].title)
			icon:         available_apps[index].icon
			active:       active
			minimized:    minimized
			app_index:    index
			window_id:    window_id
			key:          taskbar_pin_actions[index]
			pinned:       true
			window_count: count
			status:       status
		}
	}
	if d.settings.taskbar_mode == .standard {
		mut last_rank := min_i32_rank
		for {
			index := d.next_window_by_task_rank(last_rank) or { break }
			window := &d.windows[index]
			last_rank = window.task_rank
			if d.taskbar_is_pinned(window.factory_index) {
				continue
			}
			out << TaskbarEntry{
				id:           window.id_task
				label:        app_title_text(window.title)
				icon:         window.icon
				active:       window.id == d.focus && !window.minimized
				minimized:    window.minimized
				app_index:    window.factory_index
				window_id:    window.id
				key:          window.id_task
				window_count: 1
				status:       merge_task_status(TaskStatus{}, window.status, window.id == d.focus)
			}
		}
		return out
	}

	// Combined: one entry per title, labelled with how many windows share it,
	// in the order of each group's first button. Clicking it activates the most
	// recently raised of them, which is what makes a second click minimise the
	// one you just brought up.
	mut seen := []string{cap: d.windows.len}
	unsafe { seen.flags |= .noslices }
	mut last_rank := min_i32_rank
	for {
		window_index := d.next_window_by_task_rank(last_rank) or { break }
		window := &d.windows[window_index]
		last_rank = window.task_rank
		if d.taskbar_is_pinned(window.factory_index) {
			continue
		}
		if window.title in seen {
			continue
		}
		seen << window.title
		mut count := 0
		mut newest_index := window_index
		mut active := false
		mut all_minimized := true
		mut status := TaskStatus{}
		for other in d.windows {
			if other.workspace != d.current_workspace || other.title != window.title
				|| d.taskbar_is_pinned(other.factory_index) {
				continue
			}
			count++
			status = merge_task_status(status, other.status, other.id == d.focus)
			if other.id == d.focus && !other.minimized {
				active = true
			}
			if !other.minimized {
				all_minimized = false
			}
		}
		// The last in painting order is the one on top.
		for i := d.windows.len - 1; i >= 0; i-- {
			if d.windows[i].workspace == d.current_workspace
				&& d.windows[i].title == window.title
				&& !d.taskbar_is_pinned(d.windows[i].factory_index) {
				newest_index = i
				break
			}
		}
		out << TaskbarEntry{
			id:           d.windows[newest_index].id_task
			label:        if count > 1 {
				d.taskbar_group_label(window.title, count)
			} else {
				app_title_text(window.title)
			}
			icon:         d.windows[newest_index].icon
			active:       active
			minimized:    all_minimized
			app_index:    d.windows[newest_index].factory_index
			window_id:    d.windows[newest_index].id
			key:          window.title
			window_count: count
			status:       status
		}
	}
	unsafe { seen.free() }
	return out
}

// Combined labels such as `Terminal  (2)` are built once per title, count and
// language, rather than on every rebuild, because nothing collects them here.
fn (d &Desktop) taskbar_group_label(title string, count int) string {
	for label in taskbar_group_labels {
		if label.count == count && label.language == desktop_language && label.title == title {
			return label.text
		}
	}
	number := count.str()
	text := tr_fill2('wm.taskbar.group', app_title_text(title), number)
	unsafe { number.free() }
	taskbar_group_labels << TaskbarGroupLabel{
		title:    title.clone()
		count:    count
		language: desktop_language
		text:     text
	}
	return text
}

struct TaskbarGroupLabel {
	title    string
	count    int
	language DesktopLanguage
	text     string
}

__global taskbar_group_labels = []TaskbarGroupLabel{}

const min_i32_rank = -2147483647

// next_window_by_task_rank walks the current workspace's windows in taskbar
// order. The window list is kept in painting order, which changes whenever one
// is raised; ranks only change when a button is dragged, so repeatedly taking
// the smallest rank above the last one gives a stable order without building a
// sorted copy every frame.
fn (d &Desktop) next_window_by_task_rank(after_rank int) ?int {
	mut found := -1
	for i, window in d.windows {
		if window.workspace != d.current_workspace || window.task_rank <= after_rank {
			continue
		}
		if found < 0 || window.task_rank < d.windows[found].task_rank {
			found = i
		}
	}
	if found < 0 {
		return none
	}
	return found
}

fn (d &Desktop) taskbar_entry_for_action(action string) ?TaskbarEntry {
	entries := d.taskbar_entries()
	defer { unsafe { entries.free() } }
	for entry in entries {
		if entry.id == action {
			return entry
		}
	}
	return none
}

// ── Pointer handling ───────────────────────────────────────────────

fn (mut d Desktop) on_pointer_move(x int, y int) {
	d.pointer_moved_only = false
	pointer_moved := x != d.pointer_x || y != d.pointer_y
	old_pointer_x := d.pointer_x
	old_pointer_y := d.pointer_y
	was_dirty := d.dirty
	if pointer_moved {
		d.dirty = true
	}
	d.pointer_x = x
	d.pointer_y = y
	if d.window_overlay_active() {
		d.set_hover(d.hit_action(x, y))
		return
	}
	if d.drag.kind == .move && pointer_moved {
		d.drag.moved = true
	}
	if d.drag.kind == .move && d.buttons & button_left != 0 {
		if pointer_moved && d.drag.shake.sample(x, y, monotonic_millis()) {
			d.toggle_window_isolation(d.drag.window_id)
		}
		d.update_window_placement(x, y)
	}

	if d.shortcut_press.app_index >= 0 && d.buttons & button_left != 0 {
		d.update_shortcut_drag(x, y)
		hover := d.hit_action(x, y)
		if hover != d.hover {
			d.set_hover(hover)
			d.dirty = true
		}
		return
	}
	if d.taskbar_press.active && d.buttons & button_left != 0 {
		d.update_taskbar_drag(x, y)
		return
	}

	// The button level, not just the release edge, ends a drag. The driver
	// reports the current state on every read, so a release that was missed
	// between two frames cannot leave a window stuck to the cursor.
	if d.drag.kind != .none_ && d.buttons & button_left == 0 {
		if d.drag.kind == .move {
			d.finish_window_drag(x, y)
		} else if d.drag.kind == .resize {
			d.finish_window_resize()
		}
		d.drag = Drag{}
	}

	if d.drag.kind == .resize {
		d.resize_window_to_pointer(x, y)
		return
	}

	if d.drag.kind == .move {
		index := d.window_index(d.drag.window_id) or {
			d.drag = Drag{}
			return
		}
		// An arranged window that is dragged goes back to its own size, with
		// the grab kept proportionally along the title bar.
		if d.windows[index].maximized || d.windows[index].snap != .none_ {
			ratio := f64(d.drag.offset_x) / f64(d.windows[index].width)
			d.restore_window(d.drag.window_id)
			new_index := d.window_index(d.drag.window_id) or { return }
			d.drag.offset_x = int(ratio * f64(d.windows[new_index].width))
			d.drag.offset_y = d.theme().title_height / 2
		}
		moved := d.window_index(d.drag.window_id) or { return }
		old_x := d.windows[moved].x
		old_y := d.windows[moved].y
		d.windows[moved].x = x - d.drag.offset_x
		d.windows[moved].y = y - d.drag.offset_y
		d.clamp_drag_to_screen(moved)
		if pointer_moved {
			// Repaint the old location to reveal what was behind the window and
			// the new one to draw it again. The cursor is composed into the same
			// canvas, so both of its footprints need refreshing too.
			d.add_drag_damage(old_x, old_y, d.windows[moved].x, d.windows[moved].y,
				old_pointer_x, old_pointer_y, x, y, d.windows[moved].width,
				d.windows[moved].height)
		}
		if d.windows[moved].x != old_x || d.windows[moved].y != old_y {
			d.dirty = true
		}
		return
	}
	// The device reports its position on every read, moved or not. Only a
	// real move is news to an application, and each one is a round trip.
	mut delivered := -1
	if pointer_moved && !d.start_menu_open && !d.start_menu_pointer {
		delivered = d.forward_pointer_to_window(x, y, .move, .no_button, 0)
	}

	// What an ordinary move changes is local: the pointer's own picture, the
	// window of the application it was delivered to, and the two controls
	// the hover highlight left and reached. Those are repainted by themselves
	// (see frame_damage.v); anything else takes the whole frame.
	mut local := pointer_moved
	hover := d.hit_action(x, y)
	if hover != d.hover {
		local = local && d.damage_hover_change(d.hover, hover)
		d.set_hover(hover)
		d.update_start_menu_hover()
		d.dirty = true
	}
	if local {
		if delivered >= 0 && d.app_pointer_changed(delivered) {
			d.damage_window(delivered)
		}
		d.dirty = was_dirty
		d.pointer_moved_only = true
	}
}

// resize_window_to_pointer moves the grabbed edges while leaving the opposite
// edges and the untouched dimension fixed. The usable desktop bounds the growing
// edge, so a top edge never takes the title bar off the screen; a window
// already positioned too near an edge still retains the global minimum size.
fn (mut d Desktop) resize_window_to_pointer(x int, y int) {
	index := d.window_index(d.drag.window_id) or {
		d.drag = Drag{}
		return
	}
	dx := x - d.drag.start_pointer_x
	dy := y - d.drag.start_pointer_y
	right := d.drag.start_x + d.drag.start_width
	bottom := d.drag.start_y + d.drag.start_height
	mut width := if !d.drag.resize_horizontal {
		d.drag.start_width
	} else if d.drag.resize_left {
		d.drag.start_width - dx
	} else {
		d.drag.start_width + dx
	}
	mut height := if !d.drag.resize_vertical {
		d.drag.start_height
	} else if d.drag.resize_top {
		d.drag.start_height - dy
	} else {
		d.drag.start_height + dy
	}
	min_height := d.theme().title_height + window_min_body_height
	if d.drag.resize_horizontal && width < window_min_width {
		width = window_min_width
	}
	if d.drag.resize_vertical && height < min_height {
		height = min_height
	}
	max_width := if d.drag.resize_left { right } else { d.canvas.width - d.drag.start_x }
	max_height := if d.drag.resize_top {
		bottom
	} else {
		d.canvas.height - taskbar_height - d.drag.start_y
	}
	if d.drag.resize_horizontal && max_width >= window_min_width && width > max_width {
		width = max_width
	}
	if d.drag.resize_vertical && max_height >= min_height && height > max_height {
		height = max_height
	}
	new_x := if d.drag.resize_horizontal && d.drag.resize_left { right - width } else { d.drag.start_x }
	new_y := if d.drag.resize_vertical && d.drag.resize_top { bottom - height } else { d.drag.start_y }
	if width != d.windows[index].width || height != d.windows[index].height
		|| new_x != d.windows[index].x || new_y != d.windows[index].y {
		d.windows[index].x = new_x
		d.windows[index].y = new_y
		d.windows[index].width = width
		d.windows[index].height = height
		d.dirty = true
	}
}

fn (mut d Desktop) finish_window_resize() {
	if d.drag.kind != .resize {
		return
	}
	index := d.window_index(d.drag.window_id) or { return }
	d.remember_restore_frame(index)
}

// add_drag_damage includes the outside edge of the shadow and both cursor
// positions. Rendering clips it to the canvas, so edge coordinates may be
// negative here.
fn (mut d Desktop) add_drag_damage(old_x int, old_y int, new_x int, new_y int,
	old_pointer_x int, old_pointer_y int, pointer_x int, pointer_y int, width int, height int) {
	d.add_damage_rect(old_x - 7, old_y - 5, width + 14, height + 14)
	d.add_damage_rect(new_x - 7, new_y - 5, width + 14, height + 14)
	// The Catalina pointer includes a soft shadow to the right and below; this
	// rectangle also covers the default pointer's one-pixel halo.
	d.add_damage_rect(old_pointer_x - cursor_backing_inset, old_pointer_y - cursor_backing_inset,
		cursor_backing_width, cursor_backing_height)
	d.add_damage_rect(pointer_x - cursor_backing_inset, pointer_y - cursor_backing_inset,
		cursor_backing_width, cursor_backing_height)
}

fn (mut d Desktop) add_damage_rect(x int, y int, width int, height int) {
	d.drag_damage = damage_union(d.drag_damage, DamageRect{
		x:     x
		y:     y
		w:     width
		h:     height
		valid: true
	})
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

// clamp_drag_to_screen allows the frame to cross the side and bottom display
// edges while keeping a small, reachable piece of title bar on-screen. The
// stricter clamp_to_screen remains for initial window placement.
fn (mut d Desktop) clamp_drag_to_screen(index int) {
	mut reachable_width := 60
	if d.windows[index].width < reachable_width {
		reachable_width = d.windows[index].width
	}
	if d.canvas.width < reachable_width {
		reachable_width = d.canvas.width
	}
	max_x := d.canvas.width - reachable_width
	max_y := d.canvas.height - taskbar_height - d.theme().title_height
	if d.windows[index].x > max_x {
		d.windows[index].x = max_x
	}
	if d.windows[index].x + d.windows[index].width < reachable_width {
		d.windows[index].x = reachable_width - d.windows[index].width
	}
	if d.windows[index].y < 0 {
		d.windows[index].y = 0
	}
	if d.windows[index].y > max_y {
		d.windows[index].y = max_y
	}
}

fn (mut d Desktop) on_pointer_down(x int, y int) {
	// A fresh primary press supersedes any release that an earlier, incomplete
	// device report failed to deliver.
	d.chrome_pointer_capture = false
	d.clear_taskbar_press()
	action, world := d.hit_action_world(x, y)
	d.trace_selector(action, world)
	d.set_hover(action)
	d.dirty = true
	if d.window_actions.active && d.window_actions_pointer_down(action, world) {
		d.chrome_pointer_capture = true
		return
	}
	if d.snap_assist.active && d.window_snap_assist_pointer_down(action, world) {
		d.chrome_pointer_capture = true
		return
	}
	if d.overview.active && d.window_overview_pointer_down(action, world) {
		d.chrome_pointer_capture = true
		return
	}
	if d.window_layout.active {
		if world == .desktop && d.handle_window_layout_action(action) {
			d.chrome_pointer_capture = true
			return
		}
		d.close_window_layout()
		// Clicking away dismisses the chooser without clicking through it.
		d.chrome_pointer_capture = true
		return
	}

	if d.switcher.active {
		// A click on a tile switches to that window; a click anywhere else
		// dismisses the switcher and then means whatever it would have meant.
		if world == .desktop && action.starts_with(action_switch_prefix) {
			d.switcher_select(action[action_switch_prefix.len..].int())
			return
		}
		d.switcher_close()
	}

	// A flyout closes when anything outside it is pressed, and the press then
	// means what it would have meant.
	if d.tray.flyout != .none_ && !(world == .desktop && action.starts_with('tray.')) {
		d.close_tray_flyout()
	}
	if d.taskbar_preview.open && !(world == .desktop && (taskbar_entry_action(action)
		|| action == taskbar_preview_panel || action.starts_with(taskbar_preview_prefix))) {
		d.close_taskbar_preview()
	}

	if world == .desktop && action == action_start_toggle {
		d.start_menu_pointer = true
		d.toggle_start_menu()
		return
	}

	if d.start_menu_open {
		d.start_menu_pointer = true
		if world == .desktop && action.starts_with('start.') {
			d.handle_start_action(action)
			return
		}
		// Clicking anywhere outside the panel dismisses it, then performs the
		// action underneath, matching the Windows menu's click-away behavior.
		d.close_start_menu()
	}

	resizing_window := world == .desktop && window_resize_action(action)
	if !resizing_window && d.forward_pointer_to_app(x, y, .down, .left, 0) && action == '' {
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

	// The app world's star selector forwards arbitrary action ids to the app
	// under the pointer over its private RPC pipe. Their spelling never grants
	// access to desktop actions, including Start, window chrome and shortcuts.
	if world == .application {
		d.forward_to_app(x, y, action)
		return
	}

	if !desktop_owns(action) {
		d.forward_to_app(x, y, action)
		return
	}

	if action.starts_with(action_shortcut_prefix) {
		d.begin_shortcut_press(action, x, y)
		return
	}

	if action.starts_with(action_workspace_prefix) {
		d.switch_workspace(action[action_workspace_prefix.len..].int())
		return
	}
	if action == action_window_overview {
		d.toggle_window_overview()
		d.chrome_pointer_capture = true
		return
	}

	if taskbar_entry_action(action) {
		d.taskbar_entry_click(action, x, y)
		return
	}

	if action == taskbar_preview_panel {
		return
	}

	if action.starts_with(taskbar_preview_prefix) {
		d.handle_preview_action(action)
		return
	}

	if action == action_show_desktop {
		d.toggle_show_desktop()
		return
	}

	if action.starts_with('tray.') {
		d.handle_tray_action(action)
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
					kind:      .move
					window_id: id
					offset_x:  x - d.windows[index].x
					offset_y:  y - d.windows[index].y
					shake:     new_window_shake(x, y, monotonic_millis())
				}
				d.chrome_pointer_capture = true
				d.drag_damage = DamageRect{}
			}
			'resize', 'resize_sw', 'resize_nw', 'resize_ne', 'resize_n', 'resize_s', 'resize_e', 'resize_w' {
				index := d.window_index(id) or { return }
				if d.windows[index].maximized || d.windows[index].snap != .none_ {
					return
				}
				d.raise(id)
				resized := d.window_index(id) or { return }
				d.drag = Drag{
					kind:            .resize
					window_id:       id
					start_pointer_x: x
					start_pointer_y: y
					start_x:         d.windows[resized].x
					start_y:         d.windows[resized].y
					start_width:     d.windows[resized].width
					start_height:    d.windows[resized].height
					resize_left:     part == 'resize_sw' || part == 'resize_nw' || part == 'resize_w'
					resize_top:      part == 'resize_nw' || part == 'resize_ne' || part == 'resize_n'
					resize_horizontal: part != 'resize_n' && part != 'resize_s'
					resize_vertical: part != 'resize_w' && part != 'resize_e'
				}
				d.chrome_pointer_capture = true
				d.drag_damage = DamageRect{}
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

fn (d &Desktop) trace_selector(action string, world ActionWorld) {
	if !d.trace_selectors || action.len == 0 {
		return
	}
	// A remote app supplies its selector text. Keep control bytes and very long
	// strings out of the compositor log, while retaining readable selectors.
	mut printable := action.len <= 128
	for ch in action {
		if ch < 32 || ch > 126 {
			printable = false
			break
		}
	}
	if printable {
		eprintln('vinix-desktop: selector[${world}] ${action}')
	} else {
		eprintln('vinix-desktop: selector[${world}] <${action.len} bytes>')
	}
}

fn (mut d Desktop) on_pointer_up(x int, y int) {
	if d.window_overlay_active() {
		// A chooser opened from the keyboard can cancel a held app gesture
		// without receiving its press. Its release still belongs to the modal.
		d.chrome_pointer_capture = false
		d.pointer_capture = 0
		d.drag = Drag{}
		d.drag_damage = DamageRect{}
		return
	}
	action, world := d.hit_action_world(x, y)
	release_action := if world == .desktop { action } else { '' }
	if d.shortcut_press.app_index >= 0 {
		// Own the action before launch_index can replace application state that
		// supplied the current frame's hit targets.
		d.set_hover(release_action)
		if app_index := d.finish_shortcut_press(release_action, x, y) {
			d.launch_index(app_index)
		}
		d.drag = Drag{}
		d.drag_damage = DamageRect{}
		d.dirty = true
		return
	}
	if d.taskbar_press.active {
		d.set_hover(release_action)
		if app_index := d.finish_taskbar_press_in(d.home, release_action, x, y) {
			d.launch_index(app_index)
		}
		d.drag = Drag{}
		d.drag_damage = DamageRect{}
		d.dirty = true
		return
	}
	was_dragging := d.chrome_pointer_capture || d.drag.kind != .none_
	d.chrome_pointer_capture = false
	if d.start_menu_pointer {
		d.start_menu_pointer = false
	} else if !was_dragging {
		d.forward_pointer_to_app(x, y, .up, .left, 0)
	}
	if d.drag.kind == .move {
		d.finish_window_drag(x, y)
	} else if d.drag.kind == .resize {
		d.finish_window_resize()
	}
	d.drag = Drag{}
	d.drag_damage = DamageRect{}
	d.set_hover(release_action)
	d.dirty = true
}

// Finish the placement preview's half, quarter or maximize gesture.
fn (mut d Desktop) finish_window_drag(x int, y int) {
	id := d.drag.window_id
	d.finish_window_placement(x, y)
	if d.drag.moved {
		d.open_window_snap_assist(id)
	}
}

// Non-primary buttons and the wheel have no desktop chrome meaning yet, but a
// native pixel-surface client needs them for its own interaction model.
fn (mut d Desktop) on_app_pointer_button(x int, y int, phase AppPointerPhase, button AppPointerButton) {
	if d.window_overlay_active() {
		return
	}
	if d.switcher.active || d.start_menu_open {
		return
	}
	if d.forward_pointer_to_app(x, y, phase, button, 0) {
		d.dirty = true
	}
}

fn (mut d Desktop) on_app_pointer_scroll(x int, y int, scroll int) {
	if d.window_overlay_active() {
		return
	}
	if scroll == 0 || d.switcher.active || d.start_menu_open {
		return
	}
	if d.forward_pointer_to_app(x, y, .scroll, .no_button, scroll) {
		d.dirty = true
	}
}

// The render pass records each target's world alongside its selector. Keep
// that origin attached until dispatch; a string prefix cannot authenticate it.
fn (d &Desktop) hit_action_world(x int, y int) (string, ActionWorld) {
	for i := d.targets.len - 1; i >= 0; i-- {
		target := d.targets[i]
		if x >= target.x && y >= target.y && x < target.x + target.width
			&& y < target.y + target.height {
			return target.action_id, target.world
		}
	}
	return '', .desktop
}

fn (d &Desktop) hit_action(x int, y int) string {
	action, _ := d.hit_action_world(x, y)
	return action
}

// Hover outlives the frame that produced its hit target. Keep an owned copy:
// actions may come from an element tree or an array which is released or moved
// while an application is being launched.
fn (mut d Desktop) set_hover(action string) {
	if d.hover == action {
		return
	}
	if d.hover.len > 0 {
		unsafe { d.hover.free() }
	}
	d.hover = if action.len > 0 { action.clone() } else { '' }
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
