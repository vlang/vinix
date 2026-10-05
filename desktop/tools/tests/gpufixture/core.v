// SPDX-License-Identifier: BSD-2-Clause
// Independent bounded EGL/GLES failure and ownership model for both backends.
@[translated]
module gpufixture

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
fn C.printf(&char, ...voidptr) i32
fn C.fprintf(voidptr, &char, ...voidptr) i32
fn C.abort()
fn C.malloc(usize) voidptr
fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.strcmp(&char, &char) i32
@[c_extern] __global C.stderr voidptr
fn C.vinix_gpu_present_create(i32, i32) voidptr
fn C.vinix_gpu_present_frame(voidptr, &u32, i32, i32, i32, &u32, i32, i32, i32) i32
fn C.vinix_gpu_present_destroy(voidptr)
fn C.gpf_platform(u32, voidptr, &i32) voidptr

__global fixture_failure i32
__global fixture_allocs [8]voidptr
__global fixture_live_allocations i32
__global fixture_mallocs i32
__global fixture_callocs i32
__global fixture_shader_mask u32
__global fixture_program bool
__global fixture_texture bool
__global fixture_display bool
__global fixture_surface bool
__global fixture_context bool
__global fixture_descriptors i32
__global fixture_current_calls i32
__global fixture_images i32
__global fixture_subimages i32
__global fixture_reads i32
__global fixture_source [32]u32
__global fixture_vertex_pointers [2]voidptr

