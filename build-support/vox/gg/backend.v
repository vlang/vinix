// SPDX-License-Identifier: MIT
// GG's drawing contract hosted by UI2's Vinix backend, without a Sokol window.
@[has_globals]
module gg

import math
import os
import sokol.sapp
import sokol.gfx
import stbi
import time
import ui2
import sync.stdatomic as _

#include <sys/mman.h>
#include <spawn.h>
#include <unistd.h>

fn C.posix_spawn_file_actions_addclose(voidptr, i32) i32
fn C.sysconf(i32) i64

fn C.mmap(voidptr, uint , i32 , i32 , i32 , i64 ) voidptr
fn C.munmap(voidptr, uint) i32

// Vox's worker uses glibc's close-from spawn extension. Musl provides individual
// close actions. Cover its current descriptor limit and any descriptors that
// remain open above a subsequently lowered limit. Browser workers never raise
// that limit between preparing these actions and spawning their child.
@[export: 'vox_native_worker_close_actions']
pub fn native_worker_close_actions(actions voidptr, first i32) i32 {
	if first < 0 { return i32(C.EINVAL) }
	mut limit := C.sysconf(C._SC_OPEN_MAX)
	if limit < 0 || limit > 1048576 { return i32(C.EINVAL) }
	directory := $if linux { '/proc/self/fd' } $else { '/dev/fd' }
	for name in os.ls(directory) or { return i32(C.EIO) } {
		fd := name.i64()
		if fd >= limit { limit = fd + 1 }
	}
	for fd := i64(first); fd < limit; fd++ {
		// Darwin's spawn rejects closing an unopened descriptor. Linux musl
		// ignores that close, so it can also cover descriptors opened meanwhile.
		$if macos {
			if C.fcntl(i32(fd), C.F_GETFD) < 0 { continue }
		}
		code := C.posix_spawn_file_actions_addclose(actions, i32(fd))
		if code != 0 { return code }
	}
	return 0
}

pub type TouchPoint = sapp.TouchPoint

pub enum HorizontalAlign {
	left
	center
	right
}

pub enum VerticalAlign {
	top
	middle
	bottom
	baseline
}

pub struct Event {
pub mut:
	frame_count        u64
	typ                sapp.EventType
	key_code           KeyCode
	char_code          u32
	key_repeat         bool
	modifiers          u32
	mouse_button       MouseButton
	mouse_x            f32
	mouse_y            f32
	mouse_dx           f32
	mouse_dy           f32
	scroll_x           f32
	scroll_y           f32
	num_touches        int
	touches            [8]TouchPoint
	window_width       int
	window_height      int
	framebuffer_width  int
	framebuffer_height int
}

@[params]
pub struct Config {
pub:
	width            int = 800
	height           int = 600
	min_width        int
	min_height       int
	window_title     string = 'Vox'
	bg_color         Color  = white
	native_rendering bool
	user_data        voidptr
	init_fn          FNCb      = unsafe { nil }
	cleanup_fn       FNCb      = unsafe { nil }
	frame_fn         FNCb      = unsafe { nil }
	event_fn         FNEvent   = unsafe { nil }
	on_event         FNEvent2  = unsafe { nil }
	resized_fn       FNEvent   = unsafe { nil }
	click_fn         FNClick   = unsafe { nil }
	char_fn          FNChar    = unsafe { nil }
	keydown_fn       FNKeyDown = unsafe { nil }
	texture_filter   TextureFilter
}

pub struct Context {
pub mut:
	width            int
	height           int
	scale            f32 = 1
	native_rendering bool
	config           Config
	user_data        voidptr
	window           sapp.Desc
	has_started      bool
	timer            time.StopWatch
	update_timer     time.StopWatch
	image_cache      []Image
	pixels           []u8
	clip             Rect
	path             string
	surface          voidptr = unsafe { nil }
	surface_size     uint
	surface_width    int
	surface_height   int
	host_scope       voidptr = unsafe { nil }
	host_tail        voidptr = unsafe { nil }
	runtime_scope    voidptr = unsafe { nil }
	pixel_storage    voidptr = unsafe { nil }
}

