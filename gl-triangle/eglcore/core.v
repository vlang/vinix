// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module egltri

#include "gl_v.h"
struct C.fb_bitfield {
	offset    u32
	length    u32
	msb_right u32
}

struct C.fb_fix_screeninfo {
	smem_len    u32
	line_length u32
}

struct C.fb_var_screeninfo {
	xres           u32
	yres           u32
	xoffset        u32
	yoffset        u32
	bits_per_pixel u32
	red            C.fb_bitfield
	green          C.fb_bitfield
	blue           C.fb_bitfield
	transp         C.fb_bitfield
}

type GetPlatformDisplay = fn (u32, voidptr, &i32) voidptr

fn C.vkg_get_platform_display() voidptr
fn C.vkg_errno_pointer() &i32
fn C.vkg_stderr() voidptr
fn C.vkg_stdout() voidptr
fn C.tolower(i32) i32
fn C.strlen(&char) usize
fn C.strcmp(&char, &char) i32
fn C.strerror(i32) &char
fn C.fprintf(voidptr, &char, ...i32) i32
fn C.printf(&char, ...i32) i32
fn C.exit(i32)
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.eglChooseConfig(dpy voidptr, attrib_list &i32, configs &voidptr, config_size i32, num_config &i32) u32
fn C.eglCreateContext(dpy voidptr, config voidptr, share_context voidptr, attrib_list &i32) voidptr
fn C.eglCreatePbufferSurface(dpy voidptr, config voidptr, attrib_list &i32) voidptr
fn C.eglDestroyContext(dpy voidptr, ctx voidptr) u32
fn C.eglDestroySurface(dpy voidptr, surface voidptr) u32
fn C.vkg_default_display() voidptr
fn C.eglGetError() i32
fn C.eglGetProcAddress(procname &char) voidptr
fn C.eglInitialize(dpy voidptr, major &i32, minor &i32) u32
fn C.eglMakeCurrent(dpy voidptr, draw voidptr, read_2 voidptr, ctx voidptr) u32
fn C.eglTerminate(dpy voidptr) u32
fn C.eglBindAPI(api u32) u32
fn C.glAttachShader(program u32, shader u32)
fn C.glBindAttribLocation(program u32, index_2 u32, name &char)
fn C.glBindBuffer(target u32, buffer u32)
fn C.glBindFramebuffer(target u32, framebuffer u32)
fn C.glBindRenderbuffer(target u32, renderbuffer u32)
fn C.glBufferData(target u32, size isize, data voidptr, usage u32)
fn C.glCheckFramebufferStatus(target u32) u32
fn C.glClear(mask u32)
fn C.glClearColor(red f32, green f32, blue f32, alpha f32)
fn C.glClearDepthf(d f32)
fn C.glClearStencil(s i32)
fn C.glCompileShader(shader u32)
fn C.glCreateProgram() u32
fn C.glCreateShader(type_ u32) u32
fn C.glDeleteBuffers(n i32, buffers &u32)
fn C.glDeleteFramebuffers(n i32, framebuffers &u32)
fn C.glDeleteProgram(program u32)
fn C.glDeleteRenderbuffers(n i32, renderbuffers &u32)
fn C.glDeleteShader(shader u32)
fn C.glDepthFunc(func u32)
fn C.glDepthMask(flag u8)
fn C.glDrawArrays(mode u32, first i32, count i32)
fn C.glEnable(cap u32)
fn C.glEnableVertexAttribArray(index_2 u32)
fn C.glFinish()
fn C.glFramebufferRenderbuffer(target u32, attachment u32, renderbuffertarget u32, renderbuffer u32)
fn C.glGenBuffers(n i32, buffers &u32)
fn C.glGenFramebuffers(n i32, framebuffers &u32)
fn C.glGenRenderbuffers(n i32, renderbuffers &u32)
fn C.glGetError() u32
fn C.glGetIntegerv(pname u32, data &i32)
fn C.glGetProgramiv(program u32, pname u32, params &i32)
fn C.glGetProgramInfoLog(program u32, buf_size i32, length &i32, info_log &char)
fn C.glGetShaderiv(shader u32, pname u32, params &i32)
fn C.glGetShaderInfoLog(shader u32, buf_size i32, length &i32, info_log &char)
fn C.glGetString(name u32) &u8
fn C.glLinkProgram(program u32)
fn C.glPixelStorei(pname u32, param i32)
fn C.glReadPixels(x i32, y i32, width i32, height i32, format u32, type_ u32, pixels voidptr)
fn C.glRenderbufferStorage(target u32, internalformat u32, width i32, height i32)
fn C.vkg_shader_source(shader u32, count i32, string_ &&char, length &i32)
fn C.glStencilFunc(func u32, ref i32, mask u32)
fn C.glStencilMask(mask u32)
fn C.glStencilOp(fail u32, zfail u32, zpass u32)
fn C.glUseProgram(program u32)
fn C.glVertexAttribPointer(index_2 u32, size i32, type_ u32, normalized u8, stride i32, pointer voidptr)
fn C.glViewport(x i32, y i32, width i32, height i32)
fn C.__errno_location() &i32
fn C.open(arg &char, arg_2 i32, ...i32) i32
fn C.fflush(arg voidptr) i32
fn C.ioctl(arg i32, arg_2 i32, ...i32) i32
fn C.mmap(arg voidptr, arg_2 usize, arg_3 i32, arg_4 i32, arg_5 i32, arg_6 i64) voidptr
fn C.munmap(arg voidptr, arg_2 usize) i32
fn C.close(arg i32) i32

