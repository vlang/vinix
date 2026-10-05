// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Firmware framebuffer presentation: GLES composition followed by CPU readback.
@[translated]
module gpucore

// ABI readonly: vinix_gpu_present_startup_stage.stage
// ABI readonly: vinix_gpu_present_frame.source

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>
$if gpu_presenter_enabled ? {
    #include <EGL/egl.h>
    #include <EGL/eglext.h>
    #include <GLES2/gl2.h>
}

@[c_extern] __global C.stderr voidptr
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.fflush(voidptr) i32
fn C.getenv(&char) &char
fn C.strcmp(&char, &char) i32
fn C.strstr(&char, &char) &char
fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.ioctl(i32, usize, ...voidptr) i32
fn C.calloc(usize, usize) voidptr
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.eglGetProcAddress(&char) voidptr
fn C.eglGetDisplay(i32) voidptr
fn C.eglInitialize(voidptr, &i32, &i32) u32
fn C.eglBindAPI(u32) u32
fn C.eglChooseConfig(voidptr, &i32, &voidptr, i32, &i32) u32
fn C.eglCreatePbufferSurface(voidptr, voidptr, &i32) voidptr
fn C.eglCreateContext(voidptr, voidptr, voidptr, &i32) voidptr
fn C.eglMakeCurrent(voidptr, voidptr, voidptr, voidptr) u32
fn C.eglDestroySurface(voidptr, voidptr) u32
fn C.eglDestroyContext(voidptr, voidptr) u32
fn C.eglTerminate(voidptr) u32
fn C.glCreateShader(u32) u32
fn C.glShaderSource(u32, i32, voidptr, &i32)
fn C.glCompileShader(u32)
fn C.glGetShaderiv(u32, u32, &i32)
fn C.glDeleteShader(u32)
fn C.glDeleteProgram(u32)
fn C.glDeleteTextures(i32, &u32)
fn C.glGetString(u32) &u8
fn C.glCreateProgram() u32
fn C.glAttachShader(u32, u32)
fn C.glLinkProgram(u32)
fn C.glGetProgramiv(u32, u32, &i32)
fn C.glGetAttribLocation(u32, &char) i32
fn C.glGenTextures(i32, &u32)
fn C.glBindTexture(u32, u32)
fn C.glTexParameteri(u32, u32, i32)
fn C.glUseProgram(u32)
fn C.glUniform1i(i32, i32)
fn C.glGetUniformLocation(u32, &char) i32
fn C.glViewport(i32, i32, i32, i32)
fn C.glActiveTexture(u32)
fn C.glPixelStorei(u32, i32)
fn C.glTexImage2D(u32, i32, i32, i32, i32, i32, u32, u32, voidptr)
fn C.glTexSubImage2D(u32, i32, i32, i32, i32, i32, u32, u32, voidptr)
fn C.glVertexAttribPointer(u32, i32, u32, u8, i32, voidptr)
fn C.glEnableVertexAttribArray(u32)
fn C.glDrawArrays(u32, i32, i32)
fn C.glReadPixels(i32, i32, i32, i32, u32, u32, voidptr)
fn C.glGetError() u32

struct Presenter {
mut:
    display voidptr
    surface voidptr
    context voidptr
    program u32
    texture u32
    position i32
    texcoord i32
    width i32
    height i32
    texture_width i32
    texture_height i32
    first_frame_started i32
    readback &u32
}

type PlatformDisplay = fn (u32, voidptr, &i32) voidptr

// GL retains these client-array addresses after a frame. Preserve the original
// static lifetime even between frames and during context destruction.
@[cinit]
__global presenter_vertices = [f32(-1), f32(-1), f32(0), f32(0), f32(1), f32(-1),
    f32(1), f32(0), f32(-1), f32(1), f32(0), f32(1), f32(1), f32(1), f32(1), f32(1)]!

@[export: 'vinix_desktop_set_console_mode']
pub fn console_mode(graphics i32) {
    fd := C.open(c'/dev/console', C.O_RDWR | C.O_CLOEXEC)
    if fd < 0 { return }
    C.ioctl(fd, usize(0x4b3a), i32(if graphics != 0 { 1 } else { 0 }))
    C.close(fd)
}

@[export: 'vinix_gpu_present_startup_stage']
pub fn startup_stage(stage &char) {
    $if gpu_presenter_enabled ? {
        C.fprintf(C.stderr, c'vinix-desktop: GPU init: %s\n', stage)
        C.fflush(C.stderr)
    } $else { _ = stage }
}

