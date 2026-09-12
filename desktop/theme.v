// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// One place for every color and measurement the desktop draws with, so the
// look can be changed without going through the layout code.
module main

// ── Wallpaper ──────────────────────────────────────────────────────

// The default theme's title bar height, for sizing a window before its
// theme is known — an AppFactory declares a height in the abstract.
const default_title_height = 34

// ── Windows ────────────────────────────────────────────────────────

// ── Window contents ────────────────────────────────────────────────
// ── Application interiors ──────────────────────────────────────────
// These do not follow the chrome's theme: an application draws its own inside,
// as ui2's calculator plainly does.
const app_surface = u32(0xfbfcfe)
const app_accent = u32(0x5b9cf8)
const app_on_accent = u32(0xffffff)

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
// framebuffer's physical density. At 200% the presenter expands it along with
// the rest of the desktop, so task buttons can never paint over it on an M1.
const taskbar_clock_width = 132
// A dock's entries are narrower than a taskbar's, and the panel floats this
// far clear of the screen's bottom edge.
const dock_item_width = 122
const dock_bottom_gap = 6
const taskbar_item_gap = 6
const taskbar_padding = 10

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