struct NativeBlockPrefix {
mut:
	current  voidptr
	stop     voidptr
	start    voidptr
	previous voidptr
	next     voidptr
	scope    voidptr
}

struct NativeScopePrefix {
mut:
	previous   &NativeBlockPrefix = unsafe { nil }
	first      voidptr
	saved_next voidptr
}

pub fn native_state_enter() voidptr {
	return vinix_gg_context.native_cache_enter()
}

pub fn native_state_leave(previous voidptr) {
	vinix_gg_context.native_cache_leave(previous)
}

pub fn native_runtime_begin() {
	$if prealloc {
		mut ctx := vinix_gg_context
		unsafe {
			prealloc_scope_free_after(ctx.runtime_scope)
			ctx.runtime_scope = prealloc_scope_begin()
		}
	}
}

pub fn native_runtime_end() {
	$if prealloc {
		mut ctx := vinix_gg_context
		unsafe {
			// A persistent browser callback can grow the parent while this
			// request is active. Preserve that sibling before detaching.
			scope := &NativeScopePrefix(ctx.runtime_scope)
			parent := scope.previous
			if parent != nil && parent.next != nil {
				next := &NativeBlockPrefix(parent.next)
				if next.scope == parent.scope { scope.saved_next = next }
			}
			prealloc_scope_leave(ctx.runtime_scope)
			mut tail := &NativeBlockPrefix(g_memory_block)
			for tail.next != nil {
				next := &NativeBlockPrefix(tail.next)
				if next.scope != tail.scope { break }
				tail = next
			}
			g_memory_block = voidptr(tail)
		}
	}
}

fn (mut ctx Context) ensure_pixels() {
	size := ctx.width * ctx.height * 4
	if ctx.pixel_storage != unsafe { nil } && ctx.pixels.len == size { return }
	if ctx.pixel_storage != unsafe { nil } { unsafe { C.free(ctx.pixel_storage) } }
	ctx.pixel_storage = unsafe { C.malloc(size) }
	if ctx.pixel_storage == unsafe { nil } { panic('native framebuffer allocation failed') }
	ctx.pixels = unsafe { (&u8(ctx.pixel_storage)).vbytes(size) }
	unsafe { C.memset(ctx.pixel_storage, 255, uint(size)) }
}

// Cached image records must outlive document/frame arenas. Keep a detached
// host arena, like Vox's persistent closure metadata, and release it on exit.
fn (mut ctx Context) native_cache_enter() voidptr {
	$if prealloc {
		unsafe {
			if ctx.host_scope == nil {
				ctx.host_scope = prealloc_scope_begin()
				ctx.host_tail = voidptr(g_memory_block)
				prealloc_scope_leave(ctx.host_scope)
				(&NativeBlockPrefix(ctx.host_tail)).previous = nil
			}
			previous := voidptr(g_memory_block)
			g_memory_block = ctx.host_tail
			return previous
		}
	}
	return unsafe { nil }
}

fn (mut ctx Context) native_cache_leave(previous voidptr) {
	$if prealloc {
		unsafe {
			ctx.host_tail = voidptr(g_memory_block)
			g_memory_block = previous
		}
	}
}

__global vinix_gg_context = &Context(unsafe { nil })

pub fn new_context(cfg Config) &Context {
	mut context := &Context{
		width:     cfg.width
		height:    cfg.height
		config:    cfg
		user_data: cfg.user_data
		window:    sapp.Desc{ width: cfg.width, height: cfg.height }
		path:      '/tmp/vox-${os.getpid()}.surface'
	}
	vinix_gg_context = context
	context.ensure_pixels()
	return context
}

