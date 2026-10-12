// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math

// Catalyst's 512-byte UIImageView record is opaque. Static bitmap images and
// public configuration live here, independently of isa and caller storage.
struct ImageViewState {
mut:
	images [2]u64
	animations [2]u64
	highlighted bool
	interaction bool
	clips bool
	opaque bool = true
	mode i64
	duration f64
	repeat_count i64
	dirty bool = true
	width int
	height int
	sequence u64
	path string
}

fn image_view_types(name string, meta bool, selector string) ?string {
	if name != 'UIImageView' || meta { return none }
	return match selector {
		'init', 'image', 'highlightedImage', 'animationImages', 'highlightedAnimationImages' { '@16@0:8' }
		'initWithImage:' { '@24@0:8@16' }
		'initWithImage:highlightedImage:' { '@32@0:8@16@24' }
		'initWithFrame:' { '@48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16' }
		'setImage:', 'setHighlightedImage:', 'setAnimationImages:', 'setHighlightedAnimationImages:' { 'v24@0:8@16' }
		'frame', 'bounds' { '{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8' }
		'setFrame:', 'setBounds:', 'drawRect:' { 'v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16' }
		'sizeThatFits:' { '{CGSize=dd}32@0:8{CGSize=dd}16' }
		'intrinsicContentSize' { '{CGSize=dd}16@0:8' }
		'isHighlighted', 'isUserInteractionEnabled', 'clipsToBounds', 'isOpaque', 'isAnimating' { 'B16@0:8' }
		'setHighlighted:', 'setUserInteractionEnabled:', 'setClipsToBounds:', 'setOpaque:' { 'v20@0:8B16' }
		'contentMode', 'animationRepeatCount' { 'q16@0:8' }
		'setContentMode:', 'setAnimationRepeatCount:' { 'v24@0:8q16' }
		'animationDuration' { 'd16@0:8' }
		'setAnimationDuration:' { 'v24@0:8d16' }
		'startAnimating', 'stopAnimating', 'sizeToFit' { 'v16@0:8' }
		else { return none }
	}
}

fn image_view_selector(object u64, selector string) bool {
	return object !in ios_runtime.classes && objc_is_kind(object, ios_runtime.names['UIImageView']) && image_view_types('UIImageView', false, selector) != none
}

fn image_view_validate(image u64) {
	if image != 0 && (!objc_is_kind(image, ios_runtime.names['UIImage']) || obj_header(image).fields[0] == 0) { panic('iOS: image view requires a bitmap UIImage') }
	if image != 0 { bitmap_state(obj_header(image).fields[0]) }
}

fn image_view_size(image u64) ObjSize {
	if image == 0 { return ObjSize{} }
	header := obj_header(image)
	return ObjSize{f64(cg_bitmap_width(header.fields[0])) / header.content_scale, f64(cg_bitmap_height(header.fields[0])) / header.content_scale}
}

fn image_view_intrinsic(state &ImageViewState) ObjSize {
	return image_view_size(if state.images[0] != 0 { state.images[0] } else { state.images[1] })
}

fn image_view_frame(rect ObjRect) {
	for value in [rect.x, rect.y, rect.width, rect.height]! { if !math.is_finite(value) { panic('iOS: image view requires a finite frame') } }
	if rect.width < 0 || rect.height < 0 || rect.width > 8192 || rect.height > 8192 { panic('iOS: image view frame size is outside the supported range') }
}

fn image_view_initialize(object u64, normal u64, highlight u64, rect ObjRect, sized bool) {
	mut header := obj_header(object)
	if !header.image_view_owned || header.image_view != unsafe { nil } { panic('iOS: image view reinitialization is not implemented') }
	image_view_validate(normal); image_view_validate(highlight); image_view_frame(rect)
	header.image_view = unsafe { &ImageViewState(C.calloc(1, sizeof(ImageViewState))) }
	if header.image_view == unsafe { nil } { panic('iOS: cannot allocate image view state') }
	mut state := header.image_view
	state.images[0] = objc_retain(normal); state.images[1] = objc_retain(highlight)
	state.opaque = normal == 0 || cg_bitmap_info(obj_header(normal).fields[0]) & 31 in [u32(5), 6]
	state.dirty = true
	size := image_view_intrinsic(state)
	header.frame = if sized { ObjRect{0, 0, size.width, size.height} } else { rect }
}

fn image_view_path_clear(mut state ImageViewState) {
	if state.path.len == 0 { return }
	C.unlink(unsafe { &char(state.path.str) })
	unsafe { state.path.free() }
	state.path = ''
}

fn image_view_dispose(mut header ObjHeader) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	mut state := header.image_view
	if state == unsafe { nil } { return }
	image_view_path_clear(mut state)
	for value in state.images { objc_release(value) }
	for value in state.animations { objc_release(value) }
	C.free(state); header.image_view = unsafe { nil }
}

fn image_view_shutdown_files() {
	// The explicit _Exit lifecycle keeps native workers and objects alive.
	// Remove their published filenames without invoking destructors or freeing
	// storage those workers may still read, including views outside the tree.
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	for _, header in ios_runtime.objects {
		state := header.image_view
		if state != unsafe { nil } && state.path.len != 0 { C.unlink(unsafe { &char(state.path.str) }) }
	}
}

