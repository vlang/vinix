// SPDX-License-Identifier: GPL-2.0-or-later
module main

import gg
import ui2
import encoding.base64
import os
import sync.stdatomic as _

#include <sys/mman.h>

fn C.munmap(voidptr, uint) i32

#include <spawn.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <sys/resource.h>

struct C.rlimit {
mut:
	rlim_cur u64
	rlim_max u64
}

fn C.getrlimit(i32, &C.rlimit) i32
fn C.setrlimit(i32, &C.rlimit) i32

@[typedef]
struct C.posix_spawn_file_actions_t {}

fn C.posix_spawn_file_actions_init(&C.posix_spawn_file_actions_t) i32
fn C.posix_spawn_file_actions_destroy(&C.posix_spawn_file_actions_t) i32
fn C.posix_spawn_file_actions_adddup2(&C.posix_spawn_file_actions_t, i32, i32) i32
fn C.posix_spawn(&i32, &char, voidptr, voidptr, &&char, &&char) i32
fn C.waitpid(i32, &i32, i32) i32

fn testsuite_begin() {
	fd := os.getenv('VOX_TEST_SPAWN_FD').int()
	if fd > 0 {
		if C.fcntl(fd, C.F_GETFD) != -1 || C.fcntl(4, C.F_GETFD) < 0 { exit(1) }
		exit(0)
	}
}

fn test_worker_spawn_closes_extra_descriptors_and_preserves_reserved_channels() {
	mut original := C.rlimit{}
	assert C.getrlimit(C.RLIMIT_NOFILE, &original) == 0
	mut bounded := original
	bounded.rlim_cur = 256
	assert C.setrlimit(C.RLIMIT_NOFILE, &bounded) == 0
	defer { assert C.setrlimit(C.RLIMIT_NOFILE, &original) == 0 }
	mut file := os.open_file('/dev/null', 'r') or { panic(err) }
	defer { file.close() }
	fd := C.fcntl(file.fd, C.F_DUPFD, 128)
	assert fd >= 128
	defer { C.close(fd) }
	mut actions := C.posix_spawn_file_actions_t{}
	assert C.posix_spawn_file_actions_init(&actions) == 0
	defer { C.posix_spawn_file_actions_destroy(&actions) }
	assert C.posix_spawn_file_actions_adddup2(&actions, fd, 4) == 0
	assert gg.native_worker_close_actions(&actions, 5) == 0
	assert gg.native_worker_close_actions(&actions, -1) != 0
	mut strings := []string{}
	for key, value in os.environ() { strings << key + '=' + value }
	strings << 'VOX_TEST_SPAWN_FD=${fd}'
	mut environment := []&char{}
	for value in strings { environment << value.str }
	environment << unsafe { &char(nil) }
	name := os.executable()
	arguments := [unsafe { &char(name.str) }, unsafe { &char(nil) }]!
	mut pid := i32(0)
	assert C.posix_spawn(&pid, name.str, &actions, unsafe { nil }, &arguments[0], environment.data) == 0
	mut status := i32(-1)
	assert C.waitpid(pid, &status, 0) == pid
	assert status == 0
}

fn test_native_surface_clipping_and_alpha_compositing() {
	mut context := gg.new_context(width: 8, height: 8)
	context.begin()
	context.draw_rect_filled(0, 0, 8, 8, gg.blue)
	context.scissor_rect(2, 2, 3, 3)
	context.draw_rect_filled(-100, -100, 200, 200, gg.rgba(255, 0, 0, 128))
	inside := (3 * 8 + 3) * 4
	assert context.pixels[inside..inside + 4] == [u8(127), 0, 128, 255]
	assert context.pixels[..4] == [u8(255), 0, 0, 255]
	assert context.pixels[(6 * 8 + 6) * 4..(6 * 8 + 6) * 4 + 4] == [u8(255), 0, 0, 255]
}