fn compile_shader(kind u32, source &char) u32 {
    $if gpu_presenter_enabled ? {
        unsafe {
            shader := C.glCreateShader(kind)
            if shader == 0 { return 0 }
            mut ok := i32(0)
            C.glShaderSource(shader, 1, voidptr(&source), nil)
            C.glCompileShader(shader)
            C.glGetShaderiv(shader, C.GL_COMPILE_STATUS, &ok)
            if ok != C.GL_TRUE { C.glDeleteShader(shader); return 0 }
            return shader
        }
    } $else { _ = kind; _ = source; return 0 }
}

// EGL copies attribute lists during the call. Keep the stack lists in the
// caller and publish only the returned handles through these synchronous helpers.
fn create_surface(p &Presenter, config voidptr, attributes &i32) {
    $if gpu_presenter_enabled ? {
        unsafe { p.surface = C.eglCreatePbufferSurface(p.display, config, attributes) }
    } $else { _ = p; _ = config; _ = attributes }
}
fn create_context(p &Presenter, config voidptr, attributes &i32) {
    $if gpu_presenter_enabled ? {
        unsafe { p.context = C.eglCreateContext(p.display, config, nil, attributes) }
    } $else { _ = p; _ = config; _ = attributes }
}

fn destroy_presenter(p &Presenter) {
    $if gpu_presenter_enabled ? {
        unsafe {
            if p == nil { return }
            if p.display != nil {
                if p.context != nil {
                    if p.surface != nil { C.eglMakeCurrent(p.display, p.surface, p.surface, p.context) }
                    if p.program != 0 { C.glDeleteProgram(p.program) }
                    if p.texture != 0 { C.glDeleteTextures(1, &p.texture) }
                }
                C.eglMakeCurrent(p.display, nil, nil, nil)
                if p.surface != nil { C.eglDestroySurface(p.display, p.surface) }
                if p.context != nil { C.eglDestroyContext(p.display, p.context) }
                C.eglTerminate(p.display)
            }
            C.free(p.readback)
            C.free(p)
        }
    } $else { _ = p }
}

