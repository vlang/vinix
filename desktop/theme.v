// One place for every color and measurement the desktop draws with, so the
// look can be changed without going through the layout code.
module main

// ── Wallpaper ──────────────────────────────────────────────────────
const wallpaper_top = u32(0x141d33)
const wallpaper_bottom = u32(0x3c5a86)

// ── Windows ────────────────────────────────────────────────────────
const window_radius = 9
const window_body = u32(0xfbfcfe)
const window_edge = u32(0xb9c2d0)

const title_height = 34
const title_active_bg = u32(0xffffff)
const title_inactive_bg = u32(0xf1f3f6)
const title_divider = u32(0xe4e8ee)
const title_text_active = u32(0x18202f)
const title_text_inactive = u32(0x99a2b1)

// Title bar buttons. Each is a rounded square that only shows a fill while the
// pointer is on it, so an idle title bar stays quiet.
const title_button_size = 22
const title_button_gap = 4
const title_button_inset = 8
const title_button_hover = u32(0xe7eaf0)
const title_button_close_hover = u32(0xe5484d)
const glyph_color = u32(0x3b465a)
const glyph_color_on_close = u32(0xffffff)

// ── Window contents ────────────────────────────────────────────────
const body_text = u32(0x30394a)
const body_muted = u32(0x7b8698)
const body_heading = u32(0x141c2b)
const body_rule = u32(0xe8ebf0)
const body_panel = u32(0xf3f5f9)

// ── Taskbar ────────────────────────────────────────────────────────
const taskbar_height = 46
const taskbar_bg = u32(0x101726)
const taskbar_edge = u32(0x28344e)
const taskbar_text = u32(0xc3cddf)
// A minimised window's entry, dimmed rather than marked with a character.
const taskbar_text_minimized = u32(0x76839a)
const taskbar_text_active = u32(0xffffff)
const taskbar_item_bg = u32(0x1b2436)
const taskbar_item_hover = u32(0x27334b)
const taskbar_item_active = u32(0x2c3d5e)
const taskbar_item_height = 30
const taskbar_item_width = 168
// Entries shrink to share the bar before any of them is dropped, but only
// down to here — narrower than this and a title says nothing useful.
const taskbar_item_min_width = 84
const launcher_width = 88
const taskbar_item_gap = 6
const taskbar_padding = 10

const accent = u32(0x5b9cf8)
const accent_dim = u32(0x27436e)

const clock_time_color = u32(0xffffff)
const clock_date_color = u32(0x8fa0bd)

// ── Pointer ────────────────────────────────────────────────────────
const cursor_fill = u32(0xffffff)
const cursor_edge = u32(0x0d1220)