fn image_view_copy_images(array u64) u64 {
	if array == 0 { return 0 }
	if !objc_is_kind(array, ios_runtime.names['NSArray']) { panic('iOS: image view animation requires an array') }
	source := obj_header(array)
	if source.cf_raw_values || source.items.len > 256 { panic('iOS: image view animation array exceeds the supported profile') }
	for image in source.items { image_view_validate(image) }
	copy := objc_allocate(ios_runtime.names['NSArray'])
	mut target := obj_header(copy); target.image_view_array = true
	for image in source.items { array_append(mut target, image) }
	return copy
}

fn image_view_content_rect(bounds ObjRect, size ObjSize, mode i64) ObjRect {
	if size.width <= 0 || size.height <= 0 { return ObjRect{} }
	if mode in [i64(0), 3] { return bounds }
	mut width := size.width; mut height := size.height
	if mode in [i64(1), 2] {
		scale := if mode == 1 { math.min(bounds.width / width, bounds.height / height) } else { math.max(bounds.width / width, bounds.height / height) }
		width *= scale; height *= scale
	}
	mut x := (bounds.width - width) / 2; mut y := (bounds.height - height) / 2
	if mode in [i64(7), 9, 11] { x = 0 }
	if mode in [i64(8), 10, 12] { x = bounds.width - width }
	if mode in [i64(5), 9, 10] { y = 0 }
	if mode in [i64(6), 11, 12] { y = bounds.height - height }
	return ObjRect{bounds.x + x, bounds.y + y, width, height}
}

fn image_view_selected(state &ImageViewState) u64 {
	return if state.highlighted && state.images[1] != 0 { state.images[1] } else { state.images[0] }
}

fn image_view_draw(object u64, context u64) {
	state := obj_header(object).image_view
	if state == unsafe { nil } { panic('iOS: image view is not initialized') }
	image := image_view_selected(state)
	if context == 0 || image == 0 { return }
	bounds := ObjRect{0, 0, obj_header(object).frame.width, obj_header(object).frame.height}
	mut paint := bitmap_state(context); clip := paint.paint.clip
	if state.clips { cg_clip(context, bounds) }
	defer { paint.paint.clip = clip }
	bitmap_draw_image(context, image_view_content_rect(bounds, image_view_size(image), state.mode), obj_header(image).fields[0], true)
}

// Publish a cached PNG at the view's point dimensions. A new pathname prevents
// compositor image caches from reusing old pixels after a configuration change.
fn image_view_path(object u64) string {
	if u64(C.pthread_self()) != ios_runtime.main_thread { panic('iOS: image view publication requires the runtime main thread') }
	header := obj_header(object)
	mut state := header.image_view
	if state == unsafe { nil } { return '' }
	image := image_view_selected(state)
	if image == 0 || header.frame.width == 0 || header.frame.height == 0 { image_view_path_clear(mut state); return '' }
	width := int(math.ceil(header.frame.width)); height := int(math.ceil(header.frame.height))
	if width > 4096 || height > 4096 { panic('iOS: image view raster exceeds the desktop profile') }
	if state.path.len == 0 || state.dirty || state.width != width || state.height != height {
		bounds := ObjRect{0, 0, header.frame.width, header.frame.height}
		r := image_view_content_rect(bounds, image_view_size(image), state.mode)
		if !state.clips && (r.x < 0 || r.y < 0 || r.x + r.width > bounds.width + 1e-9 || r.y + r.height > bounds.height + 1e-9) { panic('iOS: image view overflow outside unclipped bounds is not implemented') }
		pool := objc_pool_push(); defer { objc_pool_pop(pool) }
		space := cg_rgb_space(); context := cg_bitmap_create(unsafe { nil }, u64(width), u64(height), 8, u64(width) * 4, space, 1); objc_release(space)
		if context == 0 { panic('iOS: cannot allocate image view raster') }
		defer { objc_release(context) }
		bitmap_state(context).paint.matrix = ObjTransform{f64(width) / bounds.width, 0, 0, -f64(height) / bounds.height, 0, f64(height)}
		image_view_draw(object, context)
		wrapped := ui_image_from_cg(context, 1); defer { objc_release(wrapped) }
		data := ui_png(wrapped); if data == 0 { panic('iOS: cannot encode image view raster') }
		state.sequence++
		mut path := [160]char{}
		length := C.snprintf(unsafe { &path[0] }, path.len, c'/tmp/vinix-ios-image-%d-%llu-%llu.png', C.getpid(), object, state.sequence)
		if length <= 0 || length >= path.len { panic('iOS: invalid image view raster path') }
		fd := C.open(unsafe { &path[0] }, C.O_CREAT | C.O_EXCL | C.O_WRONLY, 384)
		if fd < 0 { panic('iOS: cannot create image view raster file') }
		ok := wire_io(fd, unsafe { voidptr(data_pointer(data)) }, int(data_length(data)), true); C.close(fd)
		if !ok { C.unlink(unsafe { &path[0] }); panic('iOS: cannot write image view raster') }
		image_view_path_clear(mut state)
		state.path = ctext(u64(unsafe { &path[0] })).clone(); state.width = width; state.height = height; state.dirty = false
	}
	return state.path.clone()
}