pub fn (mut ctx Context) run() {
	vinix_gg_context = ctx
	if ctx.config.init_fn != unsafe { nil } { ctx.config.init_fn(ctx.user_data) }
	ctx.has_started = true
	ui2.run_window(ctx.config.window_title, ctx.width, ctx.height, native_build, native_action)
	if ctx.config.cleanup_fn != unsafe { nil } { ctx.config.cleanup_fn(ctx.user_data) }
	ui2.native_release_resources()
	for mut image in ctx.image_cache { image.destroy() }
	$if prealloc {
		unsafe { prealloc_scope_free_after(ctx.runtime_scope) }
		unsafe { prealloc_scope_free_after(ctx.host_scope) }
	}
	unsafe { C.free(ctx.pixel_storage) }
	ctx.release_surface()
	os.rm(ctx.path) or {}
}

fn native_build() ui2.Element {
	mut ctx := vinix_gg_context
	size := ui2.bounds()
	ctx.width = int(size.width)
	ctx.height = int(size.height)
	ctx.ensure_pixels()
	if ctx.config.frame_fn != unsafe { nil } { ctx.config.frame_fn(ctx.user_data) }
	ctx.publish()
	// Browser callbacks retain their own state. Recycle only the native UI
	// tree assembled after those callbacks have finished.
	native_runtime_begin()
	ui2.native_reset_targets()
	mut elements := [ui2.image('vox-document', 'vinix-surface:' + ctx.path, size)]
	elements << ui2.native_embedded_elements()
	return ui2.view('vox-native', size, ui2.BoxStyle{ bg: 0xffffff }, elements)
}

fn native_action(id string) { ui2.native_embedded_action(id) }

pub fn native_dispatch_pointer(kind int, button int, scroll int, x f64, y f64) {
	mut ctx := vinix_gg_context
	if ctx == unsafe { nil } { return }
	mut event := Event{
		typ:                match kind {
			1 { .mouse_down }
			2 { .mouse_up }
			3, 4 { .mouse_scroll }
			else { .mouse_move }
		}
		mouse_button:       match button {
			2 { .middle }
			3 { .right }
			else { .left }
		}
		mouse_x:            f32(x)
		mouse_y:            f32(y)
		window_width:       ctx.width
		window_height:      ctx.height
		framebuffer_width:  ctx.width
		framebuffer_height: ctx.height
		scroll_y:           if kind == 3 { f32(scroll) } else { 0 }
		scroll_x:           if kind == 4 { f32(scroll) } else { 0 }
	}
	native_event(&event, ctx)
}

pub fn native_dispatch_key(code int, modifiers u32, text string) {
	mut ctx := vinix_gg_context
	mut event := Event{
		typ:                .key_down
		key_code:           unsafe { KeyCode(code) }
		modifiers:          modifiers
		window_width:       ctx.width
		window_height:      ctx.height
		framebuffer_width:  ctx.width
		framebuffer_height: ctx.height
	}
	native_event(&event, ctx)
	if modifiers & 14 == 0 {
		for character in text.runes() {
			event.typ = .char
			event.char_code = u32(character)
			native_event(&event, ctx)
		}
	}
}

pub fn (ctx &Context) begin() {
	mut owner := unsafe { &Context(ctx) }
	owner.ensure_pixels()
	unsafe { C.memset(owner.pixels.data, 255, uint(owner.pixels.len)) }
	owner.clip = Rect{0, 0, f32(ctx.width), f32(ctx.height)}
}

pub fn (ctx &Context) end() {}

pub fn (ctx &Context) quit() { ui2.native_quit() }

pub fn window_size() Size { return Size{vinix_gg_context.width, vinix_gg_context.height} }

pub fn set_window_title(_ string) {}

pub fn (ctx &Context) scissor_rect(x int, y int, width int, height int) {
	mut owner := unsafe { &Context(ctx) }
	owner.clip = Rect{f32(x), f32(y), f32(width), f32(height)}
}

