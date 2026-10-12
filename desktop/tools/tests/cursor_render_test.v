// SPDX-License-Identifier: GPL-2.0-or-later
module main

import ui2
import time

fn cursor_test_tree(color u32) ui2.Element {
	return ui2.view('cursor.scene', ui2.rect(0, 0, 160, 100), ui2.BoxStyle{ bg: 0x254769 }, [
		ui2.view('cursor.patch', ui2.rect(50, 30, 32, 24), ui2.BoxStyle{ bg: color }, []ui2.Element{}),
	])
}

fn cursor_test_pixels(d &Desktop) []u32 {
	mut pixels := []u32{len: d.canvas.stride * d.canvas.physical_height}
	unsafe { vmemcpy(pixels.data, d.canvas.pixels, pixels.len * 4) }
	return pixels
}

fn test_plain_cursor_motion_keeps_the_scene_and_hover_unchanged() {
	mut d := Desktop{ canvas: new_canvas(160, 100), pointer_x: 12, pointer_y: 14 }
	d.settings.wallpaper_image = -1
	tree := cursor_test_tree(0x112233)
	d.render_clipped(tree, d.damage_clip(d.canvas_damage()), false)
	d.dirty = false
	for point in [[138, 72]!, [139, 73]!, [55, 35]!, [0, 0]!, [159, 99]!] {
		d.on_pointer_move(point[0], point[1])
		assert d.pointer_moved_only && !d.dirty && !d.frame_damage.valid()
		old, next := d.move_cursor()
		assert old.valid && next == d.cursor_box(point[0], point[1])
		partial := cursor_test_pixels(&d)
		d.render_clipped(tree, d.damage_clip(d.canvas_damage()), false)
		full := cursor_test_pixels(&d)
		assert partial == full
		unsafe {
			partial.free()
			full.free()
		}
	}
	free_tree(tree)
	d.free_wallpaper()
	unsafe {
		free(d.canvas.pixels)
		d.cursor_backing.pixels.free()
	}
}

fn test_partial_updates_and_cursor_motion_match_complete_frames() {
	for theme in [ThemeKind.default_, .macos, .windows7] {
		for scale in [1, 2] {
			mut d := Desktop{ canvas: new_scaled_canvas(160, 100, 160 * scale, 100 * scale, scale), pointer_x: 12, pointer_y: 14 }
			d.settings.theme = theme
			d.settings.wallpaper_image = -1
			initial := cursor_test_tree(0x112233)
			d.render_clipped(initial, d.damage_clip(d.canvas_damage()), false)
			free_tree(initial)
			// Distant, overlapping, stationary, damage-overlapping and clipped
			// cursor positions exercise restoring and saving the backing store.
			for i, point in [[138, 72]!, [139, 73]!, [139, 73]!, [55, 35]!, [0, 0]!, [159, 99]!] {
				d.on_pointer_move(point[0], point[1])
				mut damage := FrameDamage{}
				damage.add(DamageRect{ x: 50, y: 30, w: 32, h: 24, valid: true })
				tree := cursor_test_tree(u32(0x667788 + i))
				d.render_partial_frame(tree, mut damage, false)
				assert d.cursor_backing.box == d.cursor_box(point[0], point[1])
				mut area := i64(0)
				for j in 0 .. damage.count { area += damage_area(damage.rects[j]) }
				// Presenting the gap between distant cursor positions would exceed
				// this budget by several times even on this small canvas.
				assert area < 4000
				partial := cursor_test_pixels(&d)
				d.render_clipped(tree, d.damage_clip(d.canvas_damage()), false)
				full := cursor_test_pixels(&d)
				assert partial == full
				free_tree(tree)
				unsafe {
					partial.free()
					full.free()
				}
			}
			d.clear_hit_targets()
			d.free_wallpaper()
			d.glass_release()
			unsafe {
				free(d.canvas.pixels)
				d.cursor_backing.pixels.free()
			}
		}
	}
}

