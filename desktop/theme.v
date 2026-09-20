// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// One place for every color and measurement the desktop draws with, so the
// look can be changed without going through the layout code.
module main

// ── Wallpaper ──────────────────────────────────────────────────────

// The default theme's title bar height, for sizing a window before its
// theme is known — an AppFactory declares a height in the abstract.
const default_title_height = 34

// The lower-right corner is window-manager chrome: it remains large enough to
// grab at either logical scale, while the frame cannot be collapsed past a
// useful title bar and a small application body.
const window_resize_grip_size = 18
const window_min_width = 180
const window_min_body_height = 96

// ── Windows ────────────────────────────────────────────────────────

// ── Window contents ────────────────────────────────────────────────
// ── Application interiors ──────────────────────────────────────────
// Declared custom controls do not follow the chrome's theme. A button that
// explicitly requests ui2's native style is the exception: the Catalina theme
// gives it the measured AppKit bezel below, just as AppKit does on macOS.
const app_surface = u32(0xfbfcfe)
const app_accent = u32(0x5b9cf8)
const app_on_accent = u32(0xffffff)

// Catalina's standard push button is a 21-pixel Aqua bezel. These scanlines
// were sampled from the installed 10.15.7 system in
// docs/catalina-reference/push-buttons-*.png. AppKit uses the blue default
// rendition for a selected choice and a darker blue rendition for every
// enabled button while the mouse is down; pointer hover alone changes nothing.
const catalina_button_height = 21
const catalina_button_radius = 5
const catalina_button_normal_outer = [u32(0xc9c9c9), 0xc6c6c6, 0xc5c5c5, 0xc4c4c4, 0xc3c3c3, 0xc3c3c3,
	0xc2c2c2, 0xc2c2c2, 0xc2c2c2, 0xc2c2c2, 0xc2c2c2, 0xc2c2c2, 0xc2c2c2, 0xc2c2c2, 0xc2c2c2, 0xc2c2c2,
	0xc3c3c3, 0xc2c2c2, 0xc2c2c2, 0xbfbfbf, 0xacacac]
const catalina_button_face = u32(0xffffff)
const catalina_button_text = u32(0x222222)
const catalina_button_disabled_edge = u32(0xd5d5d5)
const catalina_button_disabled_face = u32(0xf5f5f5)
const catalina_button_disabled_text = u32(0xa5a5a5)
const catalina_button_default_outer = [u32(0x4c8bfa), 0x4989fa, 0x4787fa, 0x4486fa, 0x4184fb, 0x3e81fb,
	0x3a7efb, 0x377cfc, 0x3279fc, 0x3077fd, 0x2b73fd, 0x2771fd, 0x236dfe, 0x1e6afe, 0x1b67fe, 0x1864fe,
	0x1563ff, 0x1260ff, 0x0f5dff, 0x0c5aff, 0x0858ff]
const catalina_button_default_inner = [u32(0x6ba0fb), 0x689efb, 0x649cfb, 0x6099fc, 0x5b96fc, 0x5592fc,
	0x508ffc, 0x4a8bfd, 0x4488fd, 0x3e84fd, 0x3980fe, 0x337cfe, 0x2d77fe, 0x2774fe, 0x2270ff, 0x1d6cff,
	0x196aff, 0x1466ff, 0x1164ff]
const catalina_button_pressed_outer = [u32(0x2670ff), 0x246efd, 0x236cfc, 0x226bfb, 0x216afa, 0x1f68f8,
	0x1e67f7, 0x1c64f5, 0x1961f2, 0x1860f1, 0x165def, 0x145aed, 0x1359ec, 0x1056e9, 0x0f54e7, 0x0c50e5,
	0x0b4fe4, 0x0950e2, 0x074de1, 0x064adf, 0x0448de]
const catalina_button_pressed_inner = [u32(0x4c8bfe), 0x4989fd, 0x4686fc, 0x4485fb, 0x4082fa, 0x3d80f9,
	0x397cf7, 0x3478f5, 0x3075f4, 0x2d72f2, 0x296ef1, 0x246aef, 0x2067ed, 0x1d65ec, 0x1961eb, 0x165ee9,
	0x125be8, 0x0f58e7, 0x0c55e5]

// Standard AppKit controls measured from the same Catalina installation. The
// blue is Catalina's system accent, not the lighter desktop application accent.
const catalina_control_text = u32(0x262626)
const catalina_control_disabled_text = u32(0xa7a7a7)
const catalina_control_edge = u32(0xaaaaaa)
const catalina_control_edge_dark = u32(0x8e8e8e)
const catalina_control_face = u32(0xffffff)
const catalina_control_pressed_face = u32(0xe5e5e5)
const catalina_control_accent = u32(0x3478f6)
const catalina_control_accent_pressed = u32(0x1f66dc)
const catalina_control_focus = u32(0x6aa7ff)
const catalina_checkbox_size = 14
const catalina_popup_height = 22
const catalina_text_input_height = 22
const catalina_slider_track = u32(0xc8c8c8)
const catalina_slider_track_edge = u32(0xb4b4b4)
const catalina_switch_on = u32(0x64c466)
const catalina_switch_off = u32(0xb8b8b8)