@[export: 'vinix_gpu_present_create']
pub fn create(width i32, height i32) voidptr {
    $if gpu_presenter_enabled ? {
        unsafe {
            config_attributes := [i32(C.EGL_SURFACE_TYPE), i32(C.EGL_PBUFFER_BIT),
                i32(C.EGL_RENDERABLE_TYPE), i32(C.EGL_OPENGL_ES2_BIT), i32(C.EGL_RED_SIZE), i32(8),
                i32(C.EGL_GREEN_SIZE), i32(8), i32(C.EGL_BLUE_SIZE), i32(8), i32(C.EGL_ALPHA_SIZE),
                i32(8), i32(C.EGL_NONE)]!
            surface_attributes := [i32(C.EGL_WIDTH), width, i32(C.EGL_HEIGHT), height, i32(C.EGL_NONE)]!
            context_attributes := [i32(C.EGL_CONTEXT_CLIENT_VERSION), i32(2), i32(C.EGL_NONE)]!
            mut config := voidptr(nil)
            mut config_count := i32(0)
            mut vertex_shader := u32(0)
            mut fragment_shader := u32(0)
            mut linked := i32(0)
            startup_stage(c'presenter creation entered')
            if width <= 0 || height <= 0 { return nil }
            force_software := C.getenv(c'VINIX_FORCE_SOFTWARE_GL')
            if force_software != nil && C.strcmp(force_software, c'1') == 0 { return nil }
            startup_stage(c'presenter arguments validated')
            startup_stage(c'opening render node')
            render_fd := C.open(c'/dev/dri/renderD128', C.O_RDWR | C.O_CLOEXEC)
            if render_fd < 0 { return nil }
            C.close(render_fd)
            startup_stage(c'render node opened')
            startup_stage(c'allocating presenter state')
            p := &Presenter(C.calloc(1, sizeof(Presenter)))
            if p == nil { return nil }
            p.width = width; p.height = height
            startup_stage(c'presenter state allocated')
            startup_stage(c'resolving EGL platform display entrypoint')
            get_platform_display := PlatformDisplay(C.eglGetProcAddress(c'eglGetPlatformDisplayEXT'))
            startup_stage(c'acquiring surfaceless EGL display')
            p.display = if get_platform_display != nil { get_platform_display(u32(0x31dd), nil, nil) }
                else { C.eglGetDisplay(C.EGL_DEFAULT_DISPLAY) }
            if p.display == nil { goto fail }
            startup_stage(c'surfaceless EGL display acquired')
            startup_stage(c'initializing EGL')
            if C.eglInitialize(p.display, nil, nil) == 0 { goto fail }
            startup_stage(c'EGL initialized')
            startup_stage(c'binding OpenGL ES')
            if C.eglBindAPI(C.EGL_OPENGL_ES_API) == 0 { goto fail }
            startup_stage(c'OpenGL ES bound')
            startup_stage(c'choosing EGL config')
            if C.eglChooseConfig(p.display, &config_attributes[0], &config, 1, &config_count) == 0 || config_count != 1 { goto fail }
            startup_stage(c'EGL config chosen')
            startup_stage(c'creating pbuffer surface')
            create_surface(p, config, &surface_attributes[0])
            if p.surface == nil { goto fail }
            startup_stage(c'pbuffer surface created')
            startup_stage(c'creating EGL context')
            create_context(p, config, &context_attributes[0])
            if p.context == nil { goto fail }
            startup_stage(c'EGL context created')
            startup_stage(c'making EGL context current')
            if C.eglMakeCurrent(p.display, p.surface, p.surface, p.context) == 0 { goto fail }
            startup_stage(c'EGL context current')
            startup_stage(c'querying renderer')
            renderer := &char(C.glGetString(C.GL_RENDERER))
            if renderer == nil || C.strstr(renderer, c'llvmpipe') != nil || C.strstr(renderer, c'softpipe') != nil || C.strstr(renderer, c'swrast') != nil { goto fail }
            startup_stage(c'hardware renderer accepted')
            startup_stage(c'compiling vertex shader')
            vertex_shader = compile_shader(C.GL_VERTEX_SHADER, c'attribute vec2 position;\nattribute vec2 texcoord;\nvarying vec2 texture_coord;\nvoid main(void) {\n  gl_Position = vec4(position, 0.0, 1.0);\n  texture_coord = texcoord;\n}\n')
            if vertex_shader == 0 { goto fail }
            startup_stage(c'vertex shader compiled')
            startup_stage(c'compiling fragment shader')
            fragment_shader = compile_shader(C.GL_FRAGMENT_SHADER, c'precision mediump float;\nuniform sampler2D frame;\nvarying vec2 texture_coord;\nvoid main(void) {\n  gl_FragColor = texture2D(frame, texture_coord);\n}\n')
            if fragment_shader == 0 { goto fail }
            startup_stage(c'fragment shader compiled')
            startup_stage(c'creating shader program')
            p.program = C.glCreateProgram()
            if p.program == 0 { goto fail }
            C.glAttachShader(p.program, vertex_shader); C.glAttachShader(p.program, fragment_shader)
            startup_stage(c'linking shader program')
            C.glLinkProgram(p.program)
            C.glGetProgramiv(p.program, C.GL_LINK_STATUS, &linked)
            C.glDeleteShader(vertex_shader); C.glDeleteShader(fragment_shader)
            vertex_shader = 0; fragment_shader = 0
            if linked != C.GL_TRUE { goto fail }
            startup_stage(c'shader program linked')
            startup_stage(c'querying shader attributes')
            p.position = C.glGetAttribLocation(p.program, c'position')
            p.texcoord = C.glGetAttribLocation(p.program, c'texcoord')
            if p.position < 0 || p.texcoord < 0 { goto fail }
            startup_stage(c'shader attributes ready')
            startup_stage(c'creating frame texture')
            C.glGenTextures(1, &p.texture)
            if p.texture == 0 { goto fail }
            C.glBindTexture(C.GL_TEXTURE_2D, p.texture)
            C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MIN_FILTER, C.GL_NEAREST)
            C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_MAG_FILTER, C.GL_NEAREST)
            C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_S, C.GL_CLAMP_TO_EDGE)
            C.glTexParameteri(C.GL_TEXTURE_2D, C.GL_TEXTURE_WRAP_T, C.GL_CLAMP_TO_EDGE)
            C.glUseProgram(p.program)
            C.glUniform1i(C.glGetUniformLocation(p.program, c'frame'), 0)
            startup_stage(c'frame texture configured')
            C.fprintf(C.stderr, c'vinix-desktop: GPU presentation enabled on %s\n', renderer)
            C.fflush(C.stderr)
            return p
            fail:
            if vertex_shader != 0 { C.glDeleteShader(vertex_shader) }
            if fragment_shader != 0 { C.glDeleteShader(fragment_shader) }
            destroy_presenter(p)
            return nil
        }
    } $else { _ = width; _ = height; return unsafe { nil } }
}

