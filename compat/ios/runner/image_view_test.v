// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

$if macos {
	#flag -framework Foundation
	#flag -framework CoreGraphics
	#include <objc/runtime.h>
	#define dispatch_sync vinix_native_header_dispatch_sync
	#include <CoreGraphics/CoreGraphics.h>
	#undef dispatch_sync
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlopen(&char, int) voidptr
fn C.dlclose(voidptr) int
fn C.CGColorSpaceCreateDeviceRGB() voidptr
fn C.CGBitmapContextCreate(voidptr, usize, usize, usize, usize, voidptr, u32) voidptr
fn C.CGBitmapContextCreateImage(voidptr) voidptr
fn C.CGContextRelease(voidptr)
fn C.CGColorSpaceRelease(voidptr)
fn C.CGImageRelease(voidptr)
type ImageViewSend = fn (u64, u64, u64, u64) u64
type ImageViewRectSet = fn (u64, u64, ObjRect) u64
type ImageViewRectGet = fn (u64, u64) ObjRect
type ImageViewSizeGet = fn (u64, u64) ObjSize
type ImageViewFit = fn (u64, u64, ObjSize) ObjSize
type ImageViewNumberGet = fn (u64, u64) f64
type ImageViewNumberSet = fn (u64, u64, f64)
type ImageViewImage = fn (u64, u64, u64, f64, u64) u64
struct ImageViewApi { native bool send u64 view u64 image u64 arrays u64 }
fn (api ImageViewApi) selector(name &char) u64 { $if macos { if api.native { return u64(C.sel_registerName(name)) } }; return u64(name) }
fn (api ImageViewApi) message(object u64, name &char, a u64, b u64) u64 { return unsafe { ImageViewSend(voidptr(api.send))(object, api.selector(name), a, b) } }
fn (api ImageViewApi) rect_set(object u64, name &char, r ObjRect) u64 { return unsafe { ImageViewRectSet(voidptr(api.send))(object, api.selector(name), r) } }
fn (api ImageViewApi) rect(object u64, name &char) ObjRect { return unsafe { ImageViewRectGet(voidptr(api.send))(object, api.selector(name)) } }
fn (api ImageViewApi) size(object u64) ObjSize { return unsafe { ImageViewSizeGet(voidptr(api.send))(object, api.selector(c'intrinsicContentSize')) } }
fn (api ImageViewApi) fit(object u64) ObjSize { return unsafe { ImageViewFit(voidptr(api.send))(object, api.selector(c'sizeThatFits:'), ObjSize{100, 200}) } }
fn (api ImageViewApi) number(object u64) f64 { return unsafe { ImageViewNumberGet(voidptr(api.send))(object, api.selector(c'animationDuration')) } }
fn (api ImageViewApi) set_number(object u64, value f64) { unsafe { ImageViewNumberSet(voidptr(api.send))(object, api.selector(c'setAnimationDuration:'), value) } }
fn (api ImageViewApi) release(object u64) { api.message(object, c'release', 0, 0) }
fn (api ImageViewApi) array(image u64) u64 { array := api.message(api.arrays, c'new', 0, 0); api.message(array, c'addObject:', image, 0); return api.message(array, c'autorelease', 0, 0) }
fn (api ImageViewApi) pool() u64 { $if macos { if api.native { return api.message(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0) } }; return objc_pool_push() }
fn (api ImageViewApi) drain(pool u64) { $if macos { if api.native { api.release(pool); return } }; objc_pool_pop(pool) }
fn (api ImageViewApi) bitmap(width int, height int, scale f64) u64 {
	$if macos { if api.native {
		space := C.CGColorSpaceCreateDeviceRGB(); context := C.CGBitmapContextCreate(unsafe { nil }, usize(width), usize(height), 8, usize(width * 4), space, 1); assert context != unsafe { nil }
		image := C.CGBitmapContextCreateImage(context); assert image != unsafe { nil }
		value := unsafe { ImageViewImage(voidptr(api.send))(api.image, api.selector(c'imageWithCGImage:scale:orientation:'), u64(image), scale, 0) }
		C.CGImageRelease(image); C.CGContextRelease(context); C.CGColorSpaceRelease(space); return value
	} }
	space := cg_rgb_space(); context := cg_bitmap_create(unsafe { nil }, u64(width), u64(height), 8, u64(width) * 4, space, 1); objc_release(space); assert context != 0
	image := ui_image_from_cg(context, scale); objc_release(context); return objc_autorelease(image)
}
fn image_view_runtime_api() ImageViewApi { return ImageViewApi{send: u64(unsafe { voidptr(C.ios_objc_builtin) }), view: ios_runtime.names['UIImageView'], image: ios_runtime.names['UIImage'], arrays: ios_runtime.names['NSMutableArray']} }
fn image_view_cases(api ImageViewApi) {
	pool := api.pool(); normal := api.bitmap(16, 8, 2); highlight := api.bitmap(12, 24, 2)
	for mode in 0 .. 5 {
		allocated := api.message(api.view, c'alloc', 0, 0)
		view := match mode {
			0 { api.message(allocated, c'init', 0, 0) }
			1 { api.message(allocated, c'initWithImage:', normal, 0) }
			2 { api.message(allocated, c'initWithImage:highlightedImage:', normal, highlight) }
			3 { api.message(allocated, c'initWithImage:highlightedImage:', 0, highlight) }
			else { api.rect_set(allocated, c'initWithFrame:', ObjRect{1, 2, 30, 40}) }
		}
		expected := match mode { 1, 2 { ObjSize{8, 4} } 3 { ObjSize{6, 12} } else { ObjSize{} } }
		expected_frame := if mode == 4 { ObjRect{1, 2, 30, 40} } else { ObjRect{0, 0, expected.width, expected.height} }
		assert api.rect(view, c'frame') == expected_frame
		assert api.rect(view, c'bounds') == ObjRect{0, 0, expected_frame.width, expected_frame.height}
		assert api.fit(view) == expected && api.size(view) == if mode in [0, 4] { ObjSize{-1, -1} } else { expected }
		assert api.message(view, c'isOpaque', 0, 0) == u64(mode !in [1, 2])
		for selector in [c'contentMode', c'isUserInteractionEnabled', c'clipsToBounds', c'isHighlighted', c'isAnimating', c'animationRepeatCount', c'animationImages', c'highlightedAnimationImages']! { assert api.message(view, selector, 0, 0) == 0 }
		assert api.number(view) == 0
		api.message(view, c'setHighlighted:', 1, 0); assert api.message(view, c'isHighlighted', 0, 0) == 1
		assert api.fit(view) == expected
		api.message(view, c'setImage:', normal, 0); assert api.message(view, c'image', 0, 0) == normal && api.size(view) == ObjSize{8, 4}
		assert api.rect(view, c'frame') == expected_frame && api.message(view, c'isOpaque', 0, 0) == 0
		api.message(view, c'setHighlightedImage:', highlight, 0); assert api.message(view, c'highlightedImage', 0, 0) == highlight
		for selector in [c'setUserInteractionEnabled:', c'setClipsToBounds:', c'setOpaque:']! { api.message(view, selector, 1, 0) }
		assert api.message(view, c'isUserInteractionEnabled', 0, 0) == 1 && api.message(view, c'clipsToBounds', 0, 0) == 1 && api.message(view, c'isOpaque', 0, 0) == 1
		for content_mode in 0 .. 13 { api.message(view, c'setContentMode:', u64(content_mode), 0); assert api.message(view, c'contentMode', 0, 0) == u64(content_mode) }
		api.set_number(view, 0.75); api.message(view, c'setAnimationRepeatCount:', 3, 0); assert api.number(view) == 0.75 && api.message(view, c'animationRepeatCount', 0, 0) == 3
		values := api.array(normal)
		api.message(view, c'setAnimationImages:', values, 0); api.message(view, c'setHighlightedAnimationImages:', values, 0)
		first := api.message(view, c'animationImages', 0, 0); second := api.message(view, c'highlightedAnimationImages', 0, 0)
		assert first != values && second != values
		api.message(values, c'removeAllObjects', 0, 0); assert api.message(first, c'count', 0, 0) == 1 && api.message(second, c'count', 0, 0) == 1
		api.message(view, c'setAnimationImages:', 0, 0); api.message(view, c'setHighlightedAnimationImages:', 0, 0)
		api.message(view, c'startAnimating', 0, 0); assert api.message(view, c'isAnimating', 0, 0) == 0; api.message(view, c'stopAnimating', 0, 0)
		api.rect_set(view, c'setFrame:', ObjRect{10, 20, 24, 30}); assert api.rect(view, c'bounds') == ObjRect{0, 0, 24, 30}
		api.rect_set(view, c'setBounds:', ObjRect{0, 0, 12, 10}); assert api.rect(view, c'frame') == ObjRect{16, 30, 12, 10}
		api.message(view, c'sizeToFit', 0, 0); assert api.rect(view, c'frame') == ObjRect{16, 30, 8, 4}
		api.release(view)
	}
	api.drain(pool)
}
fn test_image_view_native_reference() {
	$if macos {
		handle := C.dlopen(c'/System/iOSSupport/System/Library/Frameworks/UIKit.framework/UIKit', 2); assert handle != unsafe { nil }
		api := ImageViewApi{native: true, send: u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend')), view: u64(C.objc_getClass(c'UIImageView')), image: u64(C.objc_getClass(c'UIImage')), arrays: u64(C.objc_getClass(c'NSMutableArray'))}
		image_view_cases(api); assert C.dlclose(handle) == 0
		println('IOS-IMAGEVIEW-NATIVE: five constructors, frames/bounds/sizing, highlight-independent intrinsic size, opacity, flags, thirteen modes, copied arrays and idle animation passed')
	}
}
fn test_image_view_runtime_ownership() {
	for _ in 0 .. 2 {
		objc_start(); api := image_view_runtime_api(); image_view_cases(api); assert ios_runtime.live == 0
		assert objc_class_size(api.view) == 512 && objc_class_parent(api.view) == ios_runtime.names['UIView']
		assert runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', '_OBJC_CLASS_$_UIImageView') or { panic(err) } == api.view
		assert ctext(u64(objc_method_types(objc_instance_method(api.view, u64(c'initWithImage:highlightedImage:'))))) == '@32@0:8@16@24'
		for _ in 0 .. 100 {
			pool := api.pool(); image := api.bitmap(4, 2, 1); view := api.message(objc_allocate(api.view), c'initWithImage:', image, 0)
			api.drain(pool); assert image in ios_runtime.objects
			objc_set_class(view, ios_runtime.names['NSObject']); objc_release(view); assert ios_runtime.live == 0
		}
		storage := u64(C.calloc(1, 512)); assert objc_construct_instance(api.view, storage) == storage
		api.message(storage, c'init', 0, 0); assert objc_destruct_instance(storage) == storage; C.free(unsafe { voidptr(storage) })
		assert ios_runtime.live == 0; objc_stop()
	}
	println('IOS-IMAGEVIEW: shared native cases, measured metadata, retained image after pool drainage,100 isa changes, caller storage and two zero-live-object cycles passed')
}
fn test_image_view_pixels_and_desktop_publication() {
	objc_start(); api := image_view_runtime_api(); pool := api.pool()
	image := api.bitmap(4, 2, 1); context := obj_header(image).fields[0]; cg_rgb_fill(context, 1, 0, 0, 0.5); cg_fill_rect(context, ObjRect{0, 0, 4, 2})
	view := api.message(objc_allocate(api.view), c'initWithImage:', image, 0); api.rect_set(view, c'setFrame:', ObjRect{0, 0, 8, 8}); api.message(view, c'setClipsToBounds:', 1, 0)
	mut previous := ''
	for mode in 0 .. 13 {
		api.message(view, c'setContentMode:', u64(mode), 0); path := image_view_path(view); assert path.len > 0 && os.exists(path)
		if previous.len > 0 { assert !os.exists(previous); unsafe { previous.free() } }
		previous = path.clone()
		cached := image_view_path(view); assert cached == path; unsafe { cached.free() }
		bytes := os.read_bytes(path) or { panic(err) }; data := cf_data_create(0, u64(bytes.data), bytes.len); decoded := ui_image_decode(data); objc_release(data); unsafe { bytes.free() }
		assert decoded != 0 && cg_bitmap_width(decoded) == 8 && cg_bitmap_height(decoded) == 8
		mut colored := 0
		for y in 0 .. 8 { for x in 0 .. 8 { pixel := bitmap_pixel(decoded, x, y); if pixel[3] != 0 { assert pixel == [u32(128), 0, 0, 128]!; colored++ } } }
		assert colored == if mode in [0, 2, 3] { 64 } else if mode == 1 { 32 } else { 8 }
		objc_release(decoded); unsafe { path.free() }
	}
	api.message(view, c'setContentMode:', 1, 0)
	obj_header(view).frame.width = 0; assert image_view_path(view) == ''
	obj_header(view).frame.width = 8; restored_path := image_view_path(view); assert restored_path.len > 0 && os.exists(restored_path); unsafe { restored_path.free() }
	highlight := api.bitmap(2, 4, 1); highlighted_context := obj_header(highlight).fields[0]; cg_rgb_fill(highlighted_context, 0, 1, 0, 1); cg_fill_rect(highlighted_context, ObjRect{0, 0, 2, 4})
	api.message(view, c'setHighlightedImage:', highlight, 0); api.message(view, c'setHighlighted:', 1, 0)
	highlighted_path := image_view_path(view); highlighted_bytes := os.read_bytes(highlighted_path) or { panic(err) }
	highlighted_data := cf_data_create(0, u64(highlighted_bytes.data), highlighted_bytes.len); highlighted_image := ui_image_decode(highlighted_data); objc_release(highlighted_data); unsafe { highlighted_bytes.free(); highlighted_path.free() }
	assert bitmap_pixel(highlighted_image, 3, 0) == [u32(0), 255, 0, 255]! && bitmap_pixel(highlighted_image, 0, 0)[3] == 0; objc_release(highlighted_image)
	api.message(view, c'setHighlighted:', 0, 0)
	mut encoded := []u8{}; encode_view(mut encoded, view, false, 0) or { panic(err) }; assert encoded[0] == 3 && encoded[1] & 64 == 0
	api.message(view, c'setUserInteractionEnabled:', 1, 0); encoded.clear(); encode_view(mut encoded, view, false, 0) or { panic(err) }; assert encoded[1] & 64 != 0; unsafe { encoded.free() }
	current_path := obj_header(view).image_view.path.clone()
	api.message(view, c'setImage:', 0, 0); assert image_view_path(view) == '' && !os.exists(current_path); unsafe { current_path.free() }
	assert !os.exists(previous); unsafe { previous.free() }; objc_release(view)
	// A retained snapshot outlives its view; a published file does not. The
	// original sidecar must still retire after object_setClass changes isa.
	retiring_view := api.message(objc_allocate(api.view), c'initWithImage:', image, 0)
	api.message(retiring_view, c'setAnimationImages:', api.array(image), 0)
	snapshot := api.message(api.message(retiring_view, c'animationImages', 0, 0), c'retain', 0, 0)
	retiring_path := image_view_path(retiring_view); assert os.exists(retiring_path)
	objc_set_class(retiring_view, ios_runtime.names['NSObject']); objc_release(retiring_view)
	assert !os.exists(retiring_path) && api.message(snapshot, c'count', 0, 0) == 1 && obj_header(snapshot).items[0] == image
	api.release(snapshot); unsafe { retiring_path.free() }
	// Verify the _Exit path also removes unattached views' publications while
	// preserving object storage, references and image contents for workers.
	closing_view := api.message(objc_allocate(api.view), c'initWithImage:', image, 0)
	closing_path := image_view_path(closing_view); closing_refs := obj_header(closing_view).refs
	image_view_shutdown_files(); assert !os.exists(closing_path)
	assert obj_header(closing_view).refs == closing_refs && api.message(closing_view, c'image', 0, 0) == image
	objc_release(closing_view); unsafe { closing_path.free() }
	api.drain(pool); assert ios_runtime.live == 0; objc_stop()
	println('IOS-IMAGEVIEW-PIXELS: thirteen content modes preserve premultiplied alpha and coverage; PNG cache reuses unchanged pixels, retires replaced files, serializes image/interaction flags and clears nil images')
}
fn test_image_view_rejections() {
	objc_start(); api := image_view_runtime_api()
	for mode in ['image', 'mode', 'duration', 'count', 'frame', 'bounds', 'array', 'array-image', 'playback', 'snapshot', 'reinitialize', 'uninitialized', 'overflow', 'raster']! {
		mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			pool := api.pool(); view := objc_allocate(api.view)
			if mode == 'uninitialized' { api.message(view, c'image', 0, 0) }
			api.message(view, c'init', 0, 0)
			match mode {
				'image' { api.message(view, c'setImage:', objc_new(ios_runtime.names['NSObject']), 0) }
				'mode' { api.message(view, c'setContentMode:', 13, 0) }
				'duration' { api.set_number(view, -1) }
				'count' { api.message(view, c'setAnimationRepeatCount:', u64(-1), 0) }
				'frame' { api.rect_set(view, c'setFrame:', ObjRect{0, 0, -1, 4}) }
				'bounds' { api.rect_set(view, c'setBounds:', ObjRect{1, 0, 4, 4}) }
				'array' { api.message(view, c'setAnimationImages:', objc_new(ios_runtime.names['NSObject']), 0) }
				'array-image' { values := api.array(objc_new(ios_runtime.names['NSObject'])); api.message(view, c'setAnimationImages:', values, 0) }
				'reinitialize' { api.message(view, c'init', 0, 0) }
				else {
					image := api.bitmap(4, 2, 1); api.message(view, c'setImage:', image, 0)
					if mode in ['playback', 'snapshot'] { values := api.array(image); api.message(view, c'setAnimationImages:', values, 0); if mode == 'snapshot' { api.message(api.message(view, c'animationImages', 0, 0), c'removeAllObjects', 0, 0) } else { api.message(view, c'startAnimating', 0, 0) } }
					if mode == 'overflow' { api.rect_set(view, c'setFrame:', ObjRect{0, 0, 8, 8}); api.message(view, c'setContentMode:', 2, 0); image_view_path(view) }
					if mode == 'raster' { api.rect_set(view, c'setFrame:', ObjRect{0, 0, 4097, 1}); image_view_path(view) }
				}
			}
			api.drain(pool); C._exit(0)
		}
		C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
		for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
		C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'image', 'array-image' { 'requires a bitmap UIImage' }
			'mode' { 'content mode is not supported' }
			'duration' { 'animation duration must be finite and nonnegative' }
			'count' { 'animation count must be nonnegative' }
			'frame' { 'frame size is outside the supported range' }
			'bounds' { 'nonzero bounds origin is not implemented' }
			'array' { 'animation requires an array' }
			'playback' { 'playback is not implemented' }
			'snapshot' { 'animation snapshot is read-only' }
			'reinitialize' { 'reinitialization is not implemented' }
			'uninitialized' { 'is not initialized' }
			'overflow' { 'overflow outside unclipped bounds is not implemented' }
			else { 'raster exceeds the desktop profile' }
		}
		assert output.contains('iOS: image view ' + reason), output; assert !output.contains('AddressSanitizer') && !output.contains('runtime error:'), output
	}
	assert ios_runtime.live == 0; objc_stop()
	println('IOS-IMAGEVIEW-REJECT: invalid configuration, unsupported playback, readonly snapshots, repeat/uninitialized init, nonzero bounds, unclipped overflow and oversized raster fail explicitly')
}