fn (ctx &Context) blend(x int, y int, color Color) {
	if x < 0 || y < 0 || x >= ctx.width || y >= ctx.height || x < ctx.clip.x || y < ctx.clip.y
		|| x >= ctx.clip.x + ctx.clip.width || y >= ctx.clip.y + ctx.clip.height {
		return
	}
	mut owner := unsafe { &Context(ctx) }
	i := (y * ctx.width + x) * 4
	a := int(color.a)
	owner.pixels[i] = u8((int(color.b) * a + int(owner.pixels[i]) * (255 - a) + 127) / 255)
	owner.pixels[i + 1] = u8((int(color.g) * a + int(owner.pixels[i + 1]) * (255 - a) + 127) / 255)
	owner.pixels[i + 2] = u8((int(color.r) * a + int(owner.pixels[i + 2]) * (255 - a) + 127) / 255)
	owner.pixels[i + 3] = 255
}

pub fn (ctx &Context) draw_rect_filled(x f32, y f32, width f32, height f32, color Color) {
	if width <= 0 || height <= 0 { return }
	for py in int(math.max(0.0, y)) .. int(math.min(f64(ctx.height), math.ceil(y + height))) {
		for px in int(math.max(0.0, x)) .. int(math.min(f64(ctx.width), math.ceil(x + width))) {
			ctx.blend(px, py, color)
		}
	}
}

pub fn (ctx &Context) draw_rounded_rect_filled(x f32, y f32, width f32, height f32, radius f32, color Color) {
	r := math.min(f64(radius), math.min(f64(width), f64(height)) / 2)
	for py in int(math.max(0.0, y)) .. int(math.min(f64(ctx.height), math.ceil(y + height))) {
		for px in int(math.max(0.0, x)) .. int(math.min(f64(ctx.width), math.ceil(x + width))) {
			dx := math.max(math.max(f64(x) + r - px - 0.5, f64(px) + 0.5 - x - width + r), 0.0)
			dy := math.max(math.max(f64(y) + r - py - 0.5, f64(py) + 0.5 - y - height + r), 0.0)
			if dx * dx + dy * dy <= r * r { ctx.blend(px, py, color) }
		}
	}
}

pub fn (ctx &Context) draw_rounded_rect_empty(x f32, y f32, width f32, height f32, radius f32, color Color) {
	ctx.draw_line_with_config(x, y, x + width, y, PenConfig{ color: color })
	ctx.draw_line_with_config(x, y + height, x + width, y + height, PenConfig{ color: color })
	ctx.draw_line_with_config(x, y, x, y + height, PenConfig{ color: color })
	ctx.draw_line_with_config(x + width, y, x + width, y + height, PenConfig{ color: color })
}

pub fn (ctx &Context) draw_line_with_config(x f32, y f32, x2 f32, y2 f32, cfg PenConfig) {
	steps := int(math.max(math.abs(x2 - x), math.abs(y2 - y))) + 1
	for i in 0 .. steps + 1 {
		t := f32(i) / f32(steps)
		ctx.draw_rect_filled(x + (x2 - x) * t, y + (y2 - y) * t, cfg.thickness, cfg.thickness, cfg.color)
	}
}

pub fn (ctx &Context) draw_ellipse_filled(center_x f32, center_y f32, radius_x f32, radius_y f32, color Color) {
	x := center_x - radius_x
	y := center_y - radius_y
	width := radius_x * 2
	height := radius_y * 2
	if width <= 0 || height <= 0 { return }
	for py in int(math.max(0.0, y)) .. int(math.min(f64(ctx.height), math.ceil(y + height))) {
		for px in int(math.max(0.0, x)) .. int(math.min(f64(ctx.width), math.ceil(x + width))) {
			dx := (f64(px) + 0.5 - x - width / 2) / (width / 2)
			dy := (f64(py) + 0.5 - y - height / 2) / (height / 2)
			if dx * dx + dy * dy <= 1 { ctx.blend(px, py, color) }
		}
	}
}