fn test_partial_frame_without_cursor_backing_repaints_completely() {
	mut d := Desktop{ canvas: new_canvas(160, 100), pointer_x: 80, pointer_y: 60 }
	d.settings.wallpaper_image = -1
	mut damage := FrameDamage{}
	damage.add(DamageRect{ x: 50, y: 30, w: 32, h: 24, valid: true })
	tree := cursor_test_tree(0x112233)
	d.render_partial_frame(tree, mut damage, false)
	assert damage.count == 1 && damage.rects[0] == d.canvas_damage()
	assert d.cursor_backing.box.valid
	assert unsafe { d.canvas.pixels[0] } == 0x254769
	free_tree(tree)
	d.free_wallpaper()
	unsafe {
		free(d.canvas.pixels)
		d.cursor_backing.pixels.free()
	}
}

fn test_partial_presentation_copies_only_damage_on_each_output() {
	for scale in [1, 2] {
		mut canvas := new_scaled_canvas(7, 4, 13, 7, scale)
		// At 1x use the same physical canvas with its natural logical extent.
		if scale == 1 {
			canvas.width = 13
			canvas.height = 7
		}
		for i in 0 .. 91 {
			unsafe { canvas.pixels[i] = u32(0x123400 + i) }
		}
		for direct in [true, false] {
			mut left := [32]u32{init: 0xdeadbeef}
			mut right := [49]u32{init: 0xdeadbeef}
			mut second := Framebuffer{ fd: 1, base: unsafe { &right[0] }, width: 7, height: 7, stride: 7, origin_x: 6, direct: direct, r_shift: 0, g_shift: 8, b_shift: 16 }
			mut fb := Framebuffer{ fd: 1, base: unsafe { &left[0] }, width: 6, height: 4, stride: 8, origin_y: 3, direct: direct, r_shift: 0, g_shift: 8, b_shift: 16, graphics_claimed: true, extra_count: 1 }
			fb.extra[0] = unsafe { &second }
			mut damage := FrameDamage{}
			damage.add(DamageRect{ x: 2, y: 1, w: 2, h: 2, valid: true })
			damage.add(DamageRect{ x: 6, y: 3, w: 3, h: 2, valid: true })
			fb.present_frame_damage(&canvas, damage)
			for output in [unsafe { &fb }, unsafe { &second }] {
				for y in 0 .. output.height {
					for x in 0 .. output.stride {
						px := x + output.origin_x
						py := y + output.origin_y
						mut changed := false
						for i in 0 .. damage.count {
							r := damage.rects[i]
							changed = changed || (x < output.width && px >= r.x * scale && px < (r.x + r.w) * scale && py >= r.y * scale && py < (r.y + r.h) * scale)
						}
						expected := if changed {
							output.pack_pixel(unsafe { canvas.pixels[py * canvas.stride + px] })
						} else {
							u32(0xdeadbeef)
						}
						assert unsafe { output.base[y * output.stride + x] } == expected
					}
				}
			}
		}
		unsafe { free(canvas.pixels) }
	}
}

// An explicit comparison of the previous compositor path with the current
// path. Timings are informational; correctness uses pixel and damage budgets.
fn test_cursor_with_clock_render_cost() {
	mut d := Desktop{ canvas: new_canvas(1920, 1080), pointer_x: 80, pointer_y: 100 }
	d.settings.wallpaper_image = -1
	tree := ui2.view('cursor.bench', ui2.rect(0, 0, 1920, 1080), ui2.BoxStyle{ bg: 0x254769 }, []ui2.Element{})
	for previous in [true, false] {
		d.render_clipped(tree, d.damage_clip(d.canvas_damage()), false)
		started := time.sys_mono_now()
		for i in 0 .. 200 {
			d.pointer_x = if i % 2 == 0 { 1800 } else { 80 }
			mut damage := FrameDamage{}
			damage.add(DamageRect{ x: 1850, y: 1020, w: 70, h: 60, valid: true })
			if previous {
				damage.add(damage_union(d.cursor_backing.box, d.cursor_box(d.pointer_x, d.pointer_y)))
				for j in 0 .. damage.count {
					d.render_clipped(tree, d.damage_clip(damage.rects[j]), false)
				}
			} else {
				d.render_partial_frame(tree, mut damage, false)
			}
		}
		println('1920x1080 cursor + clock, ${if previous { 'previous' } else { 'current' }}: ${(time.sys_mono_now() - started) / 200 / 1000} us/frame')
	}
	free_tree(tree)
	d.free_wallpaper()
	unsafe {
		free(d.canvas.pixels)
		d.cursor_backing.pixels.free()
	}
}