fn check(ok bool, message &char) {
 if !ok { C.fprintf(C.stderr, c'GPU FIXTURE FAIL: %s\n', message); C.abort() }
}
fn trace(name &char, a i64, b i64) { C.printf(c'%s %ld %ld\n', name, isize(a), isize(b)) }
fn handle(value usize) voidptr { return unsafe { voidptr(value) } }
fn quiescent() {
 check(fixture_live_allocations == 0 && fixture_descriptors == 0, c'host allocation or descriptor retained')
 check(fixture_shader_mask == 0 && !fixture_program && !fixture_texture, c'GL resource retained')
 check(!fixture_display && !fixture_surface && !fixture_context, c'EGL resource retained')
 check(fixture_vertex_pointers[0] == unsafe { nil } && fixture_vertex_pointers[1] == unsafe { nil }, c'GL client pointer retained after context destruction')
}
fn reset(code i32) {
 quiescent()
 unsafe {
  fixture_failure = code
  fixture_mallocs = 0; fixture_callocs = 0; fixture_current_calls = 0
  fixture_images = 0; fixture_subimages = 0; fixture_reads = 0
  for i := 0; i < 32; i++ { fixture_source[i] = u32(0xe0000000) + u32(i) }
 }
 trace(c'CASE', code, 0)
}
fn remember(address voidptr) voidptr {
 unsafe {
  if address == nil { return address }
  for i := 0; i < 8; i++ {
   if fixture_allocs[i] == nil { fixture_allocs[i] = address; fixture_live_allocations++; return address }
  }
 }
 check(false, c'fixture allocation table overflow'); return unsafe { nil }
}
@[export: 'gpf_malloc']
pub fn allocate(size usize) voidptr {
 fixture_mallocs++; trace(c'malloc', i64(size), fixture_mallocs)
 if fixture_failure == 26 && fixture_mallocs == 1 { return unsafe { nil } }
 return remember(C.malloc(size))
}
@[export: 'gpf_calloc']
pub fn allocate_zero(count usize, size usize) voidptr {
 fixture_callocs++; trace(c'calloc', i64(count), i64(size))
 if fixture_failure == 2 { return unsafe { nil } }
 return remember(C.calloc(count, size))
}
@[export: 'gpf_free']
pub fn release(address voidptr) {
 trace(c'free', if address == unsafe { nil } { 0 } else { 1 }, 0)
 if address == unsafe { nil } { return }
 unsafe {
  mut found := false
  for i := 0; i < 8; i++ {
   if fixture_allocs[i] == address { fixture_allocs[i] = nil; fixture_live_allocations--; found = true; break }
  }
  check(found, c'foreign or duplicate free'); C.free(address)
 }
}
@[export: 'gpf_getenv']
pub fn environment(name &char) &char {
 check(C.strcmp(name, c'VINIX_FORCE_SOFTWARE_GL') == 0, c'environment key')
 trace(c'getenv', 0, 0)
 return if fixture_failure == 30 { c'1' } else if fixture_failure == 31 { c'0' } else { unsafe { nil } }
}
@[export: 'gpf_open']
pub fn open(path &char, flags i32) i32 {
 render := C.strcmp(path, c'/dev/dri/renderD128') == 0
 check(render || C.strcmp(path, c'/dev/console') == 0, c'open path')
 check((flags & 3) == 2, c'open access mode')
 trace(if render { c'open-render' } else { c'open-console' }, flags, 0)
 if (render && fixture_failure == 1) || (!render && fixture_failure == 28) { return -1 }
 fixture_descriptors++
 return if render { 81 } else { 82 }
}
@[export: 'gpf_close']
pub fn close(fd i32) i32 {
 check((fd == 81 || fd == 82) && fixture_descriptors > 0, c'close descriptor')
 fixture_descriptors--; trace(c'close', fd, 0); return 0
}
fn ioctl_model(fd i32, request usize, mode i32) i32 {
 check(fd == 82 && request == 0x4b3a && mode == 1, c'graphics console handoff')
 trace(c'ioctl', i64(request), mode)
 return if fixture_failure == 29 { -1 } else { 0 }
}
$if fixture_darwin_arm64 ? {
 @[export: 'gpf_ioctl_body']
 pub fn ioctl(fd i32, request usize, mode i32) i32 { return ioctl_model(fd, request, mode) }
} $else {
 @[export: 'gpf_ioctl']
 pub fn ioctl(fd i32, request usize, mode i32) i32 { return ioctl_model(fd, request, mode) }
}
@[export: 'eglGetProcAddress']
pub fn proc_address(name &char) voidptr {
 check(C.strcmp(name, c'eglGetPlatformDisplayEXT') == 0, c'platform procedure name')
 trace(c'eglGetProcAddress', 0, 0)
 return if fixture_failure == 24 || fixture_failure == 34 { unsafe { nil } } else { unsafe { voidptr(C.gpf_platform) } }
}
@[export: 'gpf_platform']
pub fn platform(kind u32, native voidptr, attributes &i32) voidptr {
 check(kind == 0x31dd && native == unsafe { nil } && attributes == unsafe { nil }, c'platform display arguments')
 trace(c'platform-display', kind, 0)
 if fixture_failure == 3 { return unsafe { nil } }
 fixture_display = true; return handle(0x10)
}
$if fixture_native_display_int ? {
 @[export: 'eglGetDisplay']
 pub fn display(native i32) voidptr {
  check(native == 0, c'default display argument')
  trace(c'eglGetDisplay', 0, 0)
  if fixture_failure == 34 { return unsafe { nil } }
  fixture_display = true; return handle(0x10)
 }
} $else {
 @[export: 'eglGetDisplay']
 pub fn display(native voidptr) voidptr {
  check(native == unsafe { nil }, c'default display argument')
  trace(c'eglGetDisplay', 0, 0)
  if fixture_failure == 34 { return unsafe { nil } }
  fixture_display = true; return handle(0x10)
 }
}
@[export: 'eglInitialize']
pub fn initialize(display voidptr, major &i32, minor &i32) u32 {
 check(display == handle(0x10) && major == unsafe { nil } && minor == unsafe { nil }, c'EGL initialization arguments')
 trace(c'eglInitialize', 0, 0); return if fixture_failure == 4 { u32(0) } else { u32(1) }
}
@[export: 'eglBindAPI']
pub fn bind_api(api u32) u32 {
 check(api == 0x30a0, c'OpenGL ES API'); trace(c'eglBindAPI', api, 0)
 return if fixture_failure == 5 { u32(0) } else { u32(1) }
}
@[export: 'eglChooseConfig']
pub fn choose(display voidptr, attributes &i32, config &voidptr, capacity i32, count &i32) u32 {
 unsafe {
  check(display == handle(0x10) && capacity == 1, c'EGL config arguments')
  expected := [i32(0x3033), i32(1), i32(0x3040), i32(4), i32(0x3024), i32(8), i32(0x3023), i32(8), i32(0x3022), i32(8), i32(0x3021), i32(8), i32(0x3038)]!
  for i := 0; i < 13; i++ { check(attributes[i] == expected[i], c'EGL config attributes') }
  trace(c'eglChooseConfig', 0, 0); *config = handle(0x20); *count = if fixture_failure == 7 { 0 } else { 1 }
  return if fixture_failure == 6 { u32(0) } else { u32(1) }
 }
}
@[export: 'eglCreatePbufferSurface']
pub fn surface(display voidptr, config voidptr, attributes &i32) voidptr {
 unsafe {
  check(display == handle(0x10) && config == handle(0x20), c'EGL surface handles')
  expected := [i32(0x3057), i32(3), i32(0x3056), i32(2), i32(0x3038)]!
  for i := 0; i < 5; i++ { check(attributes[i] == expected[i], c'EGL surface attributes') }
 }
 trace(c'eglCreatePbufferSurface', 0, 0)
 if fixture_failure == 8 { return unsafe { nil } }; fixture_surface = true; return handle(0x30)
}
@[export: 'eglCreateContext']
pub fn context(display voidptr, config voidptr, share voidptr, attributes &i32) voidptr {
 unsafe {
  check(display == handle(0x10) && config == handle(0x20) && share == nil, c'EGL context handles')
  check(attributes[0] == 0x3098 && attributes[1] == 2 && attributes[2] == 0x3038, c'EGL context attributes')
 }
 trace(c'eglCreateContext', 0, 0)
 if fixture_failure == 9 { return unsafe { nil } }; fixture_context = true; return handle(0x40)
}
@[export: 'eglMakeCurrent']
pub fn make_current(display voidptr, draw voidptr, read voidptr, context voidptr) u32 {
 fixture_current_calls++
 check(display == handle(0x10), c'current display')
 check((draw == handle(0x30) && read == handle(0x30) && context == handle(0x40)) ||
  (draw == unsafe { nil } && read == unsafe { nil } && context == unsafe { nil }), c'current surface/context tuple')
 trace(c'eglMakeCurrent', if context == unsafe { nil } { 0 } else { 1 }, fixture_current_calls)
 return if (fixture_failure == 10 && fixture_current_calls == 1) || (fixture_failure == 25 && fixture_current_calls == 2) ||
  (fixture_failure == 32 && fixture_current_calls == 7) || (fixture_failure == 33 && context == unsafe { nil }) { u32(0) } else { u32(1) }
}
@[export: 'eglDestroySurface']
pub fn destroy_surface(display voidptr, surface voidptr) u32 {
 check(display == handle(0x10) && surface == handle(0x30) && fixture_surface, c'surface ownership')
 fixture_surface = false; trace(c'eglDestroySurface', 0, 0); return 1
}
@[export: 'eglDestroyContext']
pub fn destroy_context(display voidptr, context voidptr) u32 {
 check(display == handle(0x10) && context == handle(0x40) && fixture_context, c'context ownership')
 check_client_pointers()
 unsafe { fixture_vertex_pointers[0] = nil; fixture_vertex_pointers[1] = nil }
 fixture_context = false; trace(c'eglDestroyContext', 0, 0); return 1
}
@[export: 'eglTerminate']
pub fn terminate(display voidptr) u32 {
 check(display == handle(0x10) && fixture_display && !fixture_context && !fixture_surface, c'EGL termination ordering')
 check(fixture_shader_mask == 0 && !fixture_program && !fixture_texture, c'GL retirement before EGL termination')
 fixture_display = false; trace(c'eglTerminate', 0, 0); return 1
}
@[export: 'glGetString']
pub fn renderer(kind u32) &u8 {
 check(kind == 0x1f01, c'renderer query'); trace(c'glGetString', kind, 0)
 return unsafe { &u8(if fixture_failure == 11 { &char(nil) } else if fixture_failure == 12 { c'llvmpipe' }
  else if fixture_failure == 13 { c'softpipe' } else if fixture_failure == 14 { c'swrast' } else { c'AGX fixture' }) }
}
@[export: 'glCreateShader']
pub fn shader(kind u32) u32 {
 check(kind == 0x8b31 || kind == 0x8b30, c'shader kind'); trace(c'glCreateShader', kind, 0)
 vertex := kind == 0x8b31
 if (vertex && fixture_failure == 15) || (!vertex && fixture_failure == 17) { return 0 }
 bit := if vertex { u32(1) } else { u32(2) }
 check((fixture_shader_mask & bit) == 0, c'shader already live'); fixture_shader_mask |= bit
 return if vertex { u32(101) } else { u32(102) }
}
@[export: 'glShaderSource']
pub fn shader_source(shader u32, count i32, sources voidptr, length &i32) {
 unsafe {
  check(count == 1 && length == nil && (shader == 101 || shader == 102), c'shader source arguments')
  mut expected := &char(nil)
  if shader == 101 { expected = c'attribute vec2 position;\nattribute vec2 texcoord;\nvarying vec2 texture_coord;\nvoid main(void) {\n  gl_Position = vec4(position, 0.0, 1.0);\n  texture_coord = texcoord;\n}\n' }
   else { expected = c'precision mediump float;\nuniform sampler2D frame;\nvarying vec2 texture_coord;\nvoid main(void) {\n  gl_FragColor = texture2D(frame, texture_coord);\n}\n' }
  check(C.strcmp((&&char(sources))[0], expected) == 0, c'exact GLSL source')
 }
 trace(c'glShaderSource', shader, count)
}
@[export: 'glCompileShader']
pub fn compile_shader(shader u32) { trace(c'glCompileShader', shader, 0) }
@[export: 'glGetShaderiv']
pub fn shader_status(shader u32, kind u32, status &i32) {
 check(kind == 0x8b81, c'shader status query'); trace(c'glGetShaderiv', shader, kind)
 unsafe { *status = if (shader == 101 && fixture_failure == 16) || (shader == 102 && fixture_failure == 18) { 0 } else { 1 } }
}
@[export: 'glDeleteShader']
pub fn delete_shader(shader u32) {
 bit := if shader == 101 { u32(1) } else if shader == 102 { u32(2) } else { u32(0) }
 check(bit != 0 && (fixture_shader_mask & bit) != 0, c'shader ownership')
 fixture_shader_mask &= ~bit; trace(c'glDeleteShader', shader, 0)
}
@[export: 'glCreateProgram']
pub fn program() u32 {
 trace(c'glCreateProgram', 0, 0); if fixture_failure == 19 { return 0 }
 check(!fixture_program, c'program already live'); fixture_program = true; return 50
}
@[export: 'glAttachShader']
pub fn attach(program u32, shader u32) { check(program == 50 && fixture_program, c'attach program'); trace(c'glAttachShader', program, shader) }
@[export: 'glLinkProgram']
pub fn link(program u32) { trace(c'glLinkProgram', program, 0) }
@[export: 'glGetProgramiv']
pub fn program_status(program u32, kind u32, status &i32) {
 check(program == 50 && kind == 0x8b82, c'program status query'); trace(c'glGetProgramiv', program, kind)
 unsafe { *status = if fixture_failure == 20 { 0 } else { 1 } }
}
@[export: 'glDeleteProgram']
pub fn delete_program(program u32) { check(program == 50 && fixture_program, c'program ownership'); fixture_program = false; trace(c'glDeleteProgram', program, 0) }
@[export: 'glGetAttribLocation']
pub fn attribute(program u32, name &char) i32 {
 position := C.strcmp(name, c'position') == 0
 check(program == 50 && (position || C.strcmp(name, c'texcoord') == 0), c'attribute query')
 trace(c'glGetAttribLocation', if position { 0 } else { 1 }, 0)
 return if (position && fixture_failure == 21) || (!position && fixture_failure == 22) { -1 } else if position { 3 } else { 4 }
}
@[export: 'glGenTextures']
pub fn texture(count i32, output &u32) {
 check(count == 1 && !fixture_texture, c'texture creation'); trace(c'glGenTextures', count, 0)
 unsafe { *output = if fixture_failure == 23 { u32(0) } else { u32(60) } }; fixture_texture = fixture_failure != 23
}
@[export: 'glDeleteTextures']
pub fn delete_texture(count i32, texture &u32) {
 check(count == 1 && unsafe { *texture == 60 } && fixture_texture, c'texture ownership')
 fixture_texture = false; trace(c'glDeleteTextures', count, 60)
}
@[export: 'glBindTexture']
pub fn bind_texture(kind u32, texture u32) { check(kind == 0x0de1 && texture == 60 && fixture_texture, c'texture binding'); trace(c'glBindTexture', kind, texture) }
@[export: 'glTexParameteri']
pub fn texture_parameter(kind u32, parameter u32, value i32) {
 check(kind == 0x0de1, c'texture parameter target'); trace(c'glTexParameteri', parameter, value)
 check(((parameter == 0x2801 || parameter == 0x2800) && value == 0x2600) ||
  ((parameter == 0x2802 || parameter == 0x2803) && value == 0x812f), c'texture parameter value')
}
@[export: 'glUseProgram']
pub fn use_program(program u32) { check(program == 50 && fixture_program, c'program use'); trace(c'glUseProgram', program, 0) }
@[export: 'glGetUniformLocation']
pub fn uniform_location(program u32, name &char) i32 { check(program == 50 && C.strcmp(name, c'frame') == 0, c'uniform query'); trace(c'glGetUniformLocation', program, 0); return 7 }
@[export: 'glUniform1i']
pub fn uniform(location i32, value i32) { check(location == 7 && value == 0, c'sampler uniform'); trace(c'glUniform1i', location, value) }
@[export: 'glViewport']
pub fn viewport(x i32, y i32, width i32, height i32) { check(x == 0 && y == 0 && width == 3 && height == 2, c'viewport dimensions'); trace(c'glViewport', width, height) }
@[export: 'glActiveTexture']
pub fn active_texture(texture u32) { check(texture == 0x84c0, c'active texture'); trace(c'glActiveTexture', texture, 0) }
@[export: 'glPixelStorei']
pub fn pixel_store(kind u32, alignment i32) { check((kind == 0x0cf5 || kind == 0x0d05) && alignment == 4, c'pixel packing'); trace(c'glPixelStorei', kind, alignment) }
fn upload(width i32, height i32, format u32, kind u32, source voidptr) {
 check(width > 0 && height > 0 && width * height <= 32 && format == 0x1908 && kind == 0x1401, c'upload format and dimensions')
 unsafe { for i := i32(0); i < width * height; i++ { check((&u32(source))[i] == fixture_source[i], c'upload pixels') } }
}
@[export: 'glTexImage2D']
pub fn image(target u32, level i32, internal i32, width i32, height i32, border i32, format u32, kind u32, source voidptr) {
 check(target == 0x0de1 && level == 0 && internal == 0x1908 && border == 0, c'texture image arguments')
 upload(width, height, format, kind, source); fixture_images++; trace(c'glTexImage2D', width, height)
}
@[export: 'glTexSubImage2D']
pub fn subimage(target u32, level i32, x i32, y i32, width i32, height i32, format u32, kind u32, source voidptr) {
 check(target == 0x0de1 && level == 0 && x == 0 && y == 0, c'texture subimage arguments')
 upload(width, height, format, kind, source); fixture_subimages++; trace(c'glTexSubImage2D', width, height)
}
@[export: 'glVertexAttribPointer']
pub fn vertex_pointer(index u32, count i32, kind u32, normalized u8, stride i32, pointer voidptr) {
 check((index == 3 || index == 4) && count == 2 && kind == 0x1406 && normalized == 0 && stride == 16, c'vertex array arguments')
 unsafe { fixture_vertex_pointers[index - 3] = pointer }
 check_client_pointers()
 trace(c'glVertexAttribPointer', index, stride)
}
fn check_client_pointers() {
 expected := [f32(-1), f32(-1), f32(0), f32(0), f32(1), f32(-1), f32(1), f32(0), f32(-1), f32(1), f32(0), f32(1), f32(1), f32(1), f32(1), f32(1)]!
 unsafe {
  for slot := 0; slot < 2; slot++ {
   if fixture_vertex_pointers[slot] == nil { continue }
   for i := 0; i < 4; i++ { for j := 0; j < 2; j++ {
    check((&f32(fixture_vertex_pointers[slot]))[i * 4 + j] == expected[i * 4 + j + slot * 2], c'retained GL client vertex or texture coordinate')
   } }
  }
 }
}
@[export: 'glEnableVertexAttribArray']
pub fn enable_vertex(index u32) { check(index == 3 || index == 4, c'attribute enable'); trace(c'glEnableVertexAttribArray', index, 0) }
@[export: 'glDrawArrays']
pub fn draw(kind u32, start i32, count i32) { check(kind == 5 && start == 0 && count == 4, c'draw shape'); trace(c'glDrawArrays', kind, count) }
@[export: 'glReadPixels']
pub fn read_pixels(x i32, y i32, width i32, height i32, format u32, kind u32, output voidptr) {
 check(x == 0 && y == 0 && width == 3 && height == 2 && format == 0x1908 && kind == 0x1401, c'readback format')
 fixture_reads++; trace(c'glReadPixels', width, height)
 unsafe { for i := i32(0); i < width * height; i++ { (&u32(output))[i] = u32(0xa5000000) + u32(i) } }
}
@[export: 'glGetError']
pub fn gl_error() u32 { trace(c'glGetError', 0, 0); return if fixture_failure == 27 && fixture_reads == 1 { u32(0x0502) } else { u32(0) } }

