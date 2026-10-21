// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.pipe(&i32) i32
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
type EscapingEntry = fn (u64, u64, i32, i32, i32, u32) bool
type EscapingProbe = fn (u64, u64, i32, i32, i32, u32, u64, &u64)

fn escaping_call(entry u64, probe EscapingProbe, object u64, filename u64, length i32, line i32, column i32, verification u32, expected bool) string {
	mut pipe := [i32(0), 0]!
	assert C.pipe(&pipe[0]) == 0
	saved := C.dup(2); assert saved >= 0 && C.dup2(pipe[1], 2) == 2
	mut result := [u64(0x1234), 0, 0, 0, 0x5678]!
	probe(object, filename, length, line, column, verification, entry, unsafe { &result[1] })
	assert C.dup2(saved, 2) == 2
	assert C.close(saved) == 0 && C.close(pipe[1]) == 0
	assert result == [u64(0x1234), u64(expected), 0x5020, 0x5021, 0x5678]!
	mut output := ''
	mut buffer := [u8(0)].repeat(4096)
	for {
		count := C.read(pipe[0], buffer.data, buffer.len)
		assert count >= 0
		if count == 0 { break }
		output += unsafe { buffer[..int(count)].bytestr() }
	}
	assert C.close(pipe[0]) == 0
	return output
}

fn escaping_cases(entry u64, probe EscapingProbe, native bool) {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 4, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert base != u64(-1)
	assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_NONE) == 0
	assert C.mprotect(voidptr(base + u64(page) * 3), page, C.PROT_NONE) == 0
	header := base + u64(page) - 16
	filename := base + u64(page) * 3 - 3
	protected := base + u64(page)
	for i, byte in [u8(`a`), `b`, `c`]! { unsafe { *(&u8(filename + u64(i))) = byte } }
	unsafe { *(&u64(header)) = protected } // The metadata must never be read.
	assert escaping_call(entry, probe, 0, protected, -1, -1, -1, 0, false) == ''
	for bits in [u64(0), 3, 5, 6, 0xfffffffe]! {
		unsafe { *(&u64(header + 8)) = bits }
		assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0
		assert escaping_call(entry, probe, header, protected, -1, -1, -1, 1, false) == ''
		assert read64(header) == protected && read64(header + 8) == bits
		assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	for bits in [u64(3) | (u64(1) << 33), u64(5) | (u64(20) << 33), u64(0x80000004ffffffff)]! {
		unsafe { *(&u64(header + 8)) = bits }
		assert C.mprotect(voidptr(base), page, C.PROT_READ) == 0
		for verification in [u32(0), 1]! {
			message := if verification == 0 { 'closure argument was escaped in withoutActuallyEscaping block' } else { 'closure argument passed as @noescape to Objective-C has escaped' }
			for line in [i32(0), 187, -1]! {
				output := escaping_call(entry, probe, header, filename, 3, line, 16, verification, true)
				expected := '${message}: file abc, line ${u32(line)}, column 16 \n'
				assert output.contains(expected), output
				if !native { assert output == expected }
			}
			output := escaping_call(entry, probe, header, protected, 0, 98, -1, verification, true)
			assert output.contains('${message}: file , line 98, column 4294967295 \n'), output
		}
		assert read64(header) == protected && read64(header + 8) == bits
		assert C.mprotect(voidptr(base), page, C.PROT_READ | C.PROT_WRITE) == 0
	}
	unsafe { *(&u8(filename + 1)) = 0 }
	output := escaping_call(entry, probe, header, filename, 3, 187, 16, 1, true)
	assert output.contains(': file a, line 187, column 16 \n'), output
	assert C.munmap(voidptr(base), page * 4) == 0
}

fn escaping_worker(entry u64) {
	query := unsafe { EscapingEntry(voidptr(entry)) }
	mut header := [u64(0), 5]!
	for _ in 0 .. 1000 {
		assert !query(u64(unsafe { &header[0] }), 0, -1, 187, 16, 1)
		assert header == [u64(0), 5]!
	}
}

fn escaping_suite(probe EscapingProbe) {
	entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_isEscapingClosureAtFileLocation') or { panic(err) }
	before := ios_runtime.swift_heap_sequence
	escaping_cases(entry, probe, false)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn escaping_worker(entry) }; workers.wait()
	assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_heap_sequence == before && ios_runtime.live == 0
	for invalid in [u64(1), 7, ~u64(0) - 7, ~u64(0) - 15]! {
		if _ := swift_escaping_closure_checked(invalid, 0, 0, 0, 0, 1) { assert false }
	}
	if _ := swift_escaping_closure_checked(0, 0, 0, 0, 0, 2) { assert false }
	mut header := [u64(0), 0]!
	for bits in [u64(1) << 63, (u64(1) << 63) | 3, (u64(1) << 32) | 3]! {
		header[1] = bits
		if _ := swift_escaping_closure_checked(u64(unsafe { &header[0] }), 0, 0, 0, 0, 1) { assert false }
		assert header[1] == bits
	}
	header[1] = 3 | (u64(1) << 33)
	for pair in [[u64(0), 1]!, [u64(1), u64(0xffffffff)]!, [~u64(0) - 1, 3]!]! {
		if _ := swift_escaping_closure_checked(u64(unsafe { &header[0] }), pair[0], i32(pair[1]), 0, 0, 1) { assert false }
	}
	if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_isEscapingClosureAtFileLocation') { assert false }
	if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_isEscapingClosureAtFileLocation') { assert false }
}

fn test_swift_escaping_closure() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != u64(-1)
	for i, word in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0703f3, 0xaa0603f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), word) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 56)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { EscapingProbe(voidptr(code)) }
	$if macos {
		lib := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); assert lib != unsafe { nil }
		entry := u64(C.dlsym(lib, c'swift_isEscapingClosureAtFileLocation')); assert entry != 0
		escaping_cases(entry, probe, true)
		println('NATIVE-ESCAPING-CLOSURE: six-argument bool ABI with x20/x21 preserved, nil/stack/heap inline uniqueness ignores unowned references, nonunique and immortal diagnostics return true, both verification messages, bounded/NUL filename, unsigned line/column, protected metadata and read-only page-end header')
	}
	escaping_cases(u64(unsafe { voidptr(swift_escaping_closure) }), probe, false)
	for _ in 0 .. 2 { objc_start(); escaping_suite(probe); objc_stop(); assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arc_code == 0 }
	escaping_cases(u64(unsafe { voidptr(swift_escaping_closure) }), probe, false)
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-ESCAPING-CLOSURE: Core-only read-only nil/stack/heap/immortal closure query and diagnostics, exact six-argument bool ABI, guarded readable headers and bounded filenames, x20/x21 preserved, eight private stack workers, no allocation/registry/ARC/destruction, malformed arguments/side-table/deinitializing headers rejected, runtime-independent calls and two empty runtime lifetimes')
}
