// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

// Hash the decoded ARGB artwork, so a fallback that silently substitutes a
// generic icon or maps an application to another application's art fails.
fn icon_test_hash(pixels []u32) u32 {
	mut value := u32(2166136261)
	for pixel in pixels {
		value = (value ^ pixel) * 16777619
	}
	return value
}

fn icon_test_directory(name string) string {
	base := os.real_path(os.temp_dir())
	pid := os.getpid().str()
	path := '${base}/vinix-app-icon-${pid}-${name}'
	unsafe {
		base.free()
		pid.free()
	}
	os.rmdir_all(path) or {}
	os.mkdir(path) or { panic(err) }
	return path
}

fn icon_test_write(path string, bytes []u8) {
	mut file := os.create(path) or { panic(err) }
	defer { file.close() }
	written := file.write(bytes) or { panic(err) }
	assert written == bytes.len
}

fn icon_test_qoi_with_stream(stream []u8) []u8 {
	mut bytes := [u8(`q`), `o`, `i`, `f`, 0, 0, 0, 2, 0, 0, 0, 1, 4, 0]
	bytes << stream
	bytes << [u8(0), 0, 0, 0, 0, 0, 0, 1]
	return bytes
}

fn icon_test_override() []u8 {
	// Two pixels with distinct colours and alpha, not desktop artwork.
	stream := [u8(0xff), 0x11, 0x22, 0x33, 0xff, 0xff, 0x44, 0x55, 0x66, 0x80]
	defer { unsafe { stream.free() } }
	return icon_test_qoi_with_stream(stream)
}

fn test_app_icons_keep_original_artwork_without_an_installed_directory() {
	root := icon_test_directory('missing')
	missing := os.join_path(root, 'uninstalled')
	defer {
		os.rmdir_all(root) or {}
		unsafe {
			root.free()
			missing.free()
		}
	}
	assert !os.exists(missing)
	expected := {
		'activity':   u32(0xa82bed1f)
		'blender':    u32(0x84f0ad7f)
		'calculator': u32(0x2957b9bb)
		'calendar':   u32(0x4b179024)
		'capture':    u32(0xa5cd69f1)
		'chromium':   u32(0x5740f3cd)
		'clock':      u32(0x4404180f)
		'disk_usage': u32(0xacf8a62c)
		'doom':       u32(0x69a723b6)
		'editor':     u32(0x86dfb77a)
		'files':      u32(0xb20a2a39)
		'firefox':    u32(0x75b54b5e)
		'minecraft':  u32(0xb77ccee8)
		'settings':   u32(0x8755c18b)
		'steam':      u32(0x2f793638)
		'terminal':   u32(0x77f5f3db)
	}
	assert expected.len == bundled_icon_paths.len
	for path in bundled_icon_paths {
		name := path['asset:'.len..]
		icon := load_app_icon_from_dir(name, missing)
		assert icon.width == 512 && icon.height == 512
		assert icon.pixels.len == 512 * 512
		assert icon_test_hash(icon.pixels) == expected[name]
		unsafe {
			name.free()
			icon.pixels.free()
		}
	}
}

fn test_app_icon_valid_installed_artwork_overrides_the_embedded_fallback() {
	root := icon_test_directory('override')
	path := os.join_path(root, 'terminal.qoi')
	bytes := icon_test_override()
	defer {
		os.rmdir_all(root) or {}
		unsafe {
			root.free()
			path.free()
			bytes.free()
		}
	}
	icon_test_write(path, bytes)
	icon := load_app_icon_from_dir('terminal', root)
	defer { unsafe { icon.pixels.free() } }
	assert icon.width == 2 && icon.height == 1
	assert icon.pixels == [u32(0xff112233), 0x80445566]
}

fn test_app_icon_corrupt_installed_artwork_uses_the_original_embedded_pixels() {
	root := icon_test_directory('corrupt')
	path := os.join_path(root, 'terminal.qoi')
	defer {
		os.rmdir_all(root) or {}
		unsafe {
			root.free()
			path.free()
		}
	}
	mut invalid_colorspace := icon_test_override()
	invalid_colorspace[13] = 2
	mut invalid_footer := icon_test_override()
	invalid_footer[invalid_footer.len - 1] = 2
	mut extra_opcode := icon_test_override()
	extra_opcode.insert(24, u8(0xc0))
	rgb_truncated := [u8(0xfe), 0x11, 0x22]
	rgba_truncated := [u8(0xff), 0x11, 0x22, 0x33]
	overlong_run := [u8(0xc2)]
	defer {
		unsafe {
			rgb_truncated.free()
			rgba_truncated.free()
			overlong_run.free()
		}
	}
	for invalid in [
		[]u8{},
		[u8(`q`), `o`, `i`, `f`, 0, 0, 0],
		[u8(`n`), `o`, `t`, `q`, `o`, `i`],
		icon_test_qoi_with_stream([]u8{}), // Header and footer, without pixel opcodes.
		icon_test_qoi_with_stream(rgb_truncated),
		icon_test_qoi_with_stream(rgba_truncated),
		icon_test_qoi_with_stream(overlong_run), // Three-pixel run in a two-pixel image.
		invalid_colorspace,
		invalid_footer,
		extra_opcode, // Complete image plus another opcode before the footer.
	] {
		icon_test_write(path, invalid)
		icon := load_app_icon_from_dir('terminal', root)
		assert icon.width == 512 && icon.height == 512
		assert icon_test_hash(icon.pixels) == 0x77f5f3db
		unsafe {
			icon.pixels.free()
			invalid.free()
		}
	}
}