pub fn (ctx &Context) draw_ellipse_thick(x f32, y f32, radius_x f32, radius_y f32, thickness f32, color Color) {
	for step in 0 .. 180 {
		a := f64(step) * 2 * math.pi / 180
		b := f64(step + 1) * 2 * math.pi / 180
		ctx.draw_line_with_config(x + f32(math.cos(a)) * radius_x, y + f32(math.sin(a)) * radius_y,
			x + f32(math.cos(b)) * radius_x, y + f32(math.sin(b)) * radius_y, PenConfig{ color: color, thickness: thickness })
	}
}

pub fn (ctx &Context) draw_convex_poly(points []f32, color Color) {
	if points.len < 6 { return }
	// A polygon is a draw call, not retained browser state. Reuse one scanline
	// buffer instead of allocating an arena array for every row of every frame.
	storage := unsafe { C.malloc((points.len / 2) * int(sizeof(f32))) }
	if storage == unsafe { nil } { return }
	defer { unsafe { C.free(storage) } }
	mut intersections := unsafe { &f32(storage) }
	mut top := f32(ctx.height)
	mut bottom := f32(0)
	for i := 1; i < points.len; i += 2 {
		top = math.min(top, points[i])
		bottom = math.max(bottom, points[i])
	}
	for y in int(math.max(0.0, math.floor(top))) .. int(math.min(f64(ctx.height), math.ceil(bottom))) {
		mut count := 0
		for i := 0; i < points.len; i += 2 {
			j := (i + 2) % points.len
			if (points[i + 1] > y) != (points[j + 1] > y) {
				value := points[i] + (f32(y) - points[i + 1]) * (points[j] - points[i]) / (points[j + 1] - points[i + 1])
				mut position := count
				unsafe {
					for position > 0 && intersections[position - 1] > value {
						intersections[position] = intersections[position - 1]
						position--
					}
					intersections[position] = value
				}
				count++
			}
		}
		for i := 0; i + 1 < count; i += 2 {
			unsafe { ctx.draw_rect_filled(intersections[i], f32(y), intersections[i + 1] - intersections[i], 1, color) }
		}
	}
}

pub struct Image {
pub mut:
	id              int
	width           int
	height          int
	nr_channels     int = 4
	data            &u8 = unsafe { nil }
	ok              bool
	texture_filter  TextureFilter
	allocation      voidptr = unsafe { nil }
	allocation_size int
}

@[params]
pub struct ImageConfig {
pub:
	texture_filter ?TextureFilter
}

@[params]
pub struct StreamingImageConfig {
pub:
	texture_filter TextureFilter
	min_filter     gfx.Filter = .linear
	mag_filter     gfx.Filter = .linear
}

pub fn create_image_from_byte_array(bytes []u8) !Image {
	decoded := stbi.load_from_memory(bytes.data, bytes.len, desired_channels: 4)!
	defer { decoded.free() }
	size := decoded.width * decoded.height * 4
	pixels := unsafe { C.malloc(size) }
	if pixels == unsafe { nil } { return error('native image allocation failed') }
	unsafe { C.memcpy(pixels, decoded.data, uint(size)) }
	return Image{
		width:           decoded.width
		height:          decoded.height
		data:            pixels
		ok:              true
		allocation:      pixels
		allocation_size: size
	}
}

pub fn (mut ctx Context) create_image_from_byte_array(bytes []u8, _ ImageConfig) !Image {
	mut image := create_image_from_byte_array(bytes)!
	image.id = ctx.cache_image(image)
	return image
}

pub fn (mut ctx Context) create_image(path string, cfg ImageConfig) !Image {
	return ctx.create_image_from_byte_array(os.read_bytes(path)!, cfg)
}

pub fn (mut img Image) init_sokol_image() &Image { return unsafe { img } }

pub fn (mut img Image) destroy() {
	img.ok = false
	if img.allocation != unsafe { nil } { unsafe { C.free(img.allocation) } }
	img.allocation = unsafe { nil }
	img.allocation_size = 0
	img.data = unsafe { nil }
}