fn test_native_frame_storage_and_cached_text_survive_request_recycling() {
	mut context := gg.new_context(width: 8, height: 8)
	buffer := context.pixels.data
	for _ in 0 .. 32 {
		gg.native_runtime_begin()
		context.begin()
		context.draw_rect_filled(0, 0, 8, 8, gg.red)
		context.draw_text(0, 0, 'persistent text', gg.TextCfg{})
		elements := ui2.native_embedded_elements()
		gg.native_runtime_end()
		assert elements.len > 0 && elements[0].children[0].text == 'persistent text'
		assert context.pixels.data == buffer
		assert context.pixels[..4] == [u8(0), 0, 255, 255]
	}
	ui2.native_release_resources()
	$if prealloc {
		unsafe {
			prealloc_scope_free_after(context.runtime_scope)
			prealloc_scope_free_after(context.host_scope)
		}
	}
}

fn test_prealloc_realloc_accepts_the_null_pointer_used_by_png_decoders() {
	$if prealloc {
		scope := unsafe { prealloc_scope_begin() }
		defer { unsafe { prealloc_scope_end(scope) } }
		bytes := unsafe { v_realloc(nil, 4096) }
		assert bytes != unsafe { nil }
		unsafe {
			bytes[0] = 42
			bytes[4095] = 99
		}
		assert unsafe { bytes[0] == 42 && bytes[4095] == 99 }
	}
}

fn test_decoded_png_pixels_outlive_the_decoders_frame_arena() {
	bytes := base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j3X8AAAAASUVORK5CYII=')
	mut scope := unsafe { voidptr(nil) }
	$if prealloc {
		scope = unsafe { prealloc_scope_begin() }
	}
	mut image := gg.create_image_from_byte_array(bytes) or { panic(err) }
	$if prealloc {
		unsafe { prealloc_scope_end(scope) }
	}
	assert image.width == 1 && image.height == 1 && image.ok
	unsafe { assert image.data[3] == 255 }
	image.destroy()
	assert image.data == unsafe { nil }
}

fn test_native_ellipses_keep_the_gg_center_and_radius_contract() {
	mut context := gg.new_context(width: 8, height: 8)
	context.begin()
	context.draw_ellipse_filled(4, 4, 2, 1, gg.red)
	assert context.pixels[(4 * 8 + 4) * 4..(4 * 8 + 4) * 4 + 4] == [u8(0), 0, 255, 255]
	assert context.pixels[(4 * 8 + 1) * 4..(4 * 8 + 1) * 4 + 4] == [u8(255), 255, 255, 255]
	assert context.pixels[(4 * 8 + 6) * 4..(4 * 8 + 6) * 4 + 4] == [u8(255), 255, 255, 255]
}

struct ArenaCursor {
	current voidptr
}

fn test_repeated_polygon_drawing_keeps_scanline_storage_out_of_the_arena() {
	mut context := gg.new_context(width: 8, height: 8)
	context.begin()
	points := [f32(-2), 1, 6, 1, 6, 6, -2, 6]
	mut cursor := unsafe { voidptr(nil) }
	$if prealloc {
		cursor = unsafe { (&ArenaCursor(g_memory_block)).current }
	}
	for _ in 0 .. 200 { context.draw_convex_poly(points, gg.red) }
	$if prealloc {
		assert unsafe { (&ArenaCursor(g_memory_block)).current == cursor }
	}
	assert context.pixels[(3 * 8 + 3) * 4..(3 * 8 + 3) * 4 + 4] == [u8(0), 0, 255, 255]
	assert context.pixels[(3 * 8 + 7) * 4..(3 * 8 + 7) * 4 + 4] == [u8(255), 255, 255, 255]
}

fn test_native_image_crop_keeps_source_coordinates() {
	mut context := gg.new_context(width: 4, height: 2)
	context.begin()
	bytes := [u8(255), 0, 0, 255, 0, 255, 0, 255]
	image := gg.Image{ width: 2, height: 1, data: bytes.data, ok: true }
	context.draw_image_with_config(
		img:       &image
		img_rect:  gg.Rect{0, 0, 4, 1}
		part_rect: gg.Rect{1, 0, 1, 1}
	)
	for x in 0 .. 4 {
		assert context.pixels[x * 4..x * 4 + 4] == [u8(0), 255, 0, 255]
	}
}

