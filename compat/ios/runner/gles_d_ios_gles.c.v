// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math
import os

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <dlfcn.h>

fn C.eglGetPlatformDisplay(u32, voidptr, &i64) voidptr
fn C.eglInitialize(voidptr, &i32, &i32) u32
fn C.eglTerminate(voidptr) u32
fn C.eglBindAPI(u32) u32
fn C.eglChooseConfig(voidptr, &i32, &voidptr, i32, &i32) u32
fn C.eglCreateContext(voidptr, voidptr, voidptr, &i32) voidptr
fn C.eglDestroyContext(voidptr, voidptr) u32
fn C.eglCreatePbufferSurface(voidptr, voidptr, &i32) voidptr
fn C.eglDestroySurface(voidptr, voidptr) u32
fn C.eglMakeCurrent(voidptr, voidptr, voidptr, voidptr) u32
fn C.eglGetError() u32
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
fn C.glGenFramebuffers(i32, &u32)
fn C.glGenRenderbuffers(i32, &u32)
fn C.glDeleteFramebuffers(i32, &u32)
fn C.glDeleteRenderbuffers(i32, &u32)
fn C.glBindFramebuffer(u32, u32)
fn C.glBindRenderbuffer(u32, u32)
fn C.glRenderbufferStorage(u32, u32, i32, i32)
fn C.glFramebufferRenderbuffer(u32, u32, u32, u32)
fn C.glCheckFramebufferStatus(u32) u32
fn C.glViewport(i32, i32, i32, i32)
fn C.glFlush()
fn C.glGetString(u32) &char

struct GlesRuntime {
mut:
	display voidptr
	functions voidptr
	compression voidptr
	current_key u64
	initialized bool
}

struct GlesContext {
mut:
	native voidptr
	surface voidptr
	api int
}

struct GlesView {
mut:
	fbo u32
	color u32
	depth u32
	width i32
	height i32
	depth_format u32
	stencil_format u32
	enable_set_needs_display bool = true
	scale f64 = 1
	surface voidptr
	surface_size u64
	surface_path string
	surface_sequence u32
	rgba voidptr
}

__global gles_runtime = unsafe { &GlesRuntime(nil) }

fn gles_start() ! {
	gles_runtime = &GlesRuntime{}
	gles_runtime.functions = C.dlopen(c'libGLESv2.so.2', C.RTLD_NOW | C.RTLD_LOCAL)
	if gles_runtime.functions == unsafe { nil } { return error('iOS: cannot load Mesa GLES library') }
	gles_runtime.compression = C.dlopen(c'libz.so.1', C.RTLD_NOW | C.RTLD_LOCAL)
	if gles_runtime.compression == unsafe { nil } { C.dlclose(gles_runtime.functions); return error('iOS: cannot load native zlib') }
	if C.ios_key_create(unsafe { &gles_runtime.current_key }, unsafe { voidptr(gles_current_destructor) }) != 0 {
		C.dlclose(gles_runtime.functions)
		C.dlclose(gles_runtime.compression)
		return error('iOS: cannot create EAGL current-context TLS')
	}
	// The supplied driver lives beside the private Mesa dependency closure.
	if os.getenv('LIBGL_DRIVERS_PATH') == '' {
		C.setenv(c'LIBGL_DRIVERS_PATH', c'/usr/lib/vinix/ios-gles/dri', 0)
	}
	// Keep the first software-rendered launch independent of Mesa's disk-cache
	// path. An explicit environment setting still takes precedence.
	C.setenv(c'MESA_SHADER_CACHE_DISABLE', c'true', 0)
}

fn gles_stop() {
	gles_set_current(0)
	if gles_runtime.initialized { C.eglTerminate(gles_runtime.display) }
	C.pthread_key_delete(gles_runtime.current_key)
	C.dlclose(gles_runtime.functions)
	C.dlclose(gles_runtime.compression)
	C.free(gles_runtime)
	gles_runtime = unsafe { nil }
}

fn gles_symbol(symbol string) ?u64 {
	// GLES exports have the same ARM64 scalar/pointer ABI. Resolve only actual
	// symbols exported by Mesa, rather than manufacturing extension entry points.
	if !symbol.starts_with('_gl') { return none }
	name := symbol[1..]
	defer { unsafe { name.free() } }
	pointer := C.dlsym(gles_runtime.functions, unsafe { &char(name.str) })
	if pointer == unsafe { nil } { return none }
	return u64(pointer)
}

