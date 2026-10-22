// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module assetprobe

fn C.printf(&char, ...) i32
fn C.eglGetDisplay(voidptr) voidptr
fn C.eglChooseConfig(voidptr, &i32, &voidptr, i32, &i32) u32
fn C.eglGetConfigs(voidptr, &voidptr, i32, &i32) u32
fn C.eglGetConfigAttrib(voidptr, voidptr, i32, &i32) u32
fn C.eglCreateContext(voidptr, voidptr, voidptr, &i32) voidptr
fn C.eglCreatePbufferSurface(voidptr, voidptr, &i32) voidptr
fn C.eglCreateWindowSurface(voidptr, voidptr, voidptr, &i32) voidptr
fn C.eglDestroyContext(voidptr, voidptr) u32
fn C.eglDestroySurface(voidptr, voidptr) u32
fn C.eglMakeCurrent(voidptr, voidptr, voidptr, voidptr) u32
fn C.eglSwapBuffers(voidptr, voidptr) u32
fn C.eglQuerySurface(voidptr, voidptr, i32, &i32) u32

type GlCreate = fn (u32) u32
type GlShaderSource = fn (u32, i32, &&char, &i32)
type GlOne = fn (u32)
type GlTwo = fn (u32, u32)
type GlGet = fn (u32, u32, &i32)
type GlProgram = fn () u32
type GlLocation = fn (u32, &char) i32
type GlVertex = fn (u32, i32, u32, u8, i32, voidptr)
type GlDraw = fn (u32, i32, i32)
type GlBox = fn (i32, i32, i32, i32)
type GlColor = fn (f32, f32, f32, f32)
type GlRead = fn (i32, i32, i32, i32, u32, u32, voidptr)
type GlError = fn () u32
type GlGenerate = fn (i32, &u32)
type GlBufferData = fn (u32, isize, voidptr, u32)
type GlStore = fn (u32, i32)
type GlInteger = fn (u32, &i32)
type GlDelete = fn (i32, &u32)
type GlString = fn (u32) &char
type GlInfoLog = fn (u32, i32, &i32, &char)