fn exercise_frames(p voidptr) {
 unsafe {
  mut destination := [10]u32{}
  for i := 0; i < 10; i++ { destination[i] = 0xdeadbeef }
  check(C.vinix_gpu_present_frame(nil, &fixture_source[0], 3, 2, 3, &destination[0], 3, 2, 5) == 0, c'null presenter')
  check(C.vinix_gpu_present_frame(p, nil, 3, 2, 3, &destination[0], 3, 2, 5) == 0, c'null source')
  check(C.vinix_gpu_present_frame(p, &fixture_source[0], 3, 2, 3, nil, 3, 2, 5) == 0, c'null destination')
  check(C.vinix_gpu_present_frame(p, &fixture_source[0], 0, 2, 0, &destination[0], 3, 2, 5) == 0, c'zero source width')
  check(C.vinix_gpu_present_frame(p, &fixture_source[0], 3, 0, 3, &destination[0], 3, 2, 5) == 0, c'zero source height')
  check(C.vinix_gpu_present_frame(p, &fixture_source[0], 3, 2, 4, &destination[0], 3, 2, 5) == 0, c'source stride rejected')
  check(C.vinix_gpu_present_frame(p, &fixture_source[0], 3, 2, 3, &destination[0], 2, 2, 5) == 0, c'output width mismatch')
  check(C.vinix_gpu_present_frame(p, &fixture_source[0], 3, 2, 3, &destination[0], 3, 1, 5) == 0, c'output height mismatch')
  check(C.vinix_gpu_present_frame(p, &fixture_source[0], 3, 2, 3, &destination[0], 3, 2, 2) == 0, c'output stride rejected')
  first := C.vinix_gpu_present_frame(p, &fixture_source[0], 3, 2, 3, &destination[0], 3, 2, 5)
  failing := fixture_failure == 25 || fixture_failure == 26 || fixture_failure == 27
  check(first == if failing { 0 } else { 1 }, c'first frame outcome')
  check_client_pointers()
  if failing { for i := 0; i < 10; i++ { check(destination[i] == 0xdeadbeef, c'failed frame changed destination') } }
  for iteration := 0; iteration < 4; iteration++ {
   width := if iteration == 2 { i32(2) } else { i32(3) }
   height := if iteration == 2 { i32(3) } else { i32(2) }
   check(C.vinix_gpu_present_frame(p, &fixture_source[0], width, height, width, &destination[0], 3, 2, 5) == 1, c'repeated frame outcome')
   check_client_pointers()
   for row := 0; row < 2; row++ {
    for column := 0; column < 3; column++ { check(destination[row * 5 + column] == u32(0xa5000000 + row * 3 + column), c'packed output row pixels') }
    check(destination[row * 5 + 3] == 0xdeadbeef && destination[row * 5 + 4] == 0xdeadbeef, c'destination padding overwritten')
   }
  }
  check(fixture_live_allocations == 2 && fixture_mallocs == if fixture_failure == 26 { 2 } else { 1 }, c'readback allocated once after success')
  check(fixture_images == 3 && fixture_subimages >= 1, c'texture resize and reuse counts')
  trace(c'PIXELS', i64(destination[0]), i64(destination[7]))
 }
}
@[export: 'main']
pub fn run() i32 {
 unsafe {
  reset(0)
  check(C.vinix_gpu_present_create(0, 2) == nil && C.vinix_gpu_present_create(3, 0) == nil && C.vinix_gpu_present_create(-1, 2) == nil, c'invalid presenter dimensions')
  C.vinix_gpu_present_destroy(nil); quiescent()
  for code := i32(1); code <= 34; code++ {
   reset(code); p := C.vinix_gpu_present_create(3, 2)
   succeeds := code >= 24 && code <= 33 && code != 30
   check((p != nil) == succeeds, c'presenter creation outcome')
   if succeeds { exercise_frames(p) }
   C.vinix_gpu_present_destroy(p); quiescent()
   trace(c'RETIRED', fixture_callocs, fixture_mallocs)
  }
  for cycle := 0; cycle < 32; cycle++ {
   reset(0); p := C.vinix_gpu_present_create(3, 2)
   check(p != nil, c'repeated presenter creation'); exercise_frames(p)
   C.vinix_gpu_present_destroy(p); quiescent()
  }
  trace(c'GPU FIXTURE PASS', 67, 0); return 0
 }
}