pub enum Attachment_mode {
	attachment_color_only
	attachment_depth
	attachment_stencil
	attachment_depth_stencil
}

pub fn attachment_mode_name(mode Attachment_mode) &char {
	unsafe {
		match mode {
			.attachment_depth {
				return &char(&c'depth'[0])
			}
			.attachment_stencil {
				return &char(&c'stencil'[0])
			}
			.attachment_depth_stencil {
				return &char(&c'depth-stencil'[0])
			}
			.attachment_color_only {
				return &char(&c'color'[0])
			}
			else {}
		}

		return &char(&c'unknown'[0])
	}
}

pub fn fail_egl(operation &char) {
	unsafe {
		C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: %s failed (EGL 0x%04x)\n', operation, C.eglGetError())
		C.exit(1)
	}
}

pub fn compile_shader(type_ u32, source_param &char) u32 {
	unsafe {
		mut source := source_param
		shader := C.glCreateShader(type_)
		ok := i32(0)
		C.vkg_shader_source(shader, 1, &source, (voidptr(0)))
		C.glCompileShader(shader)
		C.glGetShaderiv(shader, u32(35713), &ok)
		if !ok {
			log := [1024]i8{}
			length := i32(0)
			C.glGetShaderInfoLog(shader, i32(sizeof([1024]i8)), &length, &char(&log[0]))
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: shader compile failed: %.*s\n', i32(length), &log[0])
			C.exit(1)
		}
		return shader
	}
}

pub fn create_program() u32 {
	unsafe {
		vertex_source := c'attribute vec2 position;\nattribute vec3 color;\nvarying vec3 vertex_color;\nvoid main(void) {\n  vertex_color = color;\n  gl_Position = vec4(position, 0.0, 1.0);\n}\n'
		fragment_source := c'precision mediump float;\nvarying vec3 vertex_color;\nvoid main(void) {\n  gl_FragColor = vec4(vertex_color, 1.0);\n}\n'
		vertex := compile_shader(35633, &char(vertex_source))
		fragment := compile_shader(35632, &char(fragment_source))
		program := C.glCreateProgram()
		ok := i32(0)
		C.glAttachShader(program, vertex)
		C.glAttachShader(program, fragment)
		C.glBindAttribLocation(program, u32(0), c'position')
		C.glBindAttribLocation(program, u32(1), c'color')
		C.glLinkProgram(program)
		C.glGetProgramiv(program, u32(35714), &ok)
		if !ok {
			log := [1024]i8{}
			length := i32(0)
			C.glGetProgramInfoLog(program, i32(sizeof([1024]i8)), &length, &char(&log[0]))
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: program link failed: %.*s\n', i32(length), &log[0])
			C.exit(1)
		}
		C.glDeleteShader(vertex)
		C.glDeleteShader(fragment)
		return program
	}
}

pub fn contains_ignoring_case(text &char, needle &char) i32 {
	unsafe {
		needle_length := C.strlen(needle)
		if !needle_length {
			return 1
		}
		for ; (*text); text = text + 1 {
			i := usize(0)
			for i < needle_length && i32(text[i]) && C.tolower(i32(u8(text[i]))) == C.tolower(i32(u8(needle[i]))) {
				i++
			}
			if i == needle_length {
				return 1
			}
		}
		return 0
	}
}