fn egl_shader(kind u32, source &char) u32 {
	unsafe {
		shader := GlCreate(C.eglGetProcAddress(c'glCreateShader'))(kind)
		mut text := source
		GlShaderSource(C.eglGetProcAddress(c'glShaderSource'))(shader, 1, &text, nil)
		GlOne(C.eglGetProcAddress(c'glCompileShader'))(shader)
		mut success := i32(0)
		GlGet(C.eglGetProcAddress(c'glGetShaderiv'))(shader, 0x8b81, &success)
		if success == 0 {
			log := &char(C.alloca(2048))
			log[0] = 0
			GlInfoLog(C.eglGetProcAddress(c'glGetShaderInfoLog'))(shader, 2048, nil, log)
			C.printf(c'EGL-PROBE shader kind=%x id=%u error=%x\n', kind, shader, GlError(C.eglGetProcAddress(c'glGetError'))())
			C.puts(log)
			GlOne(C.eglGetProcAddress(c'glDeleteShader'))(shader); return 0
		}
		return shader
	}
}
fn egl_draw(width i32, height i32) bool {
	unsafe {
		vertex := egl_shader(0x8b31, c'attribute vec2 pos; void main(){gl_Position=vec4(pos,0.,1.);}')
		fragment := egl_shader(0x8b30, c'precision mediump float; void main(){gl_FragColor=vec4(0.,1.,0.,1.);}')
		if vertex == 0 || fragment == 0 { return false }
		defer { GlOne(C.eglGetProcAddress(c'glDeleteShader'))(vertex); GlOne(C.eglGetProcAddress(c'glDeleteShader'))(fragment) }
		program := GlProgram(C.eglGetProcAddress(c'glCreateProgram'))()
		defer { GlOne(C.eglGetProcAddress(c'glDeleteProgram'))(program) }
		GlTwo(C.eglGetProcAddress(c'glAttachShader'))(program, vertex)
		GlTwo(C.eglGetProcAddress(c'glAttachShader'))(program, fragment)
		GlOne(C.eglGetProcAddress(c'glLinkProgram'))(program)
		mut linked := i32(0)
		GlGet(C.eglGetProcAddress(c'glGetProgramiv'))(program, 0x8b82, &linked)
		if linked == 0 {
			log := &char(C.alloca(2048))
			log[0] = 0
			GlInfoLog(C.eglGetProcAddress(c'glGetProgramInfoLog'))(program, 2048, nil, log)
			C.puts(log); return false
		}
		GlOne(C.eglGetProcAddress(c'glUseProgram'))(program)
		GlBox(C.eglGetProcAddress(c'glViewport'))(0, 0, width, height)
		GlColor(C.eglGetProcAddress(c'glClearColor'))(1, 0, 0, 1)
		GlOne(C.eglGetProcAddress(c'glClear'))(0x4000)
		GlOne(C.eglGetProcAddress(c'glEnable'))(0x0c11)
		GlBox(C.eglGetProcAddress(c'glScissor'))(0, height / 2, width, height / 2)
		GlColor(C.eglGetProcAddress(c'glClearColor'))(0, 0, 1, 1)
		GlOne(C.eglGetProcAddress(c'glClear'))(0x4000)
		GlOne(C.eglGetProcAddress(c'glDisable'))(0x0c11)
		points := &f32(C.alloca(6 * sizeof(f32)))
		points[0] = -1; points[1] = -1; points[2] = 1
		points[3] = -1; points[4] = -1; points[5] = 1
		mut buffer := u32(0)
		GlGenerate(C.eglGetProcAddress(c'glGenBuffers'))(1, &buffer)
		defer { GlDelete(C.eglGetProcAddress(c'glDeleteBuffers'))(1, &buffer) }
		GlTwo(C.eglGetProcAddress(c'glBindBuffer'))(0x8892, buffer)
		GlBufferData(C.eglGetProcAddress(c'glBufferData'))(0x8892, 24, points, 0x88e4)
		location := GlLocation(C.eglGetProcAddress(c'glGetAttribLocation'))(program, c'pos')
		if location < 0 { C.puts(c'EGL-PROBE missing attribute'); return false }
		GlOne(C.eglGetProcAddress(c'glEnableVertexAttribArray'))(u32(location))
		GlVertex(C.eglGetProcAddress(c'glVertexAttribPointer'))(u32(location), 2, 0x1406, 0, 0, nil)
		GlDraw(C.eglGetProcAddress(c'glDrawArrays'))(4, 0, 3)
		mut pixels := [4]u8{}
		read := GlRead(C.eglGetProcAddress(c'glReadPixels'))
		read(1, 1, 1, 1, 0x1908, 0x1401, &pixels[0])
		if pixels != [u8(0), 255, 0, 255]! { C.printf(c'EGL-PROBE green %u %u %u %u error=%x\n', pixels[0], pixels[1], pixels[2], pixels[3], GlError(C.eglGetProcAddress(c'glGetError'))()); return false }
		read(width - 2, height - 2, 1, 1, 0x1908, 0x1401, &pixels[0])
		if pixels != [u8(0), 0, 255, 255]! { C.printf(c'EGL-PROBE blue %u %u %u %u\n', pixels[0], pixels[1], pixels[2], pixels[3]); return false }
		read(width - 1, 1, 1, 1, 0x1908, 0x1401, &pixels[0])
		if pixels != [u8(255), 0, 0, 255]! { C.printf(c'EGL-PROBE red %u %u %u %u\n', pixels[0], pixels[1], pixels[2], pixels[3]); return false }
		error := GlError(C.eglGetProcAddress(c'glGetError'))()
		if error != 0 { C.printf(c'EGL-PROBE draw error=%x\n', error) }
		return error == 0
	}
}

