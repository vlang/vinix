// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include "@VMODROOT/abi/gles-surface.h"

fn C.ios_surface_load(&u32) u32
fn C.ios_surface_store(&u32, u32)
fn C.glReadPixels(i32, i32, i32, i32, u32, u32, voidptr)
fn C.glGetIntegerv(u32, &i32)
fn C.glPixelStorei(u32, i32)
fn C.glBindBuffer(u32, u32)
fn C.glReadBuffer(u32)

fn gles_surface_close(mut view GlesView) {
	if view.surface == unsafe { nil } { return }
	C.munmap(view.surface, usize(view.surface_size))
	C.unlink(unsafe { &char(view.surface_path.str) })
	C.free(view.rgba)
	unsafe { view.surface_path.free() }
	view.surface_path = ''
	view.surface = unsafe { nil }
	view.rgba = unsafe { nil }
	view.surface_size = 0
}

fn gles_surface_create(object u64, mut view GlesView) {
	buffer_size := u64(view.width) * u64(view.height) * 4
	view.surface_size = 48 + 2 * buffer_size
	if view.surface_size > 128 * 1024 * 1024 { panic('iOS: GLKView shared surface exceeds desktop limits') }
	view.surface_sequence++
	view.surface_path = '/tmp/vinix-ios-${C.getpid()}-${object.hex()}-${view.surface_sequence}.surface'
	fd := C.open(unsafe { &char(view.surface_path.str) }, C.O_CREAT | C.O_EXCL | C.O_RDWR, 384)
	if fd < 0 { panic('iOS: cannot create GLKView shared surface') }
	if C.ftruncate(i32(fd), view.surface_size) != 0 { C.close(fd); panic('iOS: cannot size GLKView shared surface') }
	view.surface = C.mmap(unsafe { nil }, usize(view.surface_size), C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0)
	C.close(fd)
	if view.surface == unsafe { voidptr(-1) } { panic('iOS: cannot map GLKView shared surface') }
	view.rgba = C.malloc(usize(buffer_size))
	if view.rgba == unsafe { nil } { panic('iOS: cannot allocate GLKView readback buffer') }
	base := u64(view.surface)
	// VSF1 is the existing desktop's two-buffer XRGB8888 surface protocol.
	for index, value in [u32(0x31534656), 1, 48, u32(view.width), u32(view.height),
		u32(view.width) * 4, 1, 0, ~u32(0), 0, u32(buffer_size), 0]! {
		write32(base + u64(index) * 4, value)
	}
}

fn gles_surface_publish(object u64) {
	mut view := unsafe { &GlesView(obj_header(object).graphics) }
	if view.surface == unsafe { nil } { gles_surface_create(object, mut view) }
	base := u64(view.surface)
	active := unsafe { &u32(base + 28) }
	reader := unsafe { &u32(base + 32) }
	next := C.ios_surface_load(active) ^ 1
	if C.ios_surface_load(reader) == next { return } // Drop rather than overwrite a compositor reader.
	mut framebuffer := i32(0)
	mut alignment := i32(0)
	mut pack_buffer := i32(0)
	mut row_length := i32(0)
	mut skip_rows := i32(0)
	mut skip_pixels := i32(0)
	C.glGetIntegerv(C.GL_READ_FRAMEBUFFER_BINDING, &framebuffer)
	C.glGetIntegerv(C.GL_PACK_ALIGNMENT, &alignment)
	C.glGetIntegerv(C.GL_PIXEL_PACK_BUFFER_BINDING, &pack_buffer)
	C.glGetIntegerv(C.GL_PACK_ROW_LENGTH, &row_length)
	C.glGetIntegerv(C.GL_PACK_SKIP_ROWS, &skip_rows)
	C.glGetIntegerv(C.GL_PACK_SKIP_PIXELS, &skip_pixels)
	C.glBindFramebuffer(C.GL_READ_FRAMEBUFFER, view.fbo)
	mut read_buffer := i32(0)
	C.glGetIntegerv(C.GL_READ_BUFFER, &read_buffer)
	C.glReadBuffer(C.GL_COLOR_ATTACHMENT0)
	C.glBindBuffer(C.GL_PIXEL_PACK_BUFFER, 0)
	C.glPixelStorei(C.GL_PACK_ALIGNMENT, 4)
	C.glPixelStorei(C.GL_PACK_ROW_LENGTH, 0)
	C.glPixelStorei(C.GL_PACK_SKIP_ROWS, 0)
	C.glPixelStorei(C.GL_PACK_SKIP_PIXELS, 0)
	C.glReadPixels(0, 0, view.width, view.height, C.GL_RGBA, C.GL_UNSIGNED_BYTE, view.rgba)
	C.glPixelStorei(C.GL_PACK_ALIGNMENT, alignment)
	C.glPixelStorei(C.GL_PACK_ROW_LENGTH, row_length)
	C.glPixelStorei(C.GL_PACK_SKIP_ROWS, skip_rows)
	C.glPixelStorei(C.GL_PACK_SKIP_PIXELS, skip_pixels)
	C.glBindBuffer(C.GL_PIXEL_PACK_BUFFER, u32(pack_buffer))
	C.glReadBuffer(u32(read_buffer))
	C.glBindFramebuffer(C.GL_READ_FRAMEBUFFER, u32(framebuffer))
	buffer_size := u64(view.width) * u64(view.height) * 4
	destination := base + 48 + u64(next) * buffer_size
	for y := i32(0); y < view.height; y++ {
		for x := i32(0); x < view.width; x++ {
			source := u64(view.rgba) + (u64(view.height - 1 - y) * u64(view.width) + u64(x)) * 4
			pixel := read32(source)
			write32(destination + (u64(y) * u64(view.width) + u64(x)) * 4,
				0xff000000 | (pixel & 255) << 16 | (pixel & 0xff00) | (pixel >> 16 & 255))
		}
	}
	C.ios_surface_store(active, next)
}

fn gles_image_path(object u64) string {
	if !objc_is_kind(object, ios_runtime.names['GLKView']) || obj_header(object).graphics == unsafe { nil } { return '' }
	view := unsafe { &GlesView(obj_header(object).graphics) }
	if view.surface_path.len == 0 { return '' }
	return 'vinix-surface:${view.surface_path}'
}

fn gles_unlink_surfaces(object u64, depth int) {
	if object == 0 || depth > 32 { return }
	header := obj_header(object)
	if objc_is_kind(object, ios_runtime.names['GLKView']) && header.graphics != unsafe { nil } {
		view := unsafe { &GlesView(header.graphics) }
		if view.surface_path.len != 0 { C.unlink(unsafe { &char(view.surface_path.str) }) }
	}
	for index in 0 .. header.child_count { gles_unlink_surfaces(header.children[index], depth + 1) }
}
