// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import json2
import os
import surfacecore

struct Image {
mut:
	width   i32
	height  i32
	xoffset i32
	format  i32
	data    &u8 = unsafe { nil }
}

__global (
	model_image Image
	pixels      [4]u8
	opened      int
	destroyed   int
	images      int
)

fn mode() string { return os.getenv('VINIX_SURFACE_MODEL_MODE') }

fn receipt() {
	os.write_file(os.getenv('VINIX_SURFACE_MODEL_RECEIPT'), json2.encode({
		'opened':    json2.Any(opened)
		'images':    json2.Any(images)
		'destroyed': json2.Any(destroyed)
	})) or { panic(err) }
}

@[export: 'XOpenDisplay']
pub fn x_open(name &char) voidptr {
	assert unsafe { name.vstring() } == ':99'
	if mode() == 'missing-display' {
		receipt()
		return unsafe { nil }
	}
	opened++
	return voidptr(1)
}

@[export: 'XScreenCount']
pub fn x_screens(display voidptr) i32 {
	assert display == voidptr(1)
	return if mode() == 'screen-count' { 1 } else { 2 }
}

@[export: 'XQueryExtension']
pub fn x_query(display voidptr, name &char, major &i32, event &i32, failure &i32) i32 {
	assert display == voidptr(1)
	unsafe {
		*major = 99
		*event = 11
		*failure = 17
	}
	text := unsafe { name.vstring() }
	assert text in ['MIT-SHM', 'RANDR']
	return if text == 'MIT-SHM' {
		if mode() == 'no-shm' { 0 } else { 1 }
	} else {
		if mode() == 'has-randr' { 1 } else { 0 }
	}
}

@[export: 'XRootWindow']
pub fn x_root(display voidptr, screen i32) u64 {
	assert display == voidptr(1) && screen == 1
	return 0x123456789
}

@[export: 'XGetImage']
pub fn x_image(display voidptr, window u64, x i32, y i32, width u32, height u32, mask u64, format i32) &Image {
	assert display == voidptr(1) && window == 0x123456789 && x == 0 && y == 0 && width == 1 && height == 1 && mask == 0xffffffff && format == 2
	if mode() == 'missing-image' { return unsafe { nil } }
	mut mapped := surfacecore.map_file(os.getenv('VINIX_SURFACE_MODEL_FRAMEBUFFER'), false) or { panic(err) }
	defer { mapped.close() }
	offset := int(mapped.word(0) or { panic(err) }) + int(mapped.word(76) or { panic(err) }) * 12
	for index in 0 .. 4 { pixels[index] = unsafe { mapped.data[offset + index] } }
	if mode() == 'bad-pixel' { pixels[0] ^= 1 }
	images++
	model_image = Image{ width: 1, height: 1, format: 2, data: unsafe { &pixels[0] } }
	if mode() == 'null-data' { model_image.data = unsafe { nil } }
	return &model_image
}

@[export: 'XDestroyImage']
pub fn x_destroy(value &Image) i32 {
	assert value == &model_image && images == 1
	images--
	destroyed++
	return 1
}

@[export: 'XCloseDisplay']
pub fn x_close(display voidptr) i32 {
	assert display == voidptr(1) && opened == 1 && images == 0
	opened--
	receipt()
	return 0
}