pub fn framebuffer_component(value u8, field C.fb_bitfield) u32 {
	unsafe {
		maximum := u64(0)
		if !field.length || field.offset >= 32 {
			return u32(0)
		}
		maximum = if field.length >= 32 {
			u64(u32(4294967295))
		} else {
			((u64(1) << field.length) - u64(1))
		}
		return u32((((u64(value) * maximum + u64(127)) / u64(255)) << field.offset))
	}
}

pub fn copy_to_framebuffer(pixels &u8, width i32, height i32) i32 {
	unsafe {
		fixed := C.fb_fix_screeninfo{}
		variable := C.fb_var_screeninfo{}
		framebuffer := &u8(0)
		fd := C.open(c'/dev/fb0', 2 | 524288)
		if fd < 0 {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: /dev/fb0 unavailable: %s\n', C.strerror((*C.vkg_errno_pointer())))
			return 0
		}
		if C.ioctl(fd, 17922, &fixed) < 0 || C.ioctl(fd, 17920, &variable) < 0 {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: framebuffer query failed: %s\n', C.strerror((*C.vkg_errno_pointer())))
			C.close(fd)
			return 0
		}
		if fixed.smem_len == 0 || fixed.line_length == 0
			|| (variable.bits_per_pixel != 16 && variable.bits_per_pixel != 24 && variable.bits_per_pixel != 32)
			|| variable.red.msb_right != 0 || variable.green.msb_right != 0 || variable.blue.msb_right != 0 || variable.transp.msb_right != 0
			|| variable.red.offset + variable.red.length > variable.bits_per_pixel
			|| variable.green.offset + variable.green.length > variable.bits_per_pixel
			|| variable.blue.offset + variable.blue.length > variable.bits_per_pixel
			|| variable.transp.offset + variable.transp.length > variable.bits_per_pixel {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: unsupported framebuffer layout\n')
			C.close(fd)
			return 0
		}
		framebuffer = &u8(C.mmap(voidptr((voidptr(0))), usize(fixed.smem_len), 1 | 2, 1, fd, i64(0)))
		if usize(framebuffer) == usize((voidptr(-1))) {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: framebuffer mmap failed: %s\n', C.strerror((*C.vkg_errno_pointer())))
			C.close(fd)
			return 0
		}
		copy_width := if width < i32(variable.xres) { width } else { i32(variable.xres) }
		copy_height := if height < i32(variable.yres) { height } else { i32(variable.yres) }
		origin_x := (i32(variable.xres) - copy_width) / 2
		origin_y := (i32(variable.yres) - copy_height) / 2
		bytes_per_pixel := variable.bits_per_pixel / 8
		last_row := u64(variable.yoffset) + u64(origin_y) + u64(copy_height) - u64(1)
		last_column := u64(variable.xoffset) + u64(origin_x) + u64(copy_width)
		if last_row * u64(fixed.line_length) + last_column * u64(bytes_per_pixel) > u64(fixed.smem_len) {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: framebuffer bounds are invalid\n')
			C.munmap(voidptr(framebuffer), usize(fixed.smem_len))
			C.close(fd)
			return 0
		}
		for y := i32(0); y < copy_height; y++ {
			source := pixels + ((usize((height - 1 - y)) * usize(width)) * usize(4))
			destination := framebuffer + (usize((variable.yoffset + origin_y + y)) * usize(fixed.line_length)) + (usize((variable.xoffset + origin_x)) * usize(bytes_per_pixel))
			for x := i32(0); x < copy_width; x++ {
				packed := framebuffer_component(source[0], variable.red) | framebuffer_component(source[1], variable.green) | framebuffer_component(source[2], variable.blue) | framebuffer_component(source[3], variable.transp)
				for byte_ := u32(0); byte_ < bytes_per_pixel; byte_++ {
					destination[byte_] = u8((packed >> (byte_ * u32(8))))
				}
				source += 4
				destination += bytes_per_pixel
			}
		}
		C.munmap(voidptr(framebuffer), usize(fixed.smem_len))
		C.close(fd)
		return 1
	}
}

