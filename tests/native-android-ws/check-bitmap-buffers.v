// SPDX-License-Identifier: GPL-2.0-or-later
// Run production transfer code against controlled JNI storage, including canaries.
module main
import os
import crypto.sha256
fn main() {
 if os.args.len != 2 { panic('usage: check-bitmap-buffers FRESH_EXTERNAL_OUTPUT') }
 root := os.abs_path(os.args[1])
 if os.exists(root) || root.starts_with(os.real_path(os.getwd()) + '/') { panic('fresh external output required') }
 os.mkdir_all(root)!
 source := os.read_file('build-support/android/nativews/bitmap_buffers.v')!
 code := source.all_after('module atlframework')
 os.write_file(root + '/source.v.input', source)!
 variants := [code, code.replace('size > (i64(remaining) << shift)', 'false'),
 code.replace('if read_only {', 'if false {'),
 code.replace('i64(offset) + size > (i64(count) << array_shift)', 'false'),
 code.replace(' + (i64(position) << shift)', ''),
 code.replace('WsBitmapBufferRelease(slot(e, 223))(e, array, pinned, 0)', '')]
 for index, variant in variants {
  dir := root + '/case-' + index.str()
  os.mkdir(dir)!
  // Keep fixture globals distinct from production locals.
  mut fixture := model + cases
  for name in ['kind', 'direct', 'offset', 'count'] {
   fixture = fixture.replace(name, 'probe_' + name)
  }
  os.write_file(dir + '/main.v', fixture.all_before('fn main()') + variant + 'fn main()' + fixture.all_after('fn main()'))!
  build := os.exec(['/Users/alex/code/v/v', '-new-compiler', '-no-parallel', '-nocache', '-gc', 'boehm', '-enable-globals', '-cc', 'cc', '-o', dir + '/probe', dir + '/main.v'])
  os.write_file(dir + '/build.log', build.output)!
  assert build.exit_code == 0, build.output
  run := os.exec([dir + '/probe'])
  os.write_file(dir + '/run.log', run.output)!
  if index == 0 { assert run.exit_code == 0, run.output }
  else { assert run.exit_code != 0 && run.output.contains('assert'), 'mutation survived ${index}' }
 }
 os.write_file(root + '/inputs.sha256', sha256.hexhash(source) + ' bitmap_buffers.v\n' + sha256.sum(os.read_bytes('/Users/alex/code/v/v')!).hex() + ' compiler\n')!
 println('BITMAP-BUFFER-CHECK-PASS direct heap typed views padding canaries exceptions cleanup five-mutations')
}
const model = r'
module main
#include <string.h>
#include <stdlib.h>
fn C.alloca(usize) voidptr
struct WsBitmap { mut: width i32 height i32 row_bytes i32 references i32 alpha_only bool rgba &u8 }
struct Value { l voidptr }
type Member = fn (voidptr, voidptr, &char, &char) voidptr
type IntCall = fn (voidptr, voidptr, voidptr, &Value) i32
type Drop = fn (voidptr, voidptr)
type ExceptionThrow = fn (voidptr, voidptr) i32
__global problem string
__global kind int
__global backing int
__global pos i32
__global remain i32
__global cap i32
__global offset i32
__global count i32
__global direct bool
__global readonly bool
__global pin_fail bool
__global no_array bool
__global view bool
__global view_start i32
__global base_size i32
__global base_start i32
__global pins int
__global releases int
__global refs int
__global held bool
__global storage [80]u8
fn slot(e voidptr, index i32) voidptr {
 assert !held || index == 223
 return match index { 32 { voidptr(instance) } 23 { voidptr(drop_ref) } 13 { voidptr(raise_object) }
  230 { voidptr(address) } 231 { voidptr(direct_capacity) } 113 { voidptr(member) }
  131 { voidptr(base_offset) } 222 { voidptr(pin) } 223 { voidptr(release) } else { panic(index) } }
}
fn pending(e voidptr) bool { assert !held; return problem != "" }
fn cls(e voidptr, name &char) voidptr {
 assert !held
 text := unsafe { cstring_to_vstring(name) }
 refs++
 return match text { "java/nio/ByteBuffer" { voidptr(10) } "java/nio/ShortBuffer" { voidptr(11) }
 "java/nio/IntBuffer" { voidptr(12) } "[B" { voidptr(20) } "[S" { voidptr(21) } "[I" { voidptr(22) }
 "java/nio/NIOAccess" { voidptr(30) }
 "java/nio/ByteBufferAsShortBuffer" { voidptr(51) }
 "java/nio/ByteBufferAsIntBuffer" { voidptr(52) } else { panic(text) } }
}
fn instance(e voidptr, object voidptr, klass voidptr) u8 {
 assert !held
 return u8(if object == voidptr(1) { klass == voidptr(10 + kind) || (view && klass == voidptr(50 + kind)) } else { klass == voidptr(20 + backing) })
}
fn drop_ref(e voidptr, object voidptr) { assert !held; refs--; assert refs >= 0 }
fn raise_object(e voidptr, object voidptr) i32 { problem = "java/nio/ReadOnlyBufferException"; return 0 }
fn throw(e voidptr, name &char, message &char) { assert !held; assert problem == ""; problem = unsafe { cstring_to_vstring(name).clone() } }
fn integer(e voidptr, receiver voidptr, cl &char, name &char, sig &char, args &Value) i32 {
 assert !held
 if receiver == voidptr(4) {
  return match unsafe { cstring_to_vstring(name) } { "capacity" { base_size } "arrayOffset" { base_start } else { panic("base integer") } }
 }
 return match unsafe { cstring_to_vstring(name) } { "position" { pos } "remaining" { remain } "capacity" { cap } else { panic("integer") } }
}
fn boolean(e voidptr, receiver voidptr, cl &char, name &char, sig &char, args &Value) u8 { assert !held; return u8(readonly) }
fn new_object(e voidptr, cl &char, sig &char, args &Value) voidptr { assert !held; refs++; return voidptr(40) }
fn address(e voidptr, object voidptr) voidptr { assert !held; return if direct { unsafe { &storage[0] } } else { unsafe { nil } } }
fn direct_capacity(e voidptr, object voidptr) i64 { assert !held; return cap }
fn static_obj(e voidptr, cl &char, name &char, sig &char, args &Value) voidptr {
 assert !held
 if no_array || (view && args.l == voidptr(1)) { return unsafe { nil } }
 refs++; return voidptr(2)
}
fn get_object(e voidptr, receiver voidptr, cl &char, name &char, sig &char) voidptr { assert !held; refs++; return voidptr(4) }
fn get_int(e voidptr, receiver voidptr, cl &char, name &char) i32 { assert !held; return view_start }
fn member(e voidptr, cl voidptr, name &char, sig &char) voidptr { assert !held; return voidptr(3) }
fn base_offset(e voidptr, cl voidptr, method voidptr, args &Value) i32 { assert !held; return offset }
fn ws_array_len(e voidptr, array voidptr) i32 { assert !held; return count }
fn pin(e voidptr, array voidptr, copy voidptr) voidptr { assert !held; pins++; if pin_fail { return unsafe { nil } }; held = true; return unsafe { &storage[0] } }
fn release(e voidptr, array voidptr, data voidptr, mode i32) { assert held && mode == 0; held = false; releases++ }
fn reset() {
 problem = ""; kind = 0; backing = 0; pos = 3; remain = 40; cap = 60; offset = 7; count = 64
 direct = false; readonly = false; pin_fail = false; no_array = false; pins = 0; releases = 0; refs = 0; held = false
 view = false; view_start = 4; base_size = 64; base_start = 5
 for i in 0 .. 80 { storage[i] = 0x55 }
}
'
const cases = r'
fn main() {
 mut pixels := [u8(1), 2, 3, 4, 5, 6, 7, 8]!
 mut bitmap := WsBitmap{width: 2, height: 1, row_bytes: 8, rgba: unsafe { &pixels[0] }}
 for type_id in 0 .. 3 {
  for is_direct in [false, true] {
   for array_type in 0 .. 3 {
    reset(); kind = type_id; backing = array_type; direct = is_direct
    ws_bitmap_copy_to_buffer(unsafe { nil }, i64(voidptr(&bitmap)), voidptr(1), 5, 8)
    assert problem == "" && refs == 0 && !held
    start := if is_direct { int(pos) << type_id } else { int(offset) }
    for i in 0 .. 80 { assert storage[i] == if i >= start && i < start + 8 { pixels[i - start] } else { u8(0x55) } }
    assert pos == 3 && pins == if is_direct { 0 } else { 1 }
    assert releases == pins
   }
  }
 }
 for type_id in 1 .. 3 {
  reset(); kind = type_id; view = true
  ws_bitmap_copy_to_buffer(unsafe { nil }, i64(voidptr(&bitmap)), voidptr(1), 5, 8)
  start := 9 + (3 << type_id)
  assert problem == "" && refs == 0 && releases == 1 && pins == 1
  for i in 0 .. 80 { assert storage[i] == if i >= start && i < start + 8 { pixels[i - start] } else { u8(0x55) } }
  for failure in 0 .. 4 {
   reset(); kind = type_id; view = true
   match failure { 0 { view_start = -1 } 1 { base_size = 5 } 2 { base_start = -1 } else { count = 5 } }
   ws_bitmap_copy_to_buffer(unsafe { nil }, i64(voidptr(&bitmap)), voidptr(1), 5, 8)
   assert problem != "" && refs == 0 && releases == 0 && pins == 0
  }
 }
 // ALPHA_8 rows include four-byte alignment padding and are copied as-is.
 reset(); bitmap.width = 3; bitmap.height = 2; bitmap.row_bytes = 4; bitmap.alpha_only = true
 ws_bitmap_copy_to_buffer(unsafe { nil }, i64(voidptr(&bitmap)), voidptr(1), 24, 4)
 assert problem == "" && storage[7..15] == pixels[..] && refs == 0 && releases == 1
 bitmap.width = 2; bitmap.height = 1; bitmap.row_bytes = 8; bitmap.alpha_only = false
 for failure in 0 .. 13 {
  reset()
  match failure { 0 { remain = 7 } 1 { readonly = true } 2 { offset = 60 } 3 { offset = -1 }
   4 { kind = 3 } 5 { backing = 3 } 6 { pin_fail = true } 7 { no_array = true }
   8 { pos = -1 } 9 { cap = 2 } 10 { remain = -1 } 11 { count = -1 } else { problem = "existing" } }
  ws_bitmap_copy_to_buffer(unsafe { nil }, i64(voidptr(&bitmap)), voidptr(1), 5, 8)
  assert problem != "" && refs == 0 && !held && releases == 0
  for value in storage { assert value == 0x55 }
 }
 for failure in 0 .. 4 {
  reset()
  ws_bitmap_copy_to_buffer(unsafe { nil }, if failure == 0 { i64(0) } else { i64(voidptr(&bitmap)) },
   if failure == 1 { unsafe { nil } } else { voidptr(1) }, if failure == 2 { 24 } else { 5 }, if failure == 3 { 4 } else { 8 })
  assert problem != "" && refs == 0 && pins == 0
 }
 // An aliased direct destination exercises memmove rather than memcpy.
 reset(); direct = true; pos = 1; bitmap.rgba = unsafe { &storage[0] }
 for i in 0 .. 8 { storage[i] = u8(i) }
 ws_bitmap_copy_to_buffer(unsafe { nil }, i64(voidptr(&bitmap)), voidptr(1), 5, 8)
 assert problem == "" && storage[1..9] == [u8(0), 1, 2, 3, 4, 5, 6, 7]
 println("BITMAP-BUFFER-PASS")
}
'