@[export: 'vinix_gpu_present_frame']
pub fn frame(opaque voidptr, source &u32, source_width i32, source_height i32,
    source_stride i32, destination &u32, destination_width i32, destination_height i32,
    destination_stride i32) i32 {
    $if gpu_presenter_enabled ? {
        unsafe {
            mut p := &Presenter(opaque)
            if p == nil || source == nil || destination == nil || source_width <= 0 || source_height <= 0 ||
                source_stride != source_width || destination_width != p.width || destination_height != p.height ||
                destination_stride < destination_width { return 0 }
            trace_first := p.first_frame_started == 0
            p.first_frame_started = 1
            if trace_first { startup_stage(c'first frame begin'); startup_stage(c'making first-frame context current') }
            if C.eglMakeCurrent(p.display, p.surface, p.surface, p.context) == 0 { return 0 }
            if trace_first { startup_stage(c'first-frame context current') }
            if p.readback == nil {
                if trace_first { startup_stage(c'allocating packed readback buffer') }
                p.readback = &u32(C.malloc(usize(destination_width) * usize(destination_height) * sizeof(u32)))
                if p.readback == nil { return 0 }
            }
            output := p.readback
            if trace_first { startup_stage(c'configuring first-frame viewport') }
            C.glViewport(0, 0, destination_width, destination_height)
            C.glActiveTexture(C.GL_TEXTURE0); C.glBindTexture(C.GL_TEXTURE_2D, p.texture)
            C.glPixelStorei(C.GL_UNPACK_ALIGNMENT, 4)
            if trace_first { startup_stage(c'uploading first frame') }
            if p.texture_width != source_width || p.texture_height != source_height {
                if trace_first { startup_stage(c'allocating and uploading first texture') }
                C.glTexImage2D(C.GL_TEXTURE_2D, 0, C.GL_RGBA, source_width, source_height, 0, C.GL_RGBA, C.GL_UNSIGNED_BYTE, source)
                p.texture_width = source_width; p.texture_height = source_height
            } else { C.glTexSubImage2D(C.GL_TEXTURE_2D, 0, 0, 0, source_width, source_height, C.GL_RGBA, C.GL_UNSIGNED_BYTE, source) }
            if trace_first { startup_stage(c'first texture upload returned'); startup_stage(c'configuring first-frame shader inputs') }
            C.glUseProgram(p.program)
            C.glVertexAttribPointer(u32(p.position), 2, C.GL_FLOAT, u8(C.GL_FALSE), i32(4 * sizeof(f32)), &presenter_vertices[0])
            C.glVertexAttribPointer(u32(p.texcoord), 2, C.GL_FLOAT, u8(C.GL_FALSE), i32(4 * sizeof(f32)), &presenter_vertices[2])
            C.glEnableVertexAttribArray(u32(p.position)); C.glEnableVertexAttribArray(u32(p.texcoord))
            if trace_first { startup_stage(c'submitting first draw') }
            C.glDrawArrays(C.GL_TRIANGLE_STRIP, 0, 4)
            if trace_first { startup_stage(c'first draw returned') }
            C.glPixelStorei(C.GL_PACK_ALIGNMENT, 4)
            if trace_first { startup_stage(c'reading back first frame') }
            C.glReadPixels(0, 0, destination_width, destination_height, C.GL_RGBA, C.GL_UNSIGNED_BYTE, output)
            if trace_first { startup_stage(c'first readback returned'); startup_stage(c'checking first-frame GL status') }
            if C.glGetError() != C.GL_NO_ERROR { return 0 }
            if trace_first { startup_stage(c'first frame ready; entering graphics mode') }
            console_mode(1)
            for row := i32(0); row < destination_height; row++ {
                C.memcpy(destination + usize(row) * usize(destination_stride), output + usize(row) * usize(destination_width), usize(destination_width) * sizeof(u32))
            }
            return 1
        }
    } $else {
        _ = opaque; _ = source; _ = source_width; _ = source_height; _ = source_stride
        _ = destination; _ = destination_width; _ = destination_height; _ = destination_stride
        return 0
    }
}

@[export: 'vinix_gpu_present_destroy']
pub fn destroy(opaque voidptr) { destroy_presenter(unsafe { &Presenter(opaque) }) }