fn test_cached_streaming_images_outlive_frame_scratch_and_reuse_pixel_storage() {
	mut context := gg.new_context(width: 4, height: 2)
	mut scope := unsafe { voidptr(nil) }
	$if prealloc {
		scope = unsafe { prealloc_scope_begin() }
	}
	id := context.new_streaming_image(2, 1, 4, gg.StreamingImageConfig{})
	$if prealloc {
		unsafe { prealloc_scope_end(scope) }
	}
	mut pixels := [u8(255), 0, 0, 255, 0, 255, 0, 255]
	context.update_pixel_data(id, pixels.data)
	buffer := context.get_cached_image_by_idx(id).data
	$if prealloc {
		scope = unsafe { prealloc_scope_begin() }
	}
	pixels[0] = 42
	context.update_pixel_data(id, pixels.data)
	$if prealloc {
		unsafe { prealloc_scope_end(scope) }
	}
	image := context.get_cached_image_by_idx(id)
	assert image.width == 2 && image.height == 1
	assert image.data == buffer
	unsafe { assert image.data[0] == 42 && image.data[4] == 0 && image.data[5] == 255 }
	context.remove_cached_image_by_idx(id)
	assert !context.get_cached_image_by_idx(id).ok
	$if prealloc {
		unsafe { prealloc_scope_free_after(context.host_scope) }
	}
}

fn test_native_text_survives_the_document_frame_arena() {
	mut context := gg.new_context(width: 100, height: 50)
	mut scope := unsafe { voidptr(nil) }
	$if prealloc {
		scope = unsafe { prealloc_scope_begin() }
	}
	message := ['temporary', 'frame', 'text'].join(' ')
	context.draw_text(2, 3, message, gg.TextCfg{})
	$if prealloc {
		unsafe { prealloc_scope_end(scope) }
	}
	elements := ui2.native_embedded_elements()
	assert elements.len > 0 && elements[0].children[0].text == 'temporary frame text'
	assert elements[0].children[0].frame.x == 2 && elements[0].children[0].frame.y == 3
	ui2.native_release_resources()
	$if prealloc {
		unsafe { prealloc_scope_free_after(context.host_scope) }
	}
}

fn test_native_chrome_keeps_favicon_pixels_and_uses_native_buttons() {
	ui2.native_release_resources()
	defer { ui2.native_release_resources() }
	mut context := gg.new_context(width: 320, height: 200)
	mut pixels := [u8(255), 0, 0, 128, 0, 255, 0, 255]
	id := context.new_streaming_image(2, 1, 4, gg.StreamingImageConfig{})
	context.update_pixel_data(id, pixels.data)
	defer { context.remove_cached_image_by_idx(id) }
	path := '/root/.cache/vox/favicon.png'
	elements := [
		ui2.image('tab-icon-0', path, ui2.rect(0, 0, 16, 16)),
		ui2.button_with_image('bookmark-open:0', 'Example', path, ui2.rect(0, 20, 120, 24), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{}),
		ui2.button('back', '‹', ui2.rect(0, 50, 22, 22), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{}),
		ui2.button('window-close', '', ui2.rect(0, 0, 12, 12), ui2.BoxStyle{}, ui2.TextStyle{}),
	]
	for _ in 0 .. 2 {
		ui2.draw_embedded_elements(context, elements, {
			path: id
		}, fn (_ string) {})
		tree := ui2.native_embedded_elements()
		assert tree[0].image_path.starts_with('vinix-surface:')
		bytes := os.read_bytes(tree[0].image_path.all_after('vinix-surface:')) or { panic(err) }
		active := int(bytes[28])
		offset := 48 + active * 16 * 16 * 4
		assert bytes[offset..offset + 4] == [u8(127), 127, 255, 255]
		assert tree[1].native_style && !tree[1].box.transparent
		assert tree[1].children[0].image_path.starts_with('vinix-surface:')
		assert tree[1].children[0].frame.width == 16
		assert tree[1].children[1].text == 'Example'
		assert tree[1].children[1].frame.x > tree[1].children[0].frame.x
		assert tree[2].native_style && tree[2].text == ''
		assert tree[2].children[0].image_path == 'builtin:arrow_left'
		assert tree[2].children[0].frame == ui2.rect(0, 0, 22, 22)
		assert tree[3].hidden && !tree[3].enabled
	}
}

