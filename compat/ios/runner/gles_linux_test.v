// SPDX-License-Identifier: GPL-2.0-or-later
// Real GNU/Linux Mesa execution through the ARM64 Objective-C entry point.
// API2 is checked on its EGL pbuffer; GLKView publication requires ES3 here.
module main

$if ios_gles ? {
	import os
	import time

	fn C.glGetError() u32
	fn C.glClearColor(f32, f32, f32, f32)
	fn C.glClear(u32)
	fn C.glCreateShader(u32) u32
	fn C.glShaderSource(u32, i32, &&char, &i32)
	fn C.glCompileShader(u32)
	fn C.glGetShaderiv(u32, u32, &i32)
	fn C.glGetShaderInfoLog(u32, i32, &i32, &char)
	fn C.glDeleteShader(u32)
	fn C.glCreateProgram() u32
	fn C.glAttachShader(u32, u32)
	fn C.glLinkProgram(u32)
	fn C.glGetProgramiv(u32, u32, &i32)
	fn C.glGetProgramInfoLog(u32, i32, &i32, &char)
	fn C.glUseProgram(u32)
	fn C.glDeleteProgram(u32)
	fn C.glGenVertexArrays(i32, &u32)
	fn C.glBindVertexArray(u32)
	fn C.glDeleteVertexArrays(i32, &u32)
	fn C.glDrawArrays(u32, i32, i32)
	fn C.glGenBuffers(i32, &u32)
	fn C.glBufferData(u32, isize, voidptr, u32)
	fn C.glDeleteBuffers(i32, &u32)
	fn C.glIsFramebuffer(u32) u8

	type LinuxGlesSend = fn (u64, u64, u64) u64
	type LinuxGlesRectInit = fn (u64, u64, ObjRect, u64) u64
	type LinuxGlesRectSet = fn (u64, u64, ObjRect) u64
	type LinuxGlesDoubleSet = fn (u64, u64, f64)
	type LinuxGlesDoubleGet = fn (u64, u64) f64
	type LinuxGlesIntSet = fn (u64, u64, i32)
	type LinuxGlesClear = fn (f32, f32, f32, f32)
	type LinuxGlesDrawArrays = fn (u32, i32, i32)

	struct LinuxGlesProbe {
	mut:
		view        u64
		context     u64
		program     u32
		vao         u32
		read_fbo    u32
		read_color  u32
		pack_buffer u32
		width       i32
		height      i32
		points      ObjRect
		draws       int
		blue        bool
	}

	__global linux_gles_probe = unsafe { &LinuxGlesProbe(nil) }

	fn linux_gles_message(object u64, selector &char, argument u64) u64 {
		return unsafe { LinuxGlesSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument) }
	}

	fn linux_gles_context(api u64) u64 {
		cls := ios_runtime.names['EAGLContext']
		object := linux_gles_message(cls, c'alloc', 0)
		return linux_gles_message(object, c'initWithAPI:', api)
	}

	fn linux_gles_current() u64 {
		return linux_gles_message(ios_runtime.names['EAGLContext'], c'currentContext', 0)
	}

	fn linux_gles_set_current(object u64) {
		assert linux_gles_message(ios_runtime.names['EAGLContext'], c'setCurrentContext:', object) == 1
		assert linux_gles_current() == object
	}

	fn linux_gles_signature(object u64, selector &char, encoding string, returns string, length u64, arguments []string) {
		assert linux_gles_message(object, c'respondsToSelector:', u64(selector)) == 1, unsafe { cstring_to_vstring(selector) }
		method := objc_instance_method(read64(object), u64(selector))
		assert method != 0 && ctext(u64(objc_method_types(method))) == encoding
		signature := linux_gles_message(object, c'methodSignatureForSelector:', u64(selector))
		assert signature != 0
		assert linux_gles_message(signature, c'methodReturnLength', 0) == length
		assert ctext(linux_gles_message(signature, c'methodReturnType', 0)) == returns
		assert linux_gles_message(signature, c'numberOfArguments', 0) == u64(arguments.len + 2)
		assert ctext(linux_gles_message(signature, c'getArgumentTypeAtIndex:', 0)) == '@'
		assert ctext(linux_gles_message(signature, c'getArgumentTypeAtIndex:', 1)) == ':'
		for i, expected in arguments {
			assert ctext(linux_gles_message(signature, c'getArgumentTypeAtIndex:', u64(i + 2))) == expected
		}
	}

	fn linux_gles_metadata(subclass u64, context u64, view u64) {
		for cls in [ios_runtime.names['EAGLContext'], subclass]! {
			linux_gles_signature(cls, c'currentContext', '@16@0:8', '@', 8, [])
			linux_gles_signature(cls, c'setCurrentContext:', 'B24@0:8@16', 'B', 1, ['@'])
			assert linux_gles_message(cls, c'respondsToSelector:', u64(c'initWithAPI:')) == 0
		}
		linux_gles_signature(context, c'initWithAPI:', '@24@0:8Q16', '@', 8, ['Q'])
		linux_gles_signature(context, c'API', 'Q16@0:8', 'Q', 8, [])
		// Aggregate NSMethodSignature values are outside the existing invocation
		// profile. Check raw method metadata here; the initializer executes the
		// real HFA/FP argument path through the ARM64 message trampoline.
		assert linux_gles_message(view, c'respondsToSelector:', u64(c'initWithFrame:context:')) == 1
		initializer := objc_instance_method(read64(view), u64(c'initWithFrame:context:'))
		assert initializer != 0
		assert ctext(u64(objc_method_types(initializer))) == '@56@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16@48'
		for selector in [c'context', c'delegate']! {
			linux_gles_signature(view, selector, '@16@0:8', '@', 8, [])
		}
		for selector in [c'setContext:', c'setDelegate:']! {
			linux_gles_signature(view, selector, 'v24@0:8@16', 'v', 0, ['@'])
		}
		for selector in [c'drawableWidth', c'drawableHeight']! {
			linux_gles_signature(view, selector, 'q16@0:8', 'q', 8, [])
		}
		for selector in [c'drawableColorFormat', c'drawableDepthFormat', c'drawableStencilFormat',
			c'drawableMultisample']! {
			linux_gles_signature(view, selector, 'i16@0:8', 'i', 4, [])
		}
		for selector in [c'setDrawableColorFormat:', c'setDrawableDepthFormat:',
			c'setDrawableStencilFormat:', c'setDrawableMultisample:']! {
			linux_gles_signature(view, selector, 'v20@0:8i16', 'v', 0, ['i'])
		}
		linux_gles_signature(view, c'enableSetNeedsDisplay', 'B16@0:8', 'B', 1, [])
		linux_gles_signature(view, c'setEnableSetNeedsDisplay:', 'v20@0:8B16', 'v', 0, ['B'])
		linux_gles_signature(view, c'contentScaleFactor', 'd16@0:8', 'd', 8, [])
		linux_gles_signature(view, c'setContentScaleFactor:', 'v24@0:8d16', 'v', 0, ['d'])
		for selector in [c'bindDrawable', c'deleteDrawable', c'display']! {
			linux_gles_signature(view, selector, 'v16@0:8', 'v', 0, [])
		}
		for selector in [c'currentContext', c'setCurrentContext:', c'sharegroup',
			c'initWithAPI:sharegroup:', c'renderbufferStorage:fromDrawable:', c'presentRenderbuffer:',
			c'bindDrawable']! {
			assert linux_gles_message(context, c'respondsToSelector:', u64(selector)) == 0
			assert linux_gles_message(context, c'methodSignatureForSelector:', u64(selector)) == 0
		}
		for selector in [c'API', c'initWithAPI:', c'glkViewInventedEntry']! {
			assert linux_gles_message(view, c'respondsToSelector:', u64(selector)) == 0
			assert linux_gles_message(view, c'methodSignatureForSelector:', u64(selector)) == 0
		}
	}

	fn linux_gles_integer(name u32) i32 {
		mut value := i32(-1)
		C.glGetIntegerv(name, &value)
		return value
	}

	fn linux_gles_error(where string) {
		result := C.glGetError()
		assert result == 0, '${where}: GLES error 0x${result.hex()}'
	}

	fn linux_gles_clear(blue bool) {
		address := runtime_symbol('/System/Library/Frameworks/OpenGLES.framework/OpenGLES', '_glClearColor') or { panic(err) }
		unsafe {
			LinuxGlesClear(voidptr(address))(if blue { f32(0) } else { f32(1) }, 0, if blue {
				f32(1)
			} else {
				f32(0)
			}, 1)
		}
		C.glClear(C.GL_COLOR_BUFFER_BIT | C.GL_DEPTH_BUFFER_BIT | C.GL_STENCIL_BUFFER_BIT)
	}

	fn linux_gles_pixel(x i32, y i32, expected [4]u8) {
		mut actual := [4]u8{}
		C.glReadPixels(x, y, 1, 1, C.GL_RGBA, C.GL_UNSIGNED_BYTE, &actual[0])
		assert actual == expected, 'pixel (${x}, ${y}) differs from the rendered color'
	}

	fn linux_gles_shader(kind u32, source &char) u32 {
		shader := C.glCreateShader(kind)
		assert shader != 0
		mut sources := [source]!
		C.glShaderSource(shader, 1, &sources[0], unsafe { nil })
		C.glCompileShader(shader)
		mut compiled := i32(0)
		C.glGetShaderiv(shader, C.GL_COMPILE_STATUS, &compiled)
		if compiled == 0 {
			mut log := [4096]char{}
			C.glGetShaderInfoLog(shader, log.len, unsafe { nil }, &log[0])
			panic('GLES shader: ' + unsafe { cstring_to_vstring(&log[0]) })
		}
		return shader
	}

	fn linux_gles_program() u32 {
		vertex := linux_gles_shader(C.GL_VERTEX_SHADER, c'#version 300 es\nconst vec2 p[3]=vec2[3](vec2(-1,-1),vec2(1,-1),vec2(0,1));\nvoid main(){gl_Position=vec4(p[gl_VertexID],0,1);}\n')
		fragment := linux_gles_shader(C.GL_FRAGMENT_SHADER, c'#version 300 es\nprecision highp float;out vec4 c;\nvoid main(){c=vec4(0,1,0,1);}\n')
		program := C.glCreateProgram()
		assert program != 0
		C.glAttachShader(program, vertex)
		C.glAttachShader(program, fragment)
		C.glLinkProgram(program)
		mut linked := i32(0)
		C.glGetProgramiv(program, C.GL_LINK_STATUS, &linked)
		if linked == 0 {
			mut log := [4096]char{}
			C.glGetProgramInfoLog(program, log.len, unsafe { nil }, &log[0])
			panic('GLES program: ' + unsafe { cstring_to_vstring(&log[0]) })
		}
		C.glDeleteShader(vertex)
		C.glDeleteShader(fragment)
		return program
	}

	fn linux_gles_pack_defaults() {
		C.glBindBuffer(C.GL_PIXEL_PACK_BUFFER, 0)
		C.glPixelStorei(C.GL_PACK_ALIGNMENT, 4)
		C.glPixelStorei(C.GL_PACK_ROW_LENGTH, 0)
		C.glPixelStorei(C.GL_PACK_SKIP_ROWS, 0)
		C.glPixelStorei(C.GL_PACK_SKIP_PIXELS, 0)
	}

	fn linux_gles_draw(_ u64, selector &char, object u64, rect ObjRect) {
		mut probe := linux_gles_probe
		assert probe != unsafe { nil } && object == probe.view
		assert C.strcmp(selector, c'glkView:drawInRect:') == 0
		assert rect == ObjRect{0, 0, probe.points.width, probe.points.height}
		assert linux_gles_current() == probe.context
		assert linux_gles_message(object, c'drawableWidth', 0) == u64(probe.width)
		assert linux_gles_message(object, c'drawableHeight', 0) == u64(probe.height)
		mut viewport := [4]i32{}
		C.glGetIntegerv(C.GL_VIEWPORT, &viewport[0])
		assert viewport == [i32(0), 0, probe.width, probe.height]!
		linux_gles_pack_defaults()
		C.glReadBuffer(C.GL_COLOR_ATTACHMENT0)
		linux_gles_clear(probe.blue)
		C.glUseProgram(probe.program)
		C.glBindVertexArray(probe.vao)
		address := runtime_symbol('/System/Library/Frameworks/OpenGLES.framework/OpenGLES', '_glDrawArrays') or { panic(err) }
		unsafe { LinuxGlesDrawArrays(voidptr(address))(C.GL_TRIANGLES, 0, 3) }
		linux_gles_pixel(probe.width / 2, probe.height / 2, [u8(0), 255, 0, 255]!)
		linux_gles_pixel(3, 1, [u8(0), 255, 0, 255]!)
		linux_gles_pixel(3, probe.height - 2, if probe.blue {
			[u8(0), 0, 255, 255]!
		} else {
			[u8(255), 0, 0, 255]!
		})
		linux_gles_error('shader draw and pixels')
		// Publication must preserve both the drawable's READ_BUFFER state and
		// the caller's different read framebuffer, PBO and pixel packing state.
		C.glReadBuffer(C.GL_NONE)
		C.glBindFramebuffer(C.GL_READ_FRAMEBUFFER, probe.read_fbo)
		C.glReadBuffer(C.GL_COLOR_ATTACHMENT0)
		C.glBindBuffer(C.GL_PIXEL_PACK_BUFFER, probe.pack_buffer)
		C.glPixelStorei(C.GL_PACK_ALIGNMENT, 8)
		C.glPixelStorei(C.GL_PACK_ROW_LENGTH, probe.width + 3)
		C.glPixelStorei(C.GL_PACK_SKIP_ROWS, 1)
		C.glPixelStorei(C.GL_PACK_SKIP_PIXELS, 2)
		probe.draws++
	}

	fn linux_gles_readback_state(probe &LinuxGlesProbe) {
		view := unsafe { &GlesView(obj_header(probe.view).graphics) }
		assert linux_gles_integer(C.GL_READ_FRAMEBUFFER_BINDING) == i32(probe.read_fbo)
		assert linux_gles_integer(C.GL_DRAW_FRAMEBUFFER_BINDING) == i32(view.fbo)
		assert linux_gles_integer(C.GL_READ_BUFFER) == C.GL_COLOR_ATTACHMENT0
		assert linux_gles_integer(C.GL_PIXEL_PACK_BUFFER_BINDING) == i32(probe.pack_buffer)
		assert linux_gles_integer(C.GL_PACK_ALIGNMENT) == 8
		assert linux_gles_integer(C.GL_PACK_ROW_LENGTH) == probe.width + 3
		assert linux_gles_integer(C.GL_PACK_SKIP_ROWS) == 1
		assert linux_gles_integer(C.GL_PACK_SKIP_PIXELS) == 2
		C.glBindFramebuffer(C.GL_READ_FRAMEBUFFER, view.fbo)
		assert linux_gles_integer(C.GL_READ_BUFFER) == C.GL_NONE
		C.glBindFramebuffer(C.GL_READ_FRAMEBUFFER, probe.read_fbo)
		linux_gles_error('shared-surface state restoration')
	}

	fn linux_gles_surface_pixel(view &GlesView, x i32, y i32) u32 {
		base := u64(view.surface)
		active := C.ios_surface_load(unsafe { &u32(base + 28) })
		assert active < 2
		return read32(base + 48 + u64(active) * u64(view.width) * u64(view.height) * 4 + u64(y * view.width + x) * 4)
	}

	fn linux_gles_surface(probe &LinuxGlesProbe) {
		view := unsafe { &GlesView(obj_header(probe.view).graphics) }
		assert view.surface != unsafe { nil } && os.is_file(view.surface_path)
		assert gles_image_path(probe.view) == 'vinix-surface:' + view.surface_path
		assert view.surface_size == u64(48 + 2 * probe.width * probe.height * 4)
		base := u64(view.surface)
		for index, expected in [u32(0x31534656), 1, 48, u32(probe.width), u32(probe.height),
			u32(probe.width * 4), 1]! {
			assert read32(base + u64(index) * 4) == expected
		}
		assert linux_gles_surface_pixel(view, probe.width / 2, probe.height / 2) == 0xff00ff00
		assert linux_gles_surface_pixel(view, 3, probe.height - 2) == 0xff00ff00
		assert linux_gles_surface_pixel(view, 3, 1) == if probe.blue {
			u32(0xff0000ff)
		} else {
			u32(0xffff0000)
		}
	}

	fn linux_gles_write_frame(view &GlesView, cycle int) ! {
		directory := os.getenv('VINIX_IOS_GLES_FRAME_DIR')
		if directory == '' { return }
		if !os.is_dir(directory) {
			return error('VINIX_IOS_GLES_FRAME_DIR must be an existing external directory')
		}
		variant := if os.getenv('SWIFT_DETERMINISTIC_HASHING') == '1' {
			'deterministic'
		} else {
			'ordinary'
		}
		path := directory + '/gles-' + variant + '-' + cycle.str() + '.ppm'
		mut bytes := 'P6\n${view.width} ${view.height}\n255\n'.bytes()
		defer { unsafe { bytes.free() } }
		for y in 0 .. view.height {
			for x in 0 .. view.width {
				pixel := linux_gles_surface_pixel(view, x, y)
				bytes << u8(pixel >> 16)
				bytes << u8(pixel >> 8)
				bytes << u8(pixel)
			}
		}
		fd := C.open(path.str, C.O_CREAT | C.O_EXCL | C.O_WRONLY, 384)
		if fd < 0 { return os.error_posix() }
		mut offset := 0
		for offset < bytes.len {
			count := C.write(fd, unsafe { &bytes[offset] }, usize(bytes.len - offset))
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			if count <= 0 {
				C.close(fd)
				return error('cannot write GLES frame artifact')
			}
			offset += int(count)
		}
		if C.close(fd) != 0 { return os.error_posix() }
	}

	struct LinuxGlesThread {
		context u64
	mut:
		ready u64
		leave u64
	}

	fn linux_gles_wait(value &u64) {
		deadline := time.sys_mono_now() + 30 * time.second
		for C.ios_load_pointer(value) == 0 {
			assert time.sys_mono_now() < deadline, 'EAGL thread rendezvous timed out'
			time.sleep(time.millisecond)
		}
	}

	fn linux_gles_thread(pointer voidptr) voidptr {
		state := unsafe { &LinuxGlesThread(pointer) }
		assert linux_gles_current() == 0
		linux_gles_set_current(state.context)
		assert linux_gles_message(state.context, c'API', 0) == 2
		assert C.glGetString(C.GL_VERSION) != unsafe { nil }
		linux_gles_clear(true)
		linux_gles_pixel(0, 0, [u8(0), 0, 255, 255]!)
		linux_gles_error('API2 pbuffer')
		C.ios_store_pointer(unsafe { &state.ready }, 1)
		linux_gles_wait(unsafe { &state.leave })
		// Leave the last owning reference in the EAGL TLS key. Native pthread
		// teardown must unbind and release it before the adapter join returns.
		return unsafe { nil }
	}

	fn linux_gles_thread_case(main_context u64) {
		other := linux_gles_context(2)
		assert other != 0
		mut weak := u64(0)
		objc_store_weak(unsafe { &weak }, other)
		mut state := LinuxGlesThread{ context: other }
		mut handle := u64(0)
		assert darwin_pthread_create(unsafe { &handle }, unsafe { nil }, unsafe { voidptr(linux_gles_thread) }, unsafe { &state }) == 0
		linux_gles_wait(unsafe { &state.ready })
		linux_gles_message(other, c'release', 0)
		assert weak == other && linux_gles_current() == main_context
		C.ios_store_pointer(unsafe { &state.leave }, 1)
		assert darwin_pthread_join(handle, unsafe { nil }) == 0
		assert weak == 0 && linux_gles_current() == main_context
		objc_destroy_weak(unsafe { &weak })
		linux_gles_pixel(0, 0, [u8(255), 0, 0, 255]!)
		linux_gles_error('thread current-context isolation')
	}

	fn linux_gles_case(cycle int) ! {
		objc_start()
		system_data_start()!
		gles_start()!
		pool := objc_pool_push()
		assert linux_gles_current() == 0
		assert linux_gles_context(1) == 0 && linux_gles_context(4) == 0
		subclass := objc_allocate_class(ios_runtime.names['EAGLContext'], c'LinuxGlesInheritedContext', 0)
		assert subclass != 0
		objc_register_class(subclass)
		assert linux_gles_message(subclass, c'currentContext', 0) == 0
		context := linux_gles_message(linux_gles_message(subclass, c'alloc', 0), c'initWithAPI:', 3)
		assert context != 0 && linux_gles_message(context, c'API', 0) == 3
		assert linux_gles_message(subclass, c'setCurrentContext:', context) == 1
		assert linux_gles_current() == context
		version := C.glGetString(C.GL_VERSION)
		renderer := C.glGetString(C.GL_RENDERER)
		vendor := C.glGetString(C.GL_VENDOR)
		assert version != unsafe { nil } && renderer != unsafe { nil } && vendor != unsafe { nil }
		assert unsafe { cstring_to_vstring(version) }.contains('OpenGL ES 3.')
		assert C.strcmp(renderer, c'softpipe') == 0, 'the qualified software renderer must be softpipe'
		println('IOS-LINUX-GLES-RENDERER: ' + unsafe { cstring_to_vstring(renderer) } + '; ' + unsafe { cstring_to_vstring(version) } + '; vendor=' + unsafe { cstring_to_vstring(vendor) })
		if _ := runtime_symbol('/System/Library/Frameworks/OpenGLES.framework/OpenGLES', '_glVinixInventedEntry') {
			assert false, 'unknown GLES export was manufactured'
		}
		linux_gles_clear(false)
		linux_gles_thread_case(context)
		mut weak_context := u64(0)
		objc_store_weak(unsafe { &weak_context }, context)
		view := linux_gles_message(ios_runtime.names['GLKView'], c'alloc', 0)
		initial := ObjRect{4, 7, 32, 24}
		assert unsafe { LinuxGlesRectInit(voidptr(C.ios_objc_msgsend))(view, u64(c'initWithFrame:context:'), initial, context) } == view
		assert linux_gles_message(view, c'context', 0) == context
		linux_gles_metadata(subclass, context, view)
		unsafe { LinuxGlesIntSet(voidptr(C.ios_objc_msgsend))(view, u64(c'setDrawableDepthFormat:'), 2) }
		unsafe { LinuxGlesIntSet(voidptr(C.ios_objc_msgsend))(view, u64(c'setDrawableStencilFormat:'), 1) }
		// Upper register bits are outside the public GLint/BOOL parameter ABI.
		linux_gles_message(view, c'setDrawableDepthFormat:', 0xfeedface00000002)
		linux_gles_message(view, c'setDrawableStencilFormat:', 0xfeedface00000001)
		linux_gles_message(view, c'setDrawableColorFormat:', 0xfeedface00000000)
		linux_gles_message(view, c'setDrawableMultisample:', 0xfeedface00000000)
		assert linux_gles_message(view, c'drawableDepthFormat', 0) == 2
		assert linux_gles_message(view, c'drawableStencilFormat', 0) == 1
		assert linux_gles_message(view, c'drawableColorFormat', 0) == 0
		assert linux_gles_message(view, c'drawableMultisample', 0) == 0
		linux_gles_message(view, c'setEnableSetNeedsDisplay:', 0xfeedface00000001)
		assert linux_gles_message(view, c'enableSetNeedsDisplay', 0) == 1
		linux_gles_message(view, c'setEnableSetNeedsDisplay:', 0xfeedface00000100)
		assert linux_gles_message(view, c'enableSetNeedsDisplay', 0) == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'LinuxGlesDrawDelegate', 0)
		assert cls != 0
		assert objc_add_method(cls, u64(c'glkView:drawInRect:'), u64(unsafe { voidptr(linux_gles_draw) }), c'v56@0:8@16{CGRect={CGPoint=dd}{CGSize=dd}}24')
		objc_register_class(cls)
		delegate := linux_gles_message(cls, c'new', 0)
		mut weak_delegate := u64(0)
		objc_store_weak(unsafe { &weak_delegate }, delegate)
		linux_gles_message(view, c'setDelegate:', delegate)
		mut probe := LinuxGlesProbe{ view: view, context: context, program: linux_gles_program() }
		linux_gles_probe = unsafe { &probe }
		C.glGenVertexArrays(1, &probe.vao)
		C.glGenBuffers(1, &probe.pack_buffer)
		C.glBindBuffer(C.GL_PIXEL_PACK_BUFFER, probe.pack_buffer)
		C.glBufferData(C.GL_PIXEL_PACK_BUFFER, 16384, unsafe { nil }, C.GL_STREAM_READ)
		C.glBindBuffer(C.GL_PIXEL_PACK_BUFFER, 0)
		C.glGenFramebuffers(1, &probe.read_fbo)
		C.glBindFramebuffer(C.GL_FRAMEBUFFER, probe.read_fbo)
		C.glGenRenderbuffers(1, &probe.read_color)
		C.glBindRenderbuffer(C.GL_RENDERBUFFER, probe.read_color)
		C.glRenderbufferStorage(C.GL_RENDERBUFFER, C.GL_RGBA8, 4, 4)
		C.glFramebufferRenderbuffer(C.GL_FRAMEBUFFER, C.GL_COLOR_ATTACHMENT0, C.GL_RENDERBUFFER, probe.read_color)
		assert C.glCheckFramebufferStatus(C.GL_FRAMEBUFFER) == C.GL_FRAMEBUFFER_COMPLETE
		mut previous_path := ''
		for frame in 0 .. 4 {
			probe.points = ObjRect{4, 7, f64(24 + frame * 2), f64(18 + frame * 2)}
			scale := if frame & 1 == 0 { f64(1) } else { f64(2) }
			probe.width = i32(probe.points.width * scale)
			probe.height = i32(probe.points.height * scale)
			unsafe { LinuxGlesRectSet(voidptr(C.ios_objc_msgsend))(view, u64(c'setFrame:'), probe.points) }
			unsafe { LinuxGlesDoubleSet(voidptr(C.ios_objc_msgsend))(view, u64(c'setContentScaleFactor:'), scale) }
			assert unsafe { LinuxGlesDoubleGet(voidptr(C.ios_objc_msgsend))(view, u64(c'contentScaleFactor')) } == scale
			linux_gles_message(view, c'display', 0)
			linux_gles_readback_state(unsafe { &probe })
			linux_gles_surface(unsafe { &probe })
			assert linux_gles_integer(C.GL_DEPTH_BITS) == 24 && linux_gles_integer(C.GL_STENCIL_BITS) == 8
			state := unsafe { &GlesView(obj_header(view).graphics) }
			if previous_path != '' {
				assert !os.exists(previous_path)
				unsafe { previous_path.free() }
			}
			previous_path = state.surface_path.clone()
		}
		mut state := unsafe { &GlesView(obj_header(view).graphics) }
		base := u64(state.surface)
		active := C.ios_surface_load(unsafe { &u32(base + 28) })
		C.ios_surface_store(unsafe { &u32(base + 32) }, active ^ 1)
		probe.blue = true
		linux_gles_message(view, c'display', 0)
		linux_gles_readback_state(unsafe { &probe })
		assert C.ios_surface_load(unsafe { &u32(base + 28) }) == active
		assert linux_gles_surface_pixel(state, 3, 1) == 0xffff0000
		C.ios_surface_store(unsafe { &u32(base + 32) }, ~u32(0))
		linux_gles_message(view, c'display', 0)
		assert C.ios_surface_load(unsafe { &u32(base + 28) }) == active ^ 1
		linux_gles_readback_state(unsafe { &probe })
		linux_gles_surface(unsafe { &probe })
		linux_gles_write_frame(state, cycle)!
		linux_gles_pack_defaults()
		old_fbo := state.fbo
		linux_gles_message(view, c'deleteDrawable', 0)
		assert !os.exists(previous_path) && C.glIsFramebuffer(old_fbo) == 0
		unsafe { previous_path.free() }
		assert state.fbo == 0 && state.surface == unsafe { nil } && state.surface_path == ''
		linux_gles_message(view, c'bindDrawable', 0)
		assert C.glCheckFramebufferStatus(C.GL_FRAMEBUFFER) == C.GL_FRAMEBUFFER_COMPLETE
		linux_gles_message(view, c'display', 0)
		linux_gles_readback_state(unsafe { &probe })
		linux_gles_surface(unsafe { &probe })
		final_path := state.surface_path.clone()
		assert probe.draws == 7
		linux_gles_message(delegate, c'release', 0)
		assert weak_delegate == 0 && linux_gles_message(view, c'delegate', 0) == 0
		objc_destroy_weak(unsafe { &weak_delegate })
		linux_gles_pack_defaults()
		C.glBindFramebuffer(C.GL_READ_FRAMEBUFFER, 0)
		C.glDeleteFramebuffers(1, &probe.read_fbo)
		C.glDeleteRenderbuffers(1, &probe.read_color)
		C.glDeleteBuffers(1, &probe.pack_buffer)
		C.glDeleteVertexArrays(1, &probe.vao)
		C.glUseProgram(0)
		C.glDeleteProgram(probe.program)
		linux_gles_error('graphics object cleanup')
		linux_gles_probe = unsafe { nil }
		// Replacing A's context while B is current must delete/unlink A's
		// drawable and keep B current. Releasing A's view must likewise preserve B.
		replacement := linux_gles_context(3)
		assert replacement != 0
		mut weak_replacement := u64(0)
		objc_store_weak(unsafe { &weak_replacement }, replacement)
		linux_gles_set_current(replacement)
		linux_gles_message(view, c'setContext:', replacement)
		assert !os.exists(final_path) && linux_gles_current() == replacement
		unsafe { final_path.free() }
		assert linux_gles_message(view, c'context', 0) == replacement
		linux_gles_message(view, c'bindDrawable', 0)
		assert C.glCheckFramebufferStatus(C.GL_FRAMEBUFFER) == C.GL_FRAMEBUFFER_COMPLETE
		linux_gles_clear(true)
		linux_gles_pixel(0, 0, [u8(0), 0, 255, 255]!)
		linux_gles_message(view, c'setContext:', context)
		assert linux_gles_current() == replacement
		linux_gles_message(view, c'bindDrawable', 0)
		assert linux_gles_current() == context
		linux_gles_set_current(replacement)
		linux_gles_message(context, c'release', 0)
		assert weak_context == context // Only the view owns A now.
		linux_gles_message(view, c'release', 0)
		assert weak_context == 0 && linux_gles_current() == replacement
		linux_gles_message(replacement, c'release', 0)
		assert weak_replacement == replacement // Current-context TLS owns B.
		linux_gles_set_current(0)
		assert weak_replacement == 0
		objc_destroy_weak(unsafe { &weak_replacement })
		objc_destroy_weak(unsafe { &weak_context })
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.block_refs.len == 0
		gles_stop()
		assert gles_runtime == unsafe { nil }
		system_data_stop()
	}
}

fn test_linux_gles_context_rendering_and_lifetime() {
	$if ios_gles ? {
		for cycle in 0 .. 2 { linux_gles_case(cycle) or { panic(err) } }
		println('IOS-LINUX-GLES-CONTEXTS: public ARM64 EAGL API2/API3 construction, inherited class methods, exact signatures, unsupported selector rejection, actual ES3 identity and resolved exports PASS')
		println('IOS-LINUX-GLES-DRAW: real ES3 shaders and triangle pixels, FP/HFA Objective-C dispatch, four resized/scaled GLKViews and depth/stencil PASS')
		println('IOS-LINUX-GLES-SURFACE: VSF1 XRGB pixels, vertical flip, read framebuffer/PBO/packing preservation, busy-reader drop and drawable recreation PASS')
		println('IOS-LINUX-GLES-THREADS: API2 pbuffer pixels, per-thread current contexts and last-reference TLS destruction before join PASS')
		println('IOS-LINUX-GLES-CLEANUP: weak delegates/contexts, context replacement, preserved current context during drawable deletion, surface unlinking and two zero-live-object runtime shutdowns PASS')
	} $else {
		println('IOS-LINUX-GLES-SKIPPED: requires -d ios_gles')
	}
}
