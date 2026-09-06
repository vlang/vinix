// One place for every color and measurement the desktop draws with, so the
// look can be changed without going through the layout code.
module main

// ── Wallpaper ──────────────────────────────────────────────────────

// The default theme's title bar height, for sizing a window before its
// theme is known — an AppFactory declares a height in the abstract.
const default_title_height = 34

// ── Windows ────────────────────────────────────────────────────────


// Title bar buttons. Each is a rounded square that only shows a fill while the
// pointer is on it, so an idle title bar stays quiet.
const title_button_size = 22
const title_button_gap = 4
const title_button_inset = 8

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

// ── File browser ───────────────────────────────────────────────────
const files_up = u32(0x4a6fa5)
const files_up_disabled = u32(0xe7eaf0)
const files_row_hover = u32(0xeaf1fb)
const files_error = u32(0xc0392b)
const files_folder_icon = u32(0x5b8def)
const files_file_icon = u32(0x9aa5b5)

// ── Settings ───────────────────────────────────────────────────────
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
const launcher_width = 88
// A dock's entries are narrower than a taskbar's, and the panel floats this
// far clear of the screen's bottom edge.
const dock_item_width = 122
const dock_bottom_gap = 6
const taskbar_item_gap = 6
const taskbar_padding = 10



// ── Pointer ────────────────────────────────────────────────────────
const cursor_fill = u32(0xffffff)
const cursor_edge = u32(0x0d1220)