pub fn (mut img Image) update_pixel_data(data &u8) {
	size := img.width * img.height * 4
	if img.allocation == unsafe { nil } || img.allocation_size != size {
		if img.allocation != unsafe { nil } { unsafe { C.free(img.allocation) } }
		img.allocation = unsafe { C.malloc(size) }
		img.allocation_size = size
	}
	if img.allocation == unsafe { nil } {
		img.ok = false
		return
	}
	unsafe { C.memcpy(img.allocation, data, uint(size)) }
	img.data = img.allocation
}

pub fn (mut ctx Context) new_streaming_image(width int, height int, channels int, cfg StreamingImageConfig) int {
	return ctx.cache_image(Image{
		width:          width
		height:         height
		nr_channels:    channels
		texture_filter: cfg.texture_filter
		ok:             true
	})
}

pub fn (mut ctx Context) update_pixel_data(id int, data &u8) {
	ctx.image_cache[id].update_pixel_data(data)
}

pub fn (ctx &Context) draw_image_with_config(cfg DrawImageConfig) {
	image := if cfg.img != unsafe { nil } {
		cfg.img
	} else if cfg.img_id >= 0 && cfg.img_id < ctx.image_cache.len {
		&ctx.image_cache[cfg.img_id]
	} else {
		return
	}
	if image.data == unsafe { nil } || !image.ok { return }
	d := cfg.img_rect
	s := if cfg.part_rect.width > 0 {
		cfg.part_rect
	} else {
		Rect{0, 0, f32(image.width), f32(image.height)}
	}
	if d.width <= 0 || d.height <= 0 { return }
	for y in int(math.max(0.0, d.y)) .. int(math.min(f64(ctx.height), math.ceil(d.y + d.height))) {
		for x in int(math.max(0.0, d.x)) .. int(math.min(f64(ctx.width), math.ceil(d.x + d.width))) {
			sx := int(s.x + (f32(x) - d.x) / d.width * s.width)
			sy := int(s.y + (f32(y) - d.y) / d.height * s.height)
			if sx < 0 || sy < 0 || sx >= image.width || sy >= image.height { continue }
			i := (sy * image.width + sx) * 4
			unsafe { ctx.blend(x, y, Color{image.data[i], image.data[i + 1], image.data[i + 2], u8(u32(image.data[i + 3]) * cfg.color.a / 255)}) }
		}
	}
}

pub fn (ctx &Context) publish() {
	if ctx.pixels.len != ctx.width * ctx.height * 4 { return }
	mut owner := unsafe { &Context(ctx) }
	if owner.surface == unsafe { nil } || owner.surface_width != ctx.width || owner.surface_height != ctx.height {
		owner.release_surface()
		mut header := []u8{len: 48}
		for i, value in [u32(0x31534656), 1, 48, u32(ctx.width), u32(ctx.height), u32(ctx.width * 4),
			1, 0, u32(0xffffffff), 0, u32(ctx.pixels.len), 0] {
			for shift in 0 .. 4 { header[i * 4 + shift] = u8(value >> (shift * 8)) }
		}
		size := uint(48 + ctx.pixels.len * 2)
		if size > 128 * 1024 * 1024 { return }
		mut file := os.open_file(ctx.path + '.next', 'w+', 0o600) or {
			eprintln('Vox surface: ${err}')
			return
		}
		file.write(header) or {
			file.close()
			return
		}
		file.seek(i64(size - 1), .start) or {
			file.close()
			return
		}
		file.write([u8(0)]) or {
			file.close()
			return
		}
		mapping := C.mmap(unsafe { nil }, size, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, i32(file.fd), 0)
		file.close()
		if mapping == unsafe { voidptr(-1) } {
			eprintln('Vox surface mmap: ${os.last_error()}')
			return
		}
		os.mv(ctx.path + '.next', ctx.path) or {
			C.munmap(mapping, size)
			return
		}
		owner.surface = mapping
		owner.surface_size = size
		owner.surface_width = ctx.width
		owner.surface_height = ctx.height
	}
	active := unsafe { voidptr(&u8(owner.surface) + 28) }
	reader := unsafe { voidptr(&u8(owner.surface) + 32) }
	next := u32(1) - C.atomic_load_u32(active)
	if C.atomic_load_u32(reader) == next { return }
	unsafe { C.memcpy(&u8(owner.surface) + 48 + int(next) * ctx.pixels.len, ctx.pixels.data, uint(ctx.pixels.len)) }
	C.atomic_store_u32(active, next)
}

