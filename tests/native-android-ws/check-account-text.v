// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the production JNI Unicode adapter with a strict string model.
module main

import os

fn main() {
	assert os.args.len == 2, 'usage: check-account-text OUTPUT_DIR'
	work := os.abs_path(os.args[1])
	assert !os.exists(work)
	os.mkdir_all(work)!
	source := os.read_file('build-support/android/nativews/account_text.v')!
	code := source.all_after('module atlframework')
	os.write_file(work + '/main.v', model + code + cases)!
	compiler := os.getenv_opt('VINIX_V_COMPILER') or { 'v' }
	r := os.exec([compiler, '-w', '-n', '-enable-globals', '-cc', 'cc', 'run', work + '/main.v'])
	os.write_file(work + '/run.log', r.output)!
	if r.exit_code != 0 { panic(r.output) }
	assert r.output.trim_space() == 'ACCOUNT-TEXT-PASS Unicode boundaries invalid-input JNI-release'
	println(r.output.trim_space())
}

const model = '
module main
import encoding.hex
#include <stdlib.h>
#include <string.h>
fn C.malloc(u64) voidptr
fn C.alloca(u64) voidptr
fn C.free(voidptr)
fn C.strlen(&char) u64
type WsLength = fn (voidptr, voidptr) i32
type WsChars = fn (voidptr, voidptr, voidptr) &u16
type WsCharsRelease = fn (voidptr, voidptr, &u16)
type WsNewString = fn (voidptr, &u16, i32) voidptr
__global units = []u16{}
__global result_units = []u16{}
__global acquired int
__global released int
__global exception bool
fn pending(e voidptr) bool { assert e == voidptr(1); return exception }
fn length(e voidptr, value voidptr) i32 { assert !exception; assert e == voidptr(1) && value == voidptr(2); return i32(units.len) }
fn chars(e voidptr, value voidptr, copy voidptr) &u16 { assert e == voidptr(1) && value == voidptr(2); acquired++; return unsafe { units.data } }
fn release_chars(e voidptr, value voidptr, data &u16) { assert e == voidptr(1) && value == voidptr(2) && data == unsafe { units.data }; released++ }
fn new_string(e voidptr, data &u16, n i32) voidptr { assert !exception; assert e == voidptr(1); result_units = []u16{}; for i in 0 .. n { result_units << unsafe { data[i] } }; return voidptr(3) }
fn slot(e voidptr, index int) voidptr {
 assert e == voidptr(1)
 return match index { 163 { voidptr(new_string) } 164 { voidptr(length) } 165 { voidptr(chars) } 166 { voidptr(release_chars) } else { panic("unexpected JNI slot") } }
}
'

const cases = '
fn main() {
 unsafe {
  e := voidptr(1)
  assert ws_account_utf8(e, nil) == nil
  assert ws_account_java_text(e, nil) == nil
  inputs := [[u16(0)], [u16(65), 83, 67, 73, 73], [u16(0x4e2d), 0x6587], [u16(0xe9)], [u16(0xd83d), 0xde00], [u16(97), 0xd83d, 0xde00, 0xe9], [u16(0xdbff), 0xdfff]]
  for index, item in ["", "ASCII", "中文", "é", "😀", "a😀é", "\U0010ffff"] {
   units = inputs[index].clone(); if index == 0 { units = units[..0] }
   text := ws_account_utf8(e, voidptr(2))
   assert text != nil && cstring_to_vstring(text) == item
   assert ws_account_java_text(e, text) == voidptr(3)
   assert result_units == units
   C.free(text)
  }
  for bad in [[u16(0)], [u16(0xd800)], [u16(0xdc00)], [u16(0xd800), 65], [u16(0xdbff), 0xd800]] {
   units = bad.clone(); assert ws_account_utf8(e, voidptr(2)) == nil
  }
  units = []u16{len: 4097, init: 65}; assert ws_account_utf8(e, voidptr(2)) == nil
  units = []u16{len: 4096, init: 65}
  text := ws_account_utf8(e, voidptr(2)); assert text != nil && C.strlen(text) == 4096; C.free(text)
  units = []u16{len: 2049, init: 0x80}; assert ws_account_utf8(e, voidptr(2)) == nil
  for bad in ["c080", "80", "e08080", "eda080", "f4908080", "f09f98", "c2", "f5808080"] {
   bytes := hex.decode(bad) or { panic(err) }; assert ws_account_java_text(e, bytes.bytestr().str) == nil
  }
  assert ws_account_java_text(e, "a".repeat(4097).str) == nil
  exception = true
  assert ws_account_utf8(e, voidptr(2)) == nil
  assert ws_account_java_text(e, "valid".str) == nil
  assert acquired == released
  println("ACCOUNT-TEXT-PASS Unicode boundaries invalid-input JNI-release")
 }
}
'
