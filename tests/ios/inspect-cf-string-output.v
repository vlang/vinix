// SPDX-License-Identifier: GPL-2.0-or-later
// Record native CFStringGetBytes semantics, including split surrogate ranges.
module main

import os

#flag -framework CoreFoundation
#include <CoreFoundation/CFString.h>
#include <dlfcn.h>
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFRelease(voidptr)
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
struct OutputRange { location i64 length i64 }
type OutputCall = fn (u64, OutputRange, u32, u8, bool, u64, i64, &i64) i64

fn main() {
	if os.args.len !in [2, 3] { panic('usage: inspect-cf-string-output EXTERNAL_OUT [APPLICATION]') }
	root := os.real_path(os.getwd())
	out := os.real_path(os.args[1])
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { panic('output must be external') }
	lib := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
	call := unsafe { OutputCall(C.dlsym(lib, c'CFStringGetBytes')) }
	mut lines := []string{}
	for text in ['', 'AZ', 'A\x00π🎮Z'] {
		object := C.CFStringCreateWithBytes(unsafe { nil }, text.str, text.len, 0x08000100, false)
		length := if text == '' { 0 } else if text == 'AZ' { 2 } else { 6 }
		for encoding in [u32(0x100), 0x14000100, 0x10000100, 0x08000100, 0x600] {
		for external in [false, true] {
		for range in [OutputRange{0, length}, OutputRange{3, 1}, OutputRange{4, 1}, OutputRange{3, 2}, OutputRange{0, 0}] {
			if range.location + range.length > length { continue }
		for capacity in [i64(0), 1, 2, 3, 4, 5, 7, 16] {
		for query in [false, true] {
			mut buffer := [u8(0xa5)].repeat(32)
			mut used := i64(-1)
			converted := call(u64(object), range, encoding, 63, external,
				if query { u64(0) } else { u64(buffer.data) }, capacity, &used)
			lines << 'CF-OUTPUT: text=${text.bytes().hex()} encoding=0x${encoding.hex()} external=${external} range=${range.location},${range.length} capacity=${capacity} query=${query} converted=${converted} used=${used} bytes=${buffer.hex()}'
			unsafe { buffer.free() }
		} } } } }
		C.CFRelease(object)
	}
	os.write_file(out + '/native-output.txt', lines.join('\n') + '\n')!
	println('native CFString output cases: ${lines.len}')
	if os.args.len == 3 {
		args := ['/opt/homebrew/opt/llvm/bin/llvm-objdump', '--disassemble', '--no-show-raw-insn',
			'--start-address=0x1005cf690', '--stop-address=0x1005cf6b0', os.real_path(os.args[2])]
		result := os.exec(args)
		if result.exit_code != 0 { panic(result.output) }
		os.write_file(out + '/cf-string-arguments.txt', 'COMMAND: ' + args.map(os.quoted_path(it)).join(' ') + '\n' + result.output)!
	}
}