fn test_native_document_text_uses_desktop_fonts_and_preserves_clip_and_monospace() {
	ui2.native_release_resources()
	defer { ui2.native_release_resources() }
	mut context := gg.new_context(width: 100, height: 50)
	context.scissor_rect(5, 6, 80, 30)
	context.draw_text(2, 3, 'Roboto', gg.TextCfg{ size: 13, bold: true, mono: true })
	tree := ui2.native_embedded_elements()
	assert tree.len == 1
	assert tree[0].frame == ui2.rect(5, 6, 80, 30)
	label := tree[0].children[0]
	assert label.text == 'Roboto' && label.text_style.bold
	assert label.text_style.font_family == 'mono'
	assert label.frame.x == -3 && label.frame.y == -3
	assert label.frame.height == 18
}

fn test_vector_surface_has_the_compositors_real_buffer_layout() {
	path := os.temp_dir() + '/vox-native-test-${os.getpid()}.surface'
	defer { os.rm(path) or {} }
	gg.native_raster_vector(path, 8, 8, 0xffffff, [f32(1), 1, 6, 1, 1, 6], true, true, 0xff0000, 0, 0)
	bytes := os.read_bytes(path) or { panic(err) }
	assert (os.stat(path) or { panic(err) }).mode & 0o777 == 0o600
	assert bytes.len == 48 + 2 * 8 * 8 * 4
	assert bytes[..4] == 'VFS1'.bytes()
	assert bytes[12] == 8 && bytes[16] == 8 && bytes[20] == 32
	active := int(bytes[28])
	assert active in [0, 1]
	offset := 48 + active * 8 * 8 * 4 + (2 * 8 + 2) * 4
	assert bytes[offset..offset + 4] == [u8(0), 0, 255, 255]
}

fn test_native_publisher_preserves_a_buffer_claimed_by_the_compositor() {
	mut context := gg.new_context(width: 8, height: 8)
	context.path = os.temp_dir() + '/vox-native-ownership-${os.getpid()}.surface'
	defer {
		if context.surface != unsafe { nil } {
			assert C.munmap(context.surface, context.surface_size) == 0
		}
		os.rm(context.path) or {}
	}
	context.begin()
	context.draw_rect_filled(0, 0, 8, 8, gg.red)
	context.publish()
	assert context.surface != unsafe { nil }
	active := unsafe { voidptr(&u8(context.surface) + 28) }
	reader := unsafe { voidptr(&u8(context.surface) + 32) }
	first := C.atomic_load_u32(active)
	C.atomic_store_u32(reader, first)
	context.draw_rect_filled(0, 0, 8, 8, gg.blue)
	context.publish()
	second := C.atomic_load_u32(active)
	assert first != second
	context.draw_rect_filled(0, 0, 8, 8, gg.rgb(0, 255, 0))
	context.publish()
	assert C.atomic_load_u32(active) == second
	unsafe { assert (&u8(context.surface))[48 + int(first) * 8 * 8 * 4 + 2] == 255 }
	C.atomic_store_u32(reader, u32(0xffffffff))
	context.publish()
	assert C.atomic_load_u32(active) == first
	unsafe { assert (&u8(context.surface))[48 + int(first) * 8 * 8 * 4 + 1] == 255 }
}