fn gles_zlib_symbol(symbol string) ?u64 {
	// ARM64 Darwin and musl z_stream use the same 112-byte public layout.
	// Only these checked entry points are exposed, with genuine zlib results.
	if symbol !in ['_crc32', '_deflate', '_deflateEnd', '_deflateInit2_', '_deflateReset',
		'_inflate', '_inflateEnd', '_inflateInit2_', '_inflateInit_', '_inflateReset', '_inflateReset2', '_uncompress'] { return none }
	name := symbol[1..]
	defer { unsafe { name.free() } }
	pointer := C.dlsym(gles_runtime.compression, unsafe { &char(name.str) })
	if pointer == unsafe { nil } { return none }
	return u64(pointer)
}

fn gles_initialize() bool {
	if gles_runtime.initialized { return true }
	display := C.eglGetPlatformDisplay(0x31dd, unsafe { nil }, unsafe { nil }) // EGL_PLATFORM_SURFACELESS_MESA
	mut major := i32(0)
	mut minor := i32(0)
	if display == unsafe { nil } || C.eglInitialize(display, &major, &minor) == 0 {
		eprintln('iOS: Mesa surfaceless initialization failed: 0x${C.eglGetError().hex()}')
		return false
	}
	gles_runtime.display = display
	gles_runtime.initialized = true
	return true
}

fn gles_create(object u64, api u64) bool {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if api !in [u64(2), 3] || !gles_initialize() { return false }
	if C.eglBindAPI(C.EGL_OPENGL_ES_API) == 0 { return false }
	attributes := [i32(C.EGL_SURFACE_TYPE), C.EGL_PBUFFER_BIT,
		C.EGL_RENDERABLE_TYPE, if api == 3 { C.EGL_OPENGL_ES3_BIT } else { C.EGL_OPENGL_ES2_BIT },
		C.EGL_RED_SIZE, 8, C.EGL_GREEN_SIZE, 8, C.EGL_BLUE_SIZE, 8, C.EGL_ALPHA_SIZE, 8, C.EGL_NONE]!
	mut config := unsafe { voidptr(nil) }
	mut count := i32(0)
	if C.eglChooseConfig(gles_runtime.display, unsafe { &attributes[0] }, &config, 1, &count) == 0 || count == 0 { return false }
	context_attributes := [i32(C.EGL_CONTEXT_CLIENT_VERSION), i32(api), C.EGL_NONE]!
	native := C.eglCreateContext(gles_runtime.display, config, unsafe { nil }, unsafe { &context_attributes[0] })
	if native == unsafe { nil } { return false }
	// The view owns an FBO; the current context needs only a tiny default surface.
	surface_attributes := [i32(C.EGL_WIDTH), 1, C.EGL_HEIGHT, 1, C.EGL_NONE]!
	surface := C.eglCreatePbufferSurface(gles_runtime.display, config, unsafe { &surface_attributes[0] })
	if surface == unsafe { nil } { C.eglDestroyContext(gles_runtime.display, native); return false }
	mut context := unsafe { &GlesContext(C.calloc(1, sizeof(GlesContext))) }
	if context == unsafe { nil } { panic('iOS: cannot allocate EAGL context state') }
	context.native = native
	context.surface = surface
	context.api = int(api)
	mut header := obj_header(object)
	header.graphics = context
	if ios_runtime.trace { eprintln('iOS: created Mesa EAGL context, requested ES ${api}') }
	return true
}

fn gles_current() u64 { return u64(C.pthread_getspecific(gles_runtime.current_key)) }

fn gles_set_current(object u64) bool {
	if gles_current() == object { return true }
	mut native := unsafe { voidptr(nil) }
	mut surface := unsafe { voidptr(nil) }
	if object != 0 {
		if !objc_is_kind(object, ios_runtime.names['EAGLContext']) { return false }
		state := obj_header(object).graphics
		if state == unsafe { nil } { return false }
		context := unsafe { &GlesContext(state) }
		native = context.native
		surface = context.surface
	}
	if gles_runtime.initialized && C.eglMakeCurrent(gles_runtime.display, surface, surface, native) == 0 { return false }
	previous := gles_current()
	objc_retain(object) // EAGL keeps a strong reference on each thread.
	if C.pthread_setspecific(gles_runtime.current_key, unsafe { voidptr(object) }) != 0 { panic('iOS: cannot set EAGL TLS') }
	objc_release(previous)
	return true
}

fn gles_current_destructor(pointer voidptr) {
	C.eglMakeCurrent(gles_runtime.display, unsafe { nil }, unsafe { nil }, unsafe { nil })
	objc_release(u64(pointer))
}