const body_text = u32(0x30394a)
const body_muted = u32(0x7b8698)
const body_heading = u32(0x141c2b)
const body_rule = u32(0xe8ebf0)
const body_panel = u32(0xf3f5f9)

// ── Battery ───────────────────────────────────────────────────────
const battery_level = u32(0x42a766)
const battery_graph_rule = u32(0xdde3e9)

// ── File browser ───────────────────────────────────────────────────
const files_up = u32(0x4a6fa5)
const files_up_disabled = u32(0xe7eaf0)
const files_row_hover = u32(0xeaf1fb)
const files_error = u32(0xc0392b)
const files_folder_icon = u32(0x5b8def)
const files_file_icon = u32(0x9aa5b5)

// ── Activity monitor ───────────────────────────────────────────────
// A long list of small numbers, so the stripe is barely there and only the
// figures worth acting on are given a colour.
const activity_row_alt = u32(0xf5f7fa)
const activity_sort_idle = u32(0xe9edf4)
const activity_busy = u32(0xc0632b)
// The share of one CPU at which a process is worth pointing at. Below this
// everything on an idle machine would be marked and the mark would say
// nothing.
const activity_busy_percent = 10.0

// ── Desktop utilities ─────────────────────────────────────────────
const editor_button = u32(0x4a6fa5)
const editor_path_focus = u32(0xdfeafb)
const editor_cursor = u32(0x2563a6)
const editor_modified = u32(0xb45f06)

const calendar_button = u32(0xe9edf4)
const calendar_today = u32(0xdfeafb)

const clock_stopwatch = u32(0x2563a6)
const clock_button = u32(0xe9edf4)
const clock_stop = u32(0xc94c4c)

// ── VSpace ─────────────────────────────────────────────────────────
// Two rankings sit side by side, so folders and files each get a colour and
// every proportion bar in a panel is drawn in its panel's own.
const vspace_folders_accent = u32(0xd08a24)
const vspace_files_accent = u32(0x7c5cd6)
const vspace_phase_scanning = u32(0x1d4ed8)
const vspace_phase_complete = u32(0x15803d)
const vspace_phase_stopped = u32(0xb45309)

// ── Settings ───────────────────────────────────────────────────────
// ── Terminal ───────────────────────────────────────────────────────
const terminal_bg = u32(0x1b1d23)
const terminal_text = u32(0xd8dee9)
const terminal_button = u32(0x333843)

const settings_sidebar_bg = u32(0xf3f5f9)
const settings_category_selected = u32(0xdfe7f5)
const settings_choice_bg = u32(0xe9edf4)

// ── Desktop shortcuts ──────────────────────────────────────────────
// Icons sit down the left edge of the wallpaper, out of the way of where
// windows open.
const shortcut_width = 84
const shortcut_height = 76
const shortcut_top = 18
const shortcut_left = 18
const shortcut_gap = 6
const shortcut_icon = 30

// ── Taskbar ────────────────────────────────────────────────────────
const taskbar_height = 46
// A minimised window's entry, dimmed rather than marked with a character.
const taskbar_item_height = 30
const taskbar_item_width = 168
// Entries shrink to share the bar before any of them is dropped, but only
// down to here — narrower than this and a title says nothing useful.
const taskbar_item_min_width = 84
// The bottom-right clock keeps this much logical room, independently of the
// framebuffer's physical density. At 200% the canvas expands it along with the
// rest of the desktop, so task buttons can never paint over it on an M1.
const taskbar_clock_width = 132
// A dock's entries are narrower than a taskbar's, and the panel floats this
// far clear of the screen's bottom edge.
const dock_item_width = 122
const dock_bottom_gap = 6
const taskbar_item_gap = 6
const taskbar_padding = 10
// Large, label-free buttons used by the Windows-7-style taskbar variant.
// The V anchor remains its own 42-pixel button at the lower left.
const taskbar_icon_item_width = 48
const taskbar_icon_item_min_width = 42
const taskbar_icon_item_height = 40

// ── Window switcher ────────────────────────────────────────────────
// Cmd-Tab's panel, in the middle of the screen. It is the same dark slab under
// either theme, and translucent: it sits over whatever is open for as long as
// a key is held, so what it covers should stay legible behind it, and a panel
// that took the chrome's colour would vanish into a light desktop. The
// selection is the theme's accent, which is the one part of it that belongs to
// the desktop's own look rather than to the panel.
const switcher_panel_id = 'switcher'
const switcher_bg = u32(0x11151f)
const switcher_alpha = u32(216)
const switcher_edge = u32(0x3a425c)
const switcher_text = u32(0xffffff)
const switcher_icon = u32(0xdfe6f4)
const switcher_icon_selected = u32(0xffffff)
const switcher_icon_minimized = u32(0x7c869c)
const switcher_tile = 84
const switcher_icon_size = 44
const switcher_gap = 6
const switcher_padding = 18
const switcher_label_height = 24
const switcher_radius = 18
const switcher_select_radius = 12
// What the panel leaves clear at the screen's edges before it wraps its tiles
// onto a second row.
const switcher_margin = 60

// ── Pointer ────────────────────────────────────────────────────────
const cursor_fill = u32(0xffffff)
const cursor_edge = u32(0x0d1220)