fn egl_thread(data voidptr) voidptr {
	unsafe {
		if C.eglGetCurrentContext() != nil || C.eglGetError() != 0x3000 { return nil }
		C.eglGetCurrentSurface(0)
		if C.eglGetError() != 0x300c { return nil }
		return voidptr(usize(C.eglReleaseThread() == 1))
	}
}
// Shader compilation/linking and sampled pixels distinguish a renderer from
// an EGL implementation which merely returns success or clears a buffer.
fn egl_render_check(window voidptr) bool {
	unsafe {
		display := C.eglGetDisplay(nil)
		mut major, mut minor := i32(0), i32(0)
		if display == nil || C.eglInitialize(display, &major, &minor) != 1 || major < 1 { C.puts(c'EGL-PROBE initialize'); return false }
		defer { C.eglTerminate(display) }
		attrs := [i32(0x3033), 5, 0x3040, 4, 0x3024, 8, 0x3023, 8, 0x3022, 8, 0x3021, 8, 0x3038]!
		mut config := voidptr(nil)
		mut count := i32(0)
		if C.eglChooseConfig(display, &attrs[0], &config, 1, &count) != 1 || count < 1 { C.puts(c'EGL-PROBE config'); return false }
		context_attrs := [i32(0x3098), 3, 0x3038]!
		context := C.eglCreateContext(display, config, nil, &context_attrs[0])
		if context == nil { C.puts(c'EGL-PROBE context'); return false }
		defer { C.eglDestroyContext(display, context) }
		pbuffer_attrs := [i32(0x3057), 8, 0x3056, 8, 0x3038]!
		surface := if window == nil { C.eglCreatePbufferSurface(display, config, &pbuffer_attrs[0]) }
			else { C.eglCreateWindowSurface(display, config, window, nil) }
		if surface == nil { C.puts(c'EGL-PROBE surface'); return false }
		mut surface_destroyed := false
		defer { if !surface_destroyed { C.eglDestroySurface(display, surface) } }
		if C.eglMakeCurrent(display, surface, surface, context) != 1 { C.puts(c'EGL-PROBE current'); return false }
		defer { C.eglReleaseThread() }
		width := if window == nil { i32(8) } else { C.ANativeWindow_getWidth(window) }
		height := if window == nil { i32(8) } else { C.ANativeWindow_getHeight(window) }
		C.puts(GlString(C.eglGetProcAddress(c'glGetString'))(0x1f02))
		C.puts(GlString(C.eglGetProcAddress(c'glGetString'))(0x1f01))
		if C.eglGetCurrentDisplay() != display || C.eglGetCurrentSurface(0x3059) != surface
			|| C.eglGetCurrentContext() != context || !egl_draw(width, height) { C.puts(c'EGL-PROBE draw'); return false }
		mut worker := C.pthread_t{}
		mut worker_result := voidptr(nil)
		if C.pthread_create(&worker, nil, egl_thread, nil) != 0
			|| C.pthread_join(worker, &worker_result) != 0 || usize(worker_result) != 1
			|| C.eglGetCurrentContext() != context || C.eglGetError() != 0x3000 { C.puts(c'EGL-PROBE thread'); return false }
		// ES3 applications may leave a PBO and an offscreen read FBO bound.
		// Present the window's default framebuffer and restore all pack state.
		mut fbo, mut pbo := u32(0), u32(0)
		GlGenerate(C.eglGetProcAddress(c'glGenFramebuffers'))(1, &fbo)
		GlGenerate(C.eglGetProcAddress(c'glGenBuffers'))(1, &pbo)
		defer {
			GlDelete(C.eglGetProcAddress(c'glDeleteFramebuffers'))(1, &fbo)
			GlDelete(C.eglGetProcAddress(c'glDeleteBuffers'))(1, &pbo)
		}
		GlTwo(C.eglGetProcAddress(c'glBindFramebuffer'))(0x8ca8, fbo)
		GlTwo(C.eglGetProcAddress(c'glBindBuffer'))(0x88eb, pbo)
		GlBufferData(C.eglGetProcAddress(c'glBufferData'))(0x88eb, 4096, nil, 0x88e1)
		store := GlStore(C.eglGetProcAddress(c'glPixelStorei'))
		store(0x0d05, 8); store(0x0d02, 37); store(0x0d03, 2); store(0x0d04, 3)
		if C.eglSwapBuffers(display, surface) != 1 { C.puts(c'EGL-PROBE swap'); return false }
		get := GlInteger(C.eglGetProcAddress(c'glGetIntegerv'))
		mut value := i32(0)
		attributes := [u32(0x8caa), 0x88ed, 0x0d05, 0x0d02, 0x0d03, 0x0d04]!
		expected := [i32(fbo), i32(pbo), 8, 37, 2, 3]!
		for i in 0 .. 6 {
			get(attributes[i], &value)
			if value != expected[i] { C.puts(c'EGL-PROBE pack-state'); return false }
		}
		if GlError(C.eglGetProcAddress(c'glGetError'))() != 0 { C.puts(c'EGL-PROBE GL-error'); return false }
		if window != nil {
			// Destroying a current window defers producer ownership until unbind.
			if C.eglDestroySurface(display, surface) != 1 { C.puts(c'EGL-PROBE destroy-current'); return false }
			surface_destroyed = true
			buffer := &NativeBuffer(C.alloca(sizeof(NativeBuffer)))
			if C.ANativeWindow_lock(window, buffer, nil) != -16 { C.puts(c'EGL-PROBE producer-ownership'); return false }
			if C.eglReleaseThread() != 1 { return false }
			replacement := C.eglCreateWindowSurface(display, config, window, nil)
			if replacement == nil || C.eglDestroySurface(display, replacement) != 1 { C.puts(c'EGL-PROBE released-window'); return false }
		}
		return C.eglGetError() == 0x3000
	}
}

@[export: 'Java_org_vinix_bootstrap_Main_nativeEglWindow']
pub fn egl_window_check(e voidptr, class voidptr, surface voidptr) u8 {
	unsafe {
		window := C.ANativeWindow_fromSurface(e, surface)
		if window == nil { return 0 }
		defer { C.ANativeWindow_release(window) }
		return u8(egl_render_check(window))
	}
}