fn gles_view_delete(object u64) {
	state := obj_header(object).graphics
	if state == unsafe { nil } { return }
	mut view := unsafe { &GlesView(state) }
	if view.fbo == 0 { return }
	previous := objc_retain(gles_current())
	if !gles_set_current(obj_header(object).fields[8]) { panic('iOS: GLKView drawable deletion cannot make context current') }
	C.glDeleteFramebuffers(1, &view.fbo)
	C.glDeleteRenderbuffers(1, &view.color)
	if view.depth != 0 { C.glDeleteRenderbuffers(1, &view.depth) }
	view.fbo = 0
	view.color = 0
	view.depth = 0
	view.width = 0
	view.height = 0
	gles_surface_close(mut view)
	if !gles_set_current(previous) { panic('iOS: cannot restore EAGL context after drawable deletion') }
	objc_release(previous)
}

fn gles_view_bind(object u64) {
	mut header := obj_header(object)
	if header.graphics == unsafe { nil } { panic('iOS: GLKView has not been initialized') }
	mut view := unsafe { &GlesView(header.graphics) }
	if !gles_set_current(header.fields[8]) { panic('iOS: GLKView cannot make context current') }
	pixel_width := math.ceil(header.frame.width * view.scale)
	pixel_height := math.ceil(header.frame.height * view.scale)
	if !math.is_finite(pixel_width) || !math.is_finite(pixel_height) || pixel_width < 1 || pixel_height < 1 || pixel_width > 8192 || pixel_height > 8192 { panic('iOS: invalid GLKView drawable dimensions') }
	width := i32(pixel_width)
	height := i32(pixel_height)
	if view.fbo != 0 && (view.width != width || view.height != height) { gles_view_delete(object) }
	if view.fbo == 0 {
		C.glGenFramebuffers(1, &view.fbo)
		C.glBindFramebuffer(C.GL_FRAMEBUFFER, view.fbo)
		C.glGenRenderbuffers(1, &view.color)
		C.glBindRenderbuffer(C.GL_RENDERBUFFER, view.color)
		C.glRenderbufferStorage(C.GL_RENDERBUFFER, C.GL_RGBA8, width, height)
		C.glFramebufferRenderbuffer(C.GL_FRAMEBUFFER, C.GL_COLOR_ATTACHMENT0, C.GL_RENDERBUFFER, view.color)
		if view.depth_format != 0 || view.stencil_format != 0 {
			C.glGenRenderbuffers(1, &view.depth)
			C.glBindRenderbuffer(C.GL_RENDERBUFFER, view.depth)
			format := if view.stencil_format != 0 { u32(C.GL_DEPTH24_STENCIL8) }
				else if view.depth_format == 1 { u32(C.GL_DEPTH_COMPONENT16) } else { u32(C.GL_DEPTH_COMPONENT24) }
			C.glRenderbufferStorage(C.GL_RENDERBUFFER, format, width, height)
			if view.depth_format != 0 { C.glFramebufferRenderbuffer(C.GL_FRAMEBUFFER, C.GL_DEPTH_ATTACHMENT, C.GL_RENDERBUFFER, view.depth) }
			if view.stencil_format != 0 { C.glFramebufferRenderbuffer(C.GL_FRAMEBUFFER, C.GL_STENCIL_ATTACHMENT, C.GL_RENDERBUFFER, view.depth) }
		}
		if C.glCheckFramebufferStatus(C.GL_FRAMEBUFFER) != C.GL_FRAMEBUFFER_COMPLETE { panic('iOS: GLKView framebuffer is incomplete') }
		view.width = width
		view.height = height
		if ios_runtime.trace { eprintln('iOS: GLKView framebuffer ${width}x${height}, depth format ${view.depth_format}, stencil format ${view.stencil_format}') }
	}
	C.glBindFramebuffer(C.GL_FRAMEBUFFER, view.fbo)
	C.glViewport(0, 0, width, height)
}

type GlesDraw = fn (u64, &char, u64, ObjRect)

fn gles_view_display(object u64) {
	gles_view_bind(object)
	header := obj_header(object)
	delegate := objc_load_weak(unsafe { &header.target })
	defer { objc_release(delegate) }
	if delegate == 0 { return }
	imp := native_method(read64(delegate), 'glkView:drawInRect:')
	if imp == 0 { panic('iOS: GLKView delegate has no draw callback') }
	unsafe { GlesDraw(voidptr(imp))(delegate, c'glkView:drawInRect:', object, ObjRect{0, 0, header.frame.width, header.frame.height}) }
	C.glFlush()
	gles_surface_publish(object)
	ios_runtime.dirty = true
}