fn test_app_icon_unknown_artwork_stays_missing() {
	root := icon_test_directory('unknown')
	defer {
		os.rmdir_all(root) or {}
		unsafe { root.free() }
	}
	icon := load_app_icon_from_dir('unknown-test-application', root)
	assert icon.width == 0 && icon.height == 0 && icon.pixels.len == 0
	assert !bundled_icon_path('asset:unknown-test-application')
}

fn test_app_icon_fallback_draws_visible_pixels_at_normal_and_hidpi_scales() {
	for scale in [1, 2]! {
		mut d := Desktop{ canvas: new_scaled_canvas(48, 48, 48 * scale, 48 * scale, scale) }
		defer {
			d.drop_sized_icons()
			unsafe {
				free(d.canvas.pixels)
				d.sized_icons.free()
				d.native_asset_icons.free()
			}
		}
		d.canvas.clear(0x123456)
		assert d.draw_app_icon('asset:terminal', 8, 8, 24, 24)
		assert d.sized_icons.len == 1 && !d.sized_icons[0].missing
		assert d.sized_icons[0].icon.width == 24 * scale
		assert d.sized_icons[0].icon.height == 24 * scale
		mut painted := 0
		for y in 0 .. 48 * scale {
			for x in 0 .. 48 * scale {
				pixel := unsafe { d.canvas.pixels[y * d.canvas.stride + x] }
				if x < 8 * scale || x >= 32 * scale || y < 8 * scale || y >= 32 * scale {
					assert pixel == 0x123456
				} else if pixel != 0x123456 {
					painted++
				}
			}
		}
		assert painted > 200 * scale * scale
		// Transparent edges preserve the wallpaper instead of drawing a box.
		assert unsafe { d.canvas.pixels[8 * scale * d.canvas.stride + 8 * scale] } == 0x123456
	}
}

fn test_app_icon_sized_cache_reuses_artwork_and_recovers_after_invalidation() {
	mut d := Desktop{}
	defer {
		d.drop_sized_icons()
		unsafe {
			d.sized_icons.free()
			d.native_asset_icons.free()
		}
	}
	first := d.sized_bundled_icon('asset:terminal', 24, 24)
	assert !isnil(first) && first.pixels.len == 24 * 24
	hash := icon_test_hash(first.pixels)
	for _ in 0 .. 100 {
		repeated := d.sized_bundled_icon('asset:terminal', 24, 24)
		assert repeated == first
		assert d.sized_icons.len == 1 && !d.sized_icons[0].missing
	}
	d.drop_sized_icons()
	assert d.sized_icons.len == 0
	reloaded := d.sized_bundled_icon('asset:terminal', 24, 24)
	assert !isnil(reloaded) && d.sized_icons.len == 1
	assert icon_test_hash(reloaded.pixels) == hash
}

fn test_app_icon_sized_cache_evicts_without_replacing_fallback_with_missing_artwork() {
	mut d := Desktop{}
	defer {
		d.drop_sized_icons()
		unsafe {
			d.sized_icons.free()
			d.native_asset_icons.free()
		}
	}
	for width in 1 .. sized_icon_limit + 2 {
		icon := d.sized_bundled_icon('asset:terminal', width, 16)
		assert !isnil(icon) && icon.pixels.len == width * 16
		assert d.sized_icons.len <= sized_icon_limit
	}
	assert d.sized_icons.len == sized_icon_limit
	assert d.sized_icons[0].icon.width == 2
	reloaded := d.sized_bundled_icon('asset:terminal', 1, 16)
	assert !isnil(reloaded) && reloaded.pixels.len == 16
	assert d.sized_icons.len == sized_icon_limit && d.sized_icons[0].icon.width == 3
	for entry in d.sized_icons {
		assert !entry.missing
	}
}
