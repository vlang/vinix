// SPDX-License-Identifier: GPL-2.0-or-later
// Native CF input oracle, including endian marks and malformed code units.
module main

import os

#flag -framework CoreFoundation
#include <CoreFoundation/CFString.h>
#include <dlfcn.h>
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFStringGetLength(voidptr) i64
fn C.CFRelease(voidptr)
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
struct InputRange { location i64 length i64 }
type InputOutput = fn (u64, InputRange, u32, u8, bool, u64, i64, &i64) i64

fn main() {
	if os.args.len != 2 { panic('usage: inspect-cf-string-input EXTERNAL_OUT') }
	root := os.real_path(os.getwd())
	out := os.real_path(os.args[1])
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { panic('output must be external') }
	lib := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
	call := unsafe { InputOutput(C.dlsym(lib, c'CFStringGetBytes')) }
	cases := [
		[]u8{}, [u8(0x41)], [u8(0x41), 0], [u8(0), 0x41],
		[u8(0xff), 0xfe, 0x41, 0], [u8(0xfe), 0xff, 0, 0x41],
		[u8(0xff), 0xfe, 0xff, 0xfe], [u8(0xfe), 0xff, 0xfe, 0xff],
		[u8(0x41), 0, 0, 0, 0xc0, 3, 0x3c, 0xd8, 0xae, 0xdf, 0x5a, 0],
		[u8(0x3c), 0xd8], [u8(0xae), 0xdf], [u8(0x3c), 0xd8, 0x41, 0],
		[u8(0x41), 0, 0x3c], [u8(0x41), 0, 0, 0],
		[u8(0xff), 0xfe, 0, 0, 0x41, 0, 0, 0], [u8(0), 0, 0xfe, 0xff, 0, 0, 0, 0x41],
		[u8(0), 0xd8, 0, 0], [u8(0), 0, 0x11, 0], [u8(0xae), 0xf3, 1, 0],
		[u8(0xef), 0xbb, 0xbf, 0x41], [u8(0xff), 0xfe, 0x80, 0],
	]
	mut lines := []string{}
	for encoding in [u32(0x100), 0x14000100, 0x10000100, 0xc000100, 0x1c000100, 0x18000100, 0x08000100, 0x600, 0x201, 0] {
	for external in [false, true] {
	for bytes in cases {
		object := C.CFStringCreateWithBytes(unsafe { nil }, bytes.data, bytes.len, encoding, external)
		if object == unsafe { nil } {
			lines << 'CF-INPUT: encoding=0x${encoding.hex()} external=${external} bytes=${bytes.hex()} null=true'
			continue
		}
		length := C.CFStringGetLength(object)
		mut buffer := [128]u8{}
		mut used := i64(-1)
		converted := call(u64(object), InputRange{0, length}, 0x14000100, 0, false, u64(unsafe { &buffer[0] }), buffer.len, &used)
		lines << 'CF-INPUT: encoding=0x${encoding.hex()} external=${external} bytes=${bytes.hex()} null=false length=${length} converted=${converted} utf16le=${buffer[..int(used)].hex()}'
		C.CFRelease(object)
	} } }
	os.write_file(out + '/native-input.txt', lines.join('\n') + '\n')!
	println('native CFString input cases: ${lines.len}')
}