fn gles_dispose(object u64) {
	mut header := obj_header(object)
	if header.graphics == unsafe { nil } { return }
	if objc_is_kind(object, ios_runtime.names['GLKView']) { gles_view_delete(object) }
	else if objc_is_kind(object, ios_runtime.names['EAGLContext']) {
		context := unsafe { &GlesContext(header.graphics) }
		C.eglDestroySurface(gles_runtime.display, context.surface)
		C.eglDestroyContext(gles_runtime.display, context.native)
	}
	C.free(header.graphics)
	header.graphics = unsafe { nil }
}

fn gles_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object in ios_runtime.classes {
		if object != ios_runtime.names['EAGLContext'] { return false }
		match selector {
			'currentContext' { frame.x[0] = gles_current() }
			'setCurrentContext:' { frame.x[0] = u64(gles_set_current(frame.x[2])) }
			else { return false }
		}
		return true
	}
	mut header := obj_header(object)
	if objc_is_kind(object, ios_runtime.names['EAGLContext']) {
		match selector {
			'initWithAPI:' {
				if header.graphics != unsafe { nil } { panic('iOS: EAGLContext initialized twice') }
				if !gles_create(object, frame.x[2]) { objc_release(object); frame.x[0] = 0 }
			}
			'API' {
				if header.graphics == unsafe { nil } { panic('iOS: EAGLContext is not initialized') }
				frame.x[0] = u64(unsafe { &GlesContext(header.graphics) }.api)
			}
			else { return false }
		}
		return true
	}
	if !objc_is_kind(object, ios_runtime.names['GLKView']) { return false }
	if selector == 'initWithFrame:context:' {
		if header.graphics != unsafe { nil } { panic('iOS: GLKView initialized twice') }
		if !objc_is_kind(frame.x[2], ios_runtime.names['EAGLContext']) { panic('iOS: GLKView requires an EAGLContext') }
		header.frame = frame_rect(frame)
		header.graphics = C.calloc(1, sizeof(GlesView))
		if header.graphics == unsafe { nil } { panic('iOS: cannot allocate GLKView state') }
		mut view := unsafe { &GlesView(header.graphics) }
		view.enable_set_needs_display = true
		view.scale = 1 // One drawable pixel per point until explicitly scaled.
		store_field(object, 8, frame.x[2])
		return true
	}
	if header.graphics == unsafe { nil } { return false }
	mut view := unsafe { &GlesView(header.graphics) }
	match selector {
		'context' { frame.x[0] = header.fields[8] }
		'setContext:' {
			if frame.x[2] != 0 && !objc_is_kind(frame.x[2], ios_runtime.names['EAGLContext']) { panic('iOS: GLKView requires an EAGLContext') }
			gles_view_delete(object); store_field(object, 8, frame.x[2])
		}
		'delegate' { frame.x[0] = objc_autorelease(objc_load_weak(unsafe { &header.target })) }
		'setDelegate:' { objc_store_weak(unsafe { &header.target }, frame.x[2]) }
		'enableSetNeedsDisplay' { frame.x[0] = u64(view.enable_set_needs_display) }
		'setEnableSetNeedsDisplay:' { view.enable_set_needs_display = frame.x[2] != 0 }
		'drawableDepthFormat' { frame.x[0] = view.depth_format }
		'drawableStencilFormat' { frame.x[0] = view.stencil_format }
		'drawableColorFormat', 'drawableMultisample' { frame.x[0] = 0 }
		'setDrawableDepthFormat:' {
			if frame.x[2] !in [u64(0), 1, 2] { panic('iOS: unsupported GLKView depth format') }
			gles_view_delete(object); view.depth_format = u32(frame.x[2])
		}
		'setDrawableStencilFormat:' {
			if frame.x[2] !in [u64(0), 1] { panic('iOS: unsupported GLKView stencil format') }
			gles_view_delete(object); view.stencil_format = u32(frame.x[2])
		}
		'setDrawableColorFormat:', 'setDrawableMultisample:' {
			if frame.x[2] != 0 { panic('iOS: GLKView only supports RGBA8888 without multisampling') }
		}
		'contentScaleFactor' { frame_float_return(mut frame, 0, view.scale) }
		'setContentScaleFactor:' {
			scale := frame_double(frame, 0)
			if scale <= 0 || scale > 8 || !math.is_finite(scale) { panic('iOS: invalid GLKView content scale') }
			view.scale = scale
		}
		'drawableWidth' { frame.x[0] = u64(view.width) }
		'drawableHeight' { frame.x[0] = u64(view.height) }
		'bindDrawable' { gles_view_bind(object) }
		'deleteDrawable' { gles_view_delete(object) }
		'display' { gles_view_display(object) }
		else { return false }
	}
	return true
}