fn (mut ctx Context) release_surface() {
	if ctx.surface != unsafe { nil } {
		C.munmap(ctx.surface, ctx.surface_size)
		ctx.surface = unsafe { nil }
	}
}

pub fn native_raster_vector(path string, width int, height int, background u32, points []f32,
	closed bool, fill_enabled bool, fill u32, stroke u32, stroke_width f64) {
	if width <= 0 || height <= 0 || width > 4096 || height > 4096 { return }
	mut context := Context{
		width:  width
		height: height
		path:   path
		clip:   Rect{0, 0, f32(width), f32(height)}
	}
	context.ensure_pixels()
	context.draw_rect_filled(0, 0, f32(width), f32(height), rgb(u8(background >> 16), u8(background >> 8), u8(background)))
	if fill_enabled {
		context.draw_convex_poly(points, rgb(u8(fill >> 16), u8(fill >> 8), u8(fill)))
	}
	if stroke_width > 0 && points.len >= 4 {
		color := rgb(u8(stroke >> 16), u8(stroke >> 8), u8(stroke))
		for i := 0; i + 3 < points.len; i += 2 {
			context.draw_line_with_config(points[i], points[i + 1], points[i + 2], points[i + 3], PenConfig{ color: color, thickness: f32(stroke_width) })
		}
		if closed {
			context.draw_line_with_config(points[points.len - 2], points.last(), points[0], points[1], PenConfig{ color: color, thickness: f32(stroke_width) })
		}
	}
	context.publish()
	context.release_surface()
	unsafe { C.free(context.pixel_storage) }
}

@[params]
pub struct TextCfg {
pub:
	color          Color = black
	size           int   = 16
	align          HorizontalAlign
	vertical_align VerticalAlign
	max_width      int
	family         string
	bold           bool
	mono           bool
	italic         bool
}

pub fn (ctx &Context) draw_text(x int, y int, text string, cfg TextCfg) {
	mut owner := unsafe { &Context(ctx) }
	previous := owner.native_cache_enter()
	defer { owner.native_cache_leave(previous) }
	ui2.native_add_text(x, y, text, cfg.size, u32(cfg.color.r) << 16 | u32(cfg.color.g) << 8 | u32(cfg.color.b), cfg.bold, cfg.italic)
}

@[export: 'gg__gg_event_fn']
fn native_event(pointer voidptr, owner voidptr) {
	event := unsafe { &Event(pointer) }
	mut ctx := unsafe { &Context(owner) }
	if ctx.config.event_fn != unsafe { nil } { ctx.config.event_fn(event, ctx.user_data) }
	if event.typ == .key_down && ctx.config.keydown_fn != unsafe { nil } {
		ctx.config.keydown_fn(event.key_code, unsafe { Modifier(event.modifiers) }, ctx.user_data)
	}
	if event.typ == .char && ctx.config.char_fn != unsafe { nil } {
		ctx.config.char_fn(event.char_code, ctx.user_data)
	}
	if event.typ == .mouse_down && ctx.config.click_fn != unsafe { nil } {
		ctx.config.click_fn(event.mouse_x, event.mouse_y, event.mouse_button, ctx.user_data)
	}
}

@[export: 'vox_tab_x11_frame']
fn native_tab_frame(_ voidptr, _ u64, values &f64) {
	unsafe {
		values[0] = 0
		values[1] = 0
		values[2] = vinix_gg_context.width
		values[3] = vinix_gg_context.height
	}
}

@[export: 'vox_tab_x11_show']
fn native_tab_show(_ voidptr, _ u64, _ i32, _ f64, _ f64, _ f64, _ f64) {}