pub fn destroy_render_state(program u32, display voidptr, surface voidptr, context voidptr) {
	unsafe {
		C.glDeleteProgram(program)
		C.eglMakeCurrent(voidptr(display), voidptr((voidptr(0))), voidptr((voidptr(0))), voidptr((voidptr(0))))
		C.eglDestroyContext(voidptr(display), voidptr(context))
		C.eglDestroySurface(voidptr(display), voidptr(surface))
		C.eglTerminate(voidptr(display))
	}
}

@[export: 'main']
pub fn cli_main(argc i32, argv &&char) i32 {
	unsafe {
		submit_only := i32(0)
		attachment_mode := Attachment_mode.attachment_color_only
		for argument := i32(1); argument < argc; argument++ {
			requested_mode := Attachment_mode.attachment_color_only
			if C.strcmp(argv[argument], c'--submit-only') == 0 {
				if submit_only {
					goto usage
				}
				submit_only = 1
				continue
			} else if C.strcmp(argv[argument], c'--depth') == 0 {
				requested_mode = Attachment_mode.attachment_depth
			} else if C.strcmp(argv[argument], c'--stencil') == 0 {
				requested_mode = Attachment_mode.attachment_stencil
			} else if C.strcmp(argv[argument], c'--depth-stencil') == 0 {
				requested_mode = Attachment_mode.attachment_depth_stencil
			} else {
				goto usage
			}
			if u32(attachment_mode) != u32(Attachment_mode.attachment_color_only) {
				goto usage
			}
			attachment_mode = requested_mode
		}
		cli_main_vertices := [f32(-0.720000029), f32(-0.579999983), f32(1.0), f32(0.180000007),
			f32(0.159999996), f32(0.720000029), f32(-0.579999983), f32(0.159999996), f32(1.0),
			f32(0.300000012), f32(0.0), f32(0.720000029), f32(0.180000007), f32(0.419999987), f32(1.0)]!

		cli_main_config_attributes := [i32(12339), 1, 12352, 4, 12324, 8, 12323, 8, 12322, 8, 12321,
			8, 12344]!

		cli_main_surface_attributes := [i32(12375), 800, 12374, 600, 12344]!

		cli_main_context_attributes := [i32(12440), 2, 12344]!

		get_platform_display := GetPlatformDisplay(C.vkg_get_platform_display())
		display := voidptr(if get_platform_display {
			&u8(get_platform_display(u32(12765), voidptr((voidptr(0))), (voidptr(0))))
		} else {
			&u8(C.vkg_default_display())
		})
		major := i32(0)
		minor := i32(0)
		config_count := i32(0)

		config := voidptr(0)
		surface := voidptr(0)
		context := voidptr(0)
		if usize(voidptr(display)) == usize(voidptr((voidptr(0)))) {
			fail_egl(c'surfaceless display creation')
		}
		if !C.eglInitialize(voidptr(display), &major, &minor) {
			fail_egl(c'eglInitialize')
		}
		if !C.eglBindAPI(u32(12448)) {
			fail_egl(c'eglBindAPI')
		}
		if !C.eglChooseConfig(voidptr(display), &cli_main_config_attributes[0], &config, 1, &config_count) || config_count != 1 {
			fail_egl(c'eglChooseConfig')
		}
		surface = C.eglCreatePbufferSurface(voidptr(display), voidptr(config), &cli_main_surface_attributes[0])
		if usize(voidptr(surface)) == usize(voidptr((voidptr(0)))) {
			fail_egl(c'eglCreatePbufferSurface')
		}
		context = C.eglCreateContext(voidptr(display), voidptr(config), voidptr((voidptr(0))), &cli_main_context_attributes[0])
		if usize(voidptr(context)) == usize(voidptr((voidptr(0)))) {
			fail_egl(c'eglCreateContext')
		}
		if !C.eglMakeCurrent(voidptr(display), voidptr(surface), voidptr(surface), voidptr(context)) {
			fail_egl(c'eglMakeCurrent')
		}
		vendor := &char(voidptr(C.glGetString(u32(7936))))
		renderer := &char(voidptr(C.glGetString(u32(7937))))
		version := &char(voidptr(C.glGetString(u32(7938))))
		C.printf(c'gl-triangle-agx: EGL %d.%d\n', major, minor)
		C.printf(c'gl-triangle-agx: GL_VENDOR=%s\n', if vendor { vendor } else { c'unknown' })
		C.printf(c'gl-triangle-agx: GL_RENDERER=%s\n', if renderer { renderer } else { c'unknown' })
		C.printf(c'gl-triangle-agx: GL_VERSION=%s\n', if version { version } else { c'unknown' })
		if (usize(renderer) == 0) || contains_ignoring_case(renderer, c'softpipe') || contains_ignoring_case(renderer, c'llvmpipe') || contains_ignoring_case(renderer, c'software rasterizer') {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: refusing a software renderer\n')
			return 2
		}
		framebuffer := u32(0)
		color_renderbuffer := u32(0)
		depth_stencil_renderbuffer := u32(0)
		if u32(attachment_mode) != u32(Attachment_mode.attachment_color_only) {
			C.glGenFramebuffers(1, &framebuffer)
			C.glBindFramebuffer(u32(36160), framebuffer)
			C.glGenRenderbuffers(1, &color_renderbuffer)
			C.glBindRenderbuffer(u32(36161), color_renderbuffer)
			C.glRenderbufferStorage(u32(36161), u32(32854), 800, 600)
			C.glFramebufferRenderbuffer(u32(36160), u32(36064), u32(36161), color_renderbuffer)
			C.glGenRenderbuffers(1, &depth_stencil_renderbuffer)
			C.glBindRenderbuffer(u32(36161), depth_stencil_renderbuffer)
			if u32(attachment_mode) == u32(Attachment_mode.attachment_depth) {
				C.glRenderbufferStorage(u32(36161), u32(33189), 800, 600)
				C.glFramebufferRenderbuffer(u32(36160), u32(36096), u32(36161), depth_stencil_renderbuffer)
			} else if u32(attachment_mode) == u32(Attachment_mode.attachment_stencil) {
				C.glRenderbufferStorage(u32(36161), u32(36168), 800, 600)
				C.glFramebufferRenderbuffer(u32(36160), u32(36128), u32(36161), depth_stencil_renderbuffer)
			} else {
				C.glRenderbufferStorage(u32(36161), u32(35056), 800, 600)
				C.glFramebufferRenderbuffer(u32(36160), u32(36096), u32(36161), depth_stencil_renderbuffer)
				C.glFramebufferRenderbuffer(u32(36160), u32(36128), u32(36161), depth_stencil_renderbuffer)
			}
			framebuffer_status := C.glCheckFramebufferStatus(u32(36160))
			setup_error := C.glGetError()
			if setup_error != u32(0) || framebuffer_status != u32(36053) {
				C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: %s framebuffer setup failed (GL 0x%04x, status 0x%04x)\n', attachment_mode_name(attachment_mode), setup_error, framebuffer_status)
				return 1
			}
		}
		depth_bits := i32(0)
		stencil_bits := i32(0)
		C.glGetIntegerv(u32(3414), &depth_bits)
		C.glGetIntegerv(u32(3415), &stencil_bits)
		if (attachment_mode == .attachment_depth && (depth_bits < 16 || stencil_bits != 0))
			|| (attachment_mode == .attachment_stencil && (depth_bits != 0 || stencil_bits < 8))
			|| (attachment_mode == .attachment_depth_stencil && (depth_bits < 16 || stencil_bits < 8)) {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: %s attachment mismatch (depth=%d stencil=%d)\n', attachment_mode_name(attachment_mode), depth_bits, stencil_bits)
			return 1
		}
		C.printf(c'gl-triangle-agx: attachment mode=%s depth=%d stencil=%d\n', attachment_mode_name(attachment_mode), depth_bits, stencil_bits)
		program := create_program()
		C.glUseProgram(program)
		vertex_buffer := u32(0)
		C.glGenBuffers(1, &vertex_buffer)
		C.glBindBuffer(u32(34962), vertex_buffer)
		C.glBufferData(u32(34962), isize(sizeof([15]f32)), voidptr(&cli_main_vertices[0]), u32(35044))
		C.glViewport(0, 0, 800, 600)
		C.glClearColor(0.0350000001, 0.0450000018, 0.075000003, 1.0)
		clear_mask := u32(16384)
		if u32(attachment_mode) == u32(Attachment_mode.attachment_depth) || u32(attachment_mode) == u32(Attachment_mode.attachment_depth_stencil) {
			C.glClearDepthf(1.0)
			C.glEnable(u32(2929))
			C.glDepthFunc(u32(513))
			C.glDepthMask(u8(1))
			clear_mask |= u32(256)
		}
		if u32(attachment_mode) == u32(Attachment_mode.attachment_stencil) || u32(attachment_mode) == u32(Attachment_mode.attachment_depth_stencil) {
			C.glClearStencil(0)
			C.glEnable(u32(2960))
			C.glStencilMask(u32(255))
			C.glStencilFunc(u32(519), 1, u32(255))
			C.glStencilOp(u32(7680), u32(7680), u32(7681))
			clear_mask |= u32(1024)
		}
		C.glClear(clear_mask)
		C.glVertexAttribPointer(u32(0), 2, u32(5126), u8(0), i32(u64(5) * sizeof(f32)), voidptr(0))
		C.glVertexAttribPointer(u32(1), 3, u32(5126), u8(0), i32(u64(5) * sizeof(f32)), voidptr((u64(2) * sizeof(f32))))
		C.glEnableVertexAttribArray(u32(0))
		C.glEnableVertexAttribArray(u32(1))
		C.glDrawArrays(u32(4), 0, 3)
		C.glFinish()
		if C.glGetError() != u32(0) {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: render submit or wait failed\n')
			return 1
		}
		// Fake G17 intentionally validates command generation and fence completion
		// without rasterizing. This mode proves the Mesa/DRM lifecycle while keeping
		// the normal test's rendered-pixel check intact for real hardware and VirGL.
		if submit_only {
			// An otherwise private renderbuffer has no externally observable result,
			// so Gallium may discard its batch even after glFinish().  A one-pixel
			// readback makes Mesa submit and wait without treating fake pixels as a
			// rendering correctness result.
			probe := [4]u8{}
			C.glReadPixels(800 / 2, 600 / 2, 1, 1, u32(6408), u32(5121), voidptr(&probe[0]))
			if C.glGetError() != u32(0) {
				C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: submit probe readback failed\n')
				return 1
			}
			C.printf(c'gl-triangle-agx: render submit and fence completed successfully; pixels unchecked\n')
			C.glDeleteBuffers(1, &vertex_buffer)
			C.glDeleteRenderbuffers(1, &depth_stencil_renderbuffer)
			C.glDeleteRenderbuffers(1, &color_renderbuffer)
			C.glDeleteFramebuffers(1, &framebuffer)
			destroy_render_state(program, voidptr(display), voidptr(surface), voidptr(context))
			return 0
		}
		image_size := usize(800) * usize(600) * usize(4)
		pixels := &u8(C.malloc(image_size))
		if usize(pixels) == 0 {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: image allocation failed\n')
			return 1
		}
		C.glPixelStorei(u32(3333), 1)
		C.glReadPixels(0, 0, 800, 600, u32(6408), u32(5121), voidptr(pixels))
		if C.glGetError() != u32(0) {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: glReadPixels failed\n')
			return 1
		}
		center := pixels + ((usize((600 / 2)) * usize(800) + usize(800 / 2)) * usize(4))
		if i32(center[0]) < 30 || i32(center[1]) < 30 || i32(center[2]) < 30 {
			C.fprintf(C.vkg_stderr(), c'gl-triangle-agx: rendered image validation failed\n')
			return 1
		}
		displayed := copy_to_framebuffer(pixels, 800, 600)
		C.printf(c'gl-triangle-agx: hardware frame rendered successfully%s\n', if displayed {
			c' and copied to /dev/fb0'
		} else {
			c''
		})
		// This marker is deliberately hardware-specific. VirGL, software Mesa and
		// the fake G17 backend must never be reported as an M1 hardware pass.
		if !(usize(renderer) == 0) && contains_ignoring_case(renderer, c'apple m1') {
			C.printf(c'VINIX M1 AGX RENDER TEST: PASS\n')
		}
		C.fflush(C.vkg_stdout())
		C.free(voidptr(pixels))
		C.glDeleteBuffers(1, &vertex_buffer)
		C.glDeleteRenderbuffers(1, &depth_stencil_renderbuffer)
		C.glDeleteRenderbuffers(1, &color_renderbuffer)
		C.glDeleteFramebuffers(1, &framebuffer)
		destroy_render_state(program, voidptr(display), voidptr(surface), voidptr(context))
		return 0
		usage:
		C.fprintf(C.vkg_stderr(), c'usage: %s [--submit-only] [--depth|--stencil|--depth-stencil]\n', argv[0])
		return 2
	}
}