fn image_view_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes || !objc_is_kind(object, ios_runtime.names['UIImageView']) { return false }
	if selector in ['init', 'initWithFrame:', 'initWithImage:', 'initWithImage:highlightedImage:'] {
		image_view_initialize(object, if selector.contains('Image:') { frame.x[2] } else { u64(0) }, if selector == 'initWithImage:highlightedImage:' { frame.x[3] } else { u64(0) }, if selector == 'initWithFrame:' { frame_rect(frame) } else { ObjRect{} }, selector.contains('Image:')); return true
	}
	if image_view_types('UIImageView', false, selector) == none { return false }
	mut state := obj_header(object).image_view
	if state == unsafe { nil } { panic('iOS: image view is not initialized') }
	match selector {
		'image', 'highlightedImage' { frame.x[0] = state.images[if selector == 'image' { 0 } else { 1 }] }
		'setImage:', 'setHighlightedImage:' {
			image_view_validate(frame.x[2]); index := if selector == 'setImage:' { 0 } else { 1 }
			objc_store_strong(unsafe { &state.images[index] }, frame.x[2]); state.dirty = true
			if index == 0 { state.opaque = frame.x[2] == 0 || cg_bitmap_info(obj_header(frame.x[2]).fields[0]) & 31 in [u32(5), 6] }
		}
		'animationImages', 'highlightedAnimationImages' { frame.x[0] = state.animations[if selector == 'animationImages' { 0 } else { 1 }] }
		'setAnimationImages:', 'setHighlightedAnimationImages:' { index := if selector == 'setAnimationImages:' { 0 } else { 1 }; copy := image_view_copy_images(frame.x[2]); objc_store_strong(unsafe { &state.animations[index] }, copy); objc_release(copy) }
		'isHighlighted' { frame.x[0] = u64(state.highlighted) }
		'setHighlighted:' { state.highlighted = u8(frame.x[2]) != 0; state.dirty = true }
		'isUserInteractionEnabled' { frame.x[0] = u64(state.interaction) }
		'setUserInteractionEnabled:' { state.interaction = u8(frame.x[2]) != 0 }
		'clipsToBounds' { frame.x[0] = u64(state.clips) }
		'setClipsToBounds:' { state.clips = u8(frame.x[2]) != 0; state.dirty = true }
		'isOpaque' { frame.x[0] = u64(state.opaque) }
		'setOpaque:' { state.opaque = u8(frame.x[2]) != 0 }
		'contentMode' { frame.x[0] = u64(state.mode) }
		'setContentMode:' { mode := i64(frame.x[2]); if mode < 0 || mode > 12 { panic('iOS: image view content mode is not supported') }; state.mode = mode; state.dirty = true }
		'animationRepeatCount' { frame.x[0] = u64(state.repeat_count) }
		'setAnimationRepeatCount:' { value := i64(frame.x[2]); if value < 0 { panic('iOS: image view animation count must be nonnegative') }; state.repeat_count = value }
		'animationDuration' { frame_float_return(mut frame, 0, state.duration) }
		'setAnimationDuration:' { value := frame_double(frame, 0); if !math.is_finite(value) || value < 0 { panic('iOS: image view animation duration must be finite and nonnegative') }; state.duration = value }
		'isAnimating' { frame.x[0] = 0 }
		'startAnimating' { for array in state.animations { if array != 0 && obj_header(array).items.len != 0 { panic('iOS: image view playback is not implemented') } } }
		'stopAnimating' {}
		'frame' { return_rect(mut frame, obj_header(object).frame) }
		'bounds' { r := obj_header(object).frame; return_rect(mut frame, ObjRect{0, 0, r.width, r.height}) }
		'setFrame:', 'setBounds:' {
			r := frame_rect(frame); image_view_frame(r); mut header := obj_header(object)
			if selector == 'setBounds:' { if r.x != 0 || r.y != 0 { panic('iOS: image view nonzero bounds origin is not implemented') }; header.frame.x += (header.frame.width - r.width) / 2; header.frame.y += (header.frame.height - r.height) / 2; header.frame.width = r.width; header.frame.height = r.height } else { header.frame = r }; state.dirty = true
		}
		'sizeToFit' { size := image_view_intrinsic(state); obj_header(object).frame.width = size.width; obj_header(object).frame.height = size.height; state.dirty = true }
		'sizeThatFits:', 'intrinsicContentSize' { size := image_view_intrinsic(state); absent := selector == 'intrinsicContentSize' && state.images[0] == 0 && state.images[1] == 0; frame_float_return(mut frame, 0, if absent { f64(-1) } else { size.width }); frame_float_return(mut frame, 1, if absent { f64(-1) } else { size.height }) }
		'drawRect:' { image_view_draw(object, ui_current_context()) }
		else { return false }
	}
	if selector.starts_with('set') || selector == 'sizeToFit' { ios_runtime.dirty = true }
	return true
}
