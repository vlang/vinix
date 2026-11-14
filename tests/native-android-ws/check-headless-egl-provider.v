// SPDX-License-Identifier: GPL-2.0-or-later
// Production provider initialization and lookup, with real concurrent callers.
module main
import os
import crypto.sha256
fn function(source string, name string) !string {
 start := source.index('fn ' + name + '(') or { return error('missing ' + name) }
 end := source[start..].index('\n}') or { return error('unterminated ' + name) }
 return source[start..start + end + 2]
}
fn main() {
 if os.args.len != 2 { panic('usage: check-headless-egl-provider FRESH_EXTERNAL_OUTPUT') }
 root := os.abs_path(os.args[1])
 if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') { panic('fresh external output required') }
 os.mkdir_all(root)!
 source := os.read_file('build-support/android/nativews/egl_state.v')!
 headless := os.read_file('build-support/android/nativews/headless.v')!
 entry := function(headless, 'ws_service_main')!
 prepared_at := entry.index('ws_egl_prepare()') or { panic('missing preparation') }
 bootstrap_at := entry.index('ws_bootstrap(') or { panic('missing bootstrap') }
 assert prepared_at < bootstrap_at
 assert !entry.contains('ws_egl_init(') && !entry.contains('ws_draw_init(')
 mut code := ''
 for name in ['ws_egl_symbol', 'ws_egl_prepare', 'ws_egl_init', 'ws_egl_display'] { code += function(source, name)! + '\n' }
 for name in ['pthread_key_create', 'dlopen', 'dlsym', 'dlerror', 'setenv'] { code = code.replace('C.' + name, 'probe_' + name) }
 variants := [code,
 code.replace('if !ws_egl_init(ws.root) {', 'if false {'),
 code.replace('if ws_egl_provider != nil { return true }', 'if false { return true }')]
 os.write_file(root + '/egl_state.v.input', source)!
 os.write_file(root + '/headless.v.input', headless)!
 for index, variant in variants {
  dir := root + '/case-' + index.str()
  os.mkdir(dir)!
  os.write_file(dir + '/main.v', model + variant + cases)!
  build := os.exec(['/Users/alex/code/v/v', '-new-compiler', '-no-parallel', '-nocache', '-gc', 'boehm', '-enable-globals', '-cc', 'cc', '-o', dir + '/probe', dir + '/main.v'])
  os.write_file(dir + '/build.log', build.output)!
  assert build.exit_code == 0, build.output
  run := os.exec([dir + '/probe'])
  os.write_file(dir + '/run.log', run.output)!
  if index == 0 {
   assert run.exit_code == 0, run.output
   for fail in ['--missing-provider', '--missing-symbol'] {
    result := os.exec([dir + '/probe', fail])
    os.write_file(dir + '/' + fail[2..] + '.log', result.output)!
    assert result.exit_code != 0 && result.output.contains('ANDROID-WS-FAIL EGL provider'), result.output
   }
  } else { assert run.exit_code != 0 && run.output.contains('assert'), 'mutation survived ' + index.str() }
 }
 os.write_file(root + '/inputs.sha256', sha256.hexhash(source) + ' egl_state.v\n' + sha256.hexhash(headless) + ' headless.v\n' + sha256.sum(os.read_bytes('/Users/alex/code/v/v')!).hex() + ' compiler\n')!
 println('HEADLESS-EGL-PROVIDER-PASS lazy queries pthreads repeat-UI-init TLS-identity failures two-mutations')
}
const model = r'
module main
import os
#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
struct C.pthread_mutex_t {}
fn C.pthread_mutex_init(&C.pthread_mutex_t, voidptr) i32
fn C.pthread_mutex_lock(&C.pthread_mutex_t) i32
fn C.pthread_mutex_unlock(&C.pthread_mutex_t) i32
fn C.snprintf(&char, usize, &char, ...voidptr) i32
fn C.alloca(usize) voidptr
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.abort()
type WsEglGetDisplay = fn (voidptr) voidptr
struct State { mut: root &char }
__global ws State
__global ws_egl_error_key u32
__global ws_egl_binding_key u32
__global ws_egl_provider voidptr
__global ws_egl_mutex C.pthread_mutex_t
__global ws_egl_loader_mutex C.pthread_mutex_t
__global ws_egl_prepared bool
__global counts_mutex C.pthread_mutex_t
__global opens int
__global lookups int
__global keys int
__global fail_provider bool
__global fail_symbol bool
fn ws_egl_binding_release(pointer voidptr) {}
fn ws_egl_error(code i32) { assert code == 0x300c }
fn probe_pthread_key_create(pointer &u32, release voidptr) i32 {
 keys++; unsafe { *pointer = u32(keys) }; return 0
}
fn probe_dlopen(path &char, flags i32) voidptr {
 assert flags == 2 || flags == 258
 opens++
 text := unsafe { cstring_to_vstring(path) }
 assert text.starts_with("/runtime/usr/lib/art/native-ws/") && text.ends_with(".so")
 if flags == 2 { return if fail_provider { unsafe { nil } } else { voidptr(99) } }
 return voidptr(98)
}
fn probe_setenv(name &char, value &char, overwrite i32) i32 { assert overwrite == 1; return 0 }
fn probe_dlerror() &char { return c"test provider unavailable" }
fn probe_dlsym(provider voidptr, name &char) voidptr {
 // A nil handle would re-enter the adapter rather than query Mesa.
 assert provider == voidptr(99), "lookup recursed through the global namespace"
 assert unsafe { cstring_to_vstring(name) } == "eglGetDisplay"
 C.pthread_mutex_lock(&counts_mutex); lookups++; C.pthread_mutex_unlock(&counts_mutex)
 return if fail_symbol { unsafe { nil } } else { voidptr(display) }
}
fn display(native_display voidptr) voidptr { assert native_display == unsafe { nil }; return voidptr(77) }
fn repeated() {
 for _ in 0 .. 100 { assert ws_egl_display(unsafe { nil }) == voidptr(77) }
}
'
const cases = r'
fn main() {
 ws.root = c"/runtime"
 assert C.pthread_mutex_init(&counts_mutex, unsafe { nil }) == 0
 assert ws_egl_prepare()
 assert opens == 0 && lookups == 0 && keys == 2 && ws_egl_provider == unsafe { nil }
 if os.args.len == 2 {
  fail_provider = os.args[1] == "--missing-provider"
  fail_symbol = os.args[1] == "--missing-symbol"
  ws_egl_display(unsafe { nil })
  panic("failed provider lookup returned")
 }
 assert ws_egl_display(voidptr(1)) == unsafe { nil }
 assert opens == 0
 assert ws_egl_display(unsafe { nil }) == voidptr(77)
 assert opens == 3 && lookups == 1 && keys == 2
 error_key := ws_egl_error_key
 binding_key := ws_egl_binding_key
 assert ws_egl_init(ws.root)
 assert opens == 3 && keys == 2
 mut threads := []thread{}
 for _ in 0 .. 8 { threads << spawn repeated() }
 threads.wait()
 assert opens == 3 && lookups == 801 && keys == 2
 assert ws_egl_init(ws.root)
 assert ws_egl_error_key == error_key && ws_egl_binding_key == binding_key
 assert opens == 3 && keys == 2
 println("HEADLESS-EGL-PROVIDER-PASS")
}
'
