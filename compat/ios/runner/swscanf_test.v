// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.hex

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type WideScanCall = fn (voidptr, voidptr, voidptr) i32
type WideScanProbe = fn (u64, voidptr, voidptr, voidptr) i32
struct WideScanCase {
	input string
	format string
	count i32
	outputs []string
}
fn wide_scan_test_text(text string) []i32 {
	mut result := []i32{}
	for value in text.runes() { result << i32(value) }
	result << 0
	return result
}
fn wide_scan_test_cases(call WideScanCall, entry u64, probe WideScanProbe) {
	// These formats are from the actual IPA's fifteen swscanf consumers.
	for item in [
		WideScanCase{'A B iPhone OS 17.6.1 (21f90d)', '%*s %*s iPhone OS %hd.%hd.%hd (%hxd)', 4, ['1100','0600','0100','0df9']},
		WideScanCase{'A B iPhone OS 17.6 (21f90d)', '%*s %*s iPhone OS %*hd.%*hd (%hxd)', 1, ['0df9']},
		WideScanCase{'A B [123]', '%*s %*s [%u]', 1, ['7b000000']},
		WideScanCase{'A B C (name)', '%*s %*s %*s (%256ls)', 1, ['6e000000610000006d000000650000002900000000000000']},
		WideScanCase{'A B name', '%*s %*s %256ls', 1, ['6e000000610000006d0000006500000000000000']},
		WideScanCase{'123456789 lib abc name', '%lx %*ls %lx %256ls', 3, ['8967452301000000','bc0a000000000000','6e000000610000006d0000006500000000000000']},
		WideScanCase{'3.14.15', '%hu.%hu.%hu', 3, ['0300','0e00','0f00']},
		WideScanCase{'lib 3.14.15', '%*ls %d.%d.%d', 3, ['03000000','0e000000','0f000000']},
		WideScanCase{'1 lib 0x123456789', '%*d %256ls 0x%lx', 2, ['6c000000690000006200000000000000','8967452301000000']},
		WideScanCase{'1 lib 0x123 0x456 + 7', '%*d %*ls 0x%*lx 0x%lx + %d', 2, ['5604000000000000','07000000']},
		WideScanCase{'1 lib 0x123 name + 7 (file:8)', '%*d %*ls 0x%*lx %1024ls + %*d (%256ls:%d)', 2, ['6e000000610000006d0000006500000000000000','66000000690000006c000000650000003a000000380000002900000000000000']},
		WideScanCase{'4294967295', '%u', 1, ['ffffffff']},
		WideScanCase{'A B -17', '%*ls %*ls %d', 1, ['efffffff']},
		WideScanCase{'A 1.2.3 (4.5.6-7+branch)', '%*s %d.%d.%d (%*d.%*d.%*d-%d+%256ls)', 5, ['01000000','02000000','03000000','07000000','6200000072000000610000006e00000063000000680000002900000000000000']},
		WideScanCase{'A B 42', '%*s %*s %u', 1, ['2a000000']},
		WideScanCase{'1 2 3', '%llu %llu %256ls', 3, ['0100000000000000','0200000000000000','3300000000000000']},
		WideScanCase{'', '%d', -1, []string{}},
		WideScanCase{'z', '%d', 0, []string{}},
		WideScanCase{' 	', '%n%d', -1, ['00000000']},
		WideScanCase{'12 z', '%d %u', 1, ['0c000000']},
		WideScanCase{'100% 42', '%*d%% %d%n', 1, ['2a000000','07000000']},
		WideScanCase{'-128 255 -7 ff', '%hhd %hhu %hd %hx', 4, ['80','ff','f9ff','ff00']},
		WideScanCase{'-42 077 0xff 12', '%i %i %i %zu', 4, ['d6ffffff','3f000000','ff000000','0c00000000000000']},
		WideScanCase{'1.25 2.5 3.75', '%f %lf %Lf', 3, ['0000a03f','0000000000000440','0000000000000e40']},
		WideScanCase{'0x1.8p+1 -2 3e2', '%la %lg %le', 3, ['0000000000000840','00000000000000c0','0000000000c07240']},
		WideScanCase{'abc xyz', '%s %ls', 2, ['61626300','78000000790000007a00000000000000']},
		WideScanCase{'abc xyz', '%S %C', 2, ['61000000620000006300000000000000','78000000']},
		WideScanCase{'abc xyz', '%hs %hc', 2, ['61626300','78']},
		WideScanCase{'abc 1.5 xyz', '%hs %Lf %hc', 3, ['61626300','000000000000f83f','78']},
		WideScanCase{'abcdef', '%3c%2lc%n', 2, ['616263','6400000065000000','05000000']},
		WideScanCase{'abc1', '%3[abc]%n', 1, ['61626300','03000000']},
		WideScanCase{'abc1', '%3l[^1]%n', 1, ['61000000620000006300000000000000','03000000']},
		WideScanCase{'42 3.5 tail', '%2$d %1$lf %3$s', 3, ['0000000000000c40','2a000000','7461696c00']},
		WideScanCase{'1234', '%2d%hn%hhn%ln', 1, ['0c000000','0200','02','0200000000000000']},
		WideScanCase{'L 1.5', 'L %Lf', 1, ['000000000000f83f']},
	] {
		input := wide_scan_test_text(item.input)
		format := wide_scan_test_text(item.format)
		for variadic in [false, true]! {
			buffer := C.malloc(32768)
			assert buffer != unsafe { nil }
			defer { C.free(buffer) }
			C.memset(buffer, 0xcc, 32768)
			mut expected := []u8{len: 32768, init: 0xcc}
			mut arguments := [8]u64{}
			for i in 0 .. 8 { arguments[i] = u64(buffer) + 16 + u64(i * 4096) }
			for i, output in item.outputs {
				bytes := hex.decode(output) or { panic(err) }
				for j, value in bytes { expected[16 + i * 4096 + j] = value }
			}
			darwin_set_errno(83)
			result := if variadic { probe(entry, input.data, format.data, unsafe { &arguments[0] }) }
				else { call(input.data, format.data, unsafe { &arguments[0] }) }
			error_code := unsafe { *C.ios_errno_address() }
			comparison := C.memcmp(buffer, expected.data, 32768)
			assert result == item.count, item.format
			assert error_code == 83, item.format
			assert comparison == 0, item.format
			assert input == wide_scan_test_text(item.input) && format == wide_scan_test_text(item.format)
		}
	}
}

fn wide_scan_test_encoding(call WideScanCall, utf8 bool) {
	input := wide_scan_test_text('42 é😀x')
	format := wide_scan_test_text('%d %s%n')
	mut number := i32(0)
	mut consumed := i32(-1)
	mut bytes := [16]u8{init: 0xcc}
	args := [u64(unsafe { &number }), u64(unsafe { &bytes[4] }), u64(unsafe { &consumed })]!
	darwin_set_errno(83)
	result := call(input.data, format.data, unsafe { &args[0] })
	if utf8 {
		assert number == 42 && result == 2 && consumed == 6 && unsafe { *C.ios_errno_address() } == 83
		assert bytes == [u8(0xcc),0xcc,0xcc,0xcc,0xc3,0xa9,0xf0,0x9f,0x98,0x80,0x78,0,0xcc,0xcc,0xcc,0xcc]!
		wide := wide_scan_test_text('é😀x')
		wide_format := wide_scan_test_text('%2ls%n')
		mut output := [4]u32{init: 0xcccccccc}
		wide_args := [u64(unsafe { &output[0] }), u64(unsafe { &consumed })]!
		assert call(wide.data, wide_format.data, unsafe { &wide_args[0] }) == 1
		assert output == [u32(0xe9),0x1f600,0,0xcccccccc]! && consumed == 2
	} else {
		assert number == 0 && result == -1 && consumed == -1 && unsafe { *C.ios_errno_address() } == 92
		assert bytes == [16]u8{init: 0xcc}
	}
}

fn wide_scan_test_guard(call WideScanCall) {
	page := usize(C.getpagesize())
	bytes := C.mmap(unsafe { nil }, page * 8, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert bytes != voidptr(-1)
	defer { assert C.munmap(bytes, page * 8) == 0 }
	for i in [1, 3, 5, 7]! { assert C.mprotect(voidptr(u64(bytes) + u64(page) * u64(i)), page, C.PROT_NONE) == 0 }
	input := u64(bytes) + u64(page) - 12
	format := u64(bytes) + u64(page) * 3 - 20
	arguments := u64(bytes) + u64(page) * 5 - 8
	output := u64(bytes) + u64(page) * 7 - 2
	for i, value in [u32(`4`), `2`, 0]! { write32(input + u64(i * 4), value) }
	for i, value in [u32(`%`), `2`, `h`, `d`, 0]! { write32(format + u64(i * 4), value) }
	C.memcpy(voidptr(arguments), unsafe { voidptr(&output) }, 8)
	assert call(voidptr(input), voidptr(format), voidptr(arguments)) == 1
	assert unsafe { *(&u16(output)) } == 42
	assert read32(format) == `%` && read64(arguments) == output
	// Literal L and scanset L must remain literal; only real L floats change.
	text := wide_scan_test_text('L %% %3[L] %hs %*Lf %1$LA %hc')
	converted := wide_scan_format(unsafe { &text[0] })
	expected := wide_scan_test_text('L %% %3[L] %s %*lf %1$lA %c')
	assert C.memcmp(converted, expected.data, (C.wcslen(converted) + 1) * 4) == 0
	assert voidptr(converted) != text.data
	unsafe { C.free(converted) }
}

struct WideScanThread {
	call WideScanCall
}
fn wide_scan_test_worker(context voidptr) voidptr {
	state := unsafe { &WideScanThread(context) }
	input := [i32(`4`), `2`, 0]!
	format := [i32(`%`), `d`, 0]!
	for _ in 0 .. 1000 {
		mut output := i32(0)
		arguments := [u64(unsafe { &output })]!
		darwin_set_errno(83)
		assert state.call(unsafe { &input[0] }, unsafe { &format[0] }, unsafe { &arguments[0] }) == 1
		assert output == 42 && unsafe { *C.ios_errno_address() } == 83
	}
	return unsafe { nil }
}
fn test_swscanf() {
	assert sizeof(C.wchar_t) == 4
	assert C.setlocale(i32(C.LC_ALL), c'C') != unsafe { nil }
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != voidptr(-1)
	defer { assert C.munmap(code, page) == 0 }
	// A Darwin variadic caller: copy eight pointers to SP before calling x16.
	for i, op in [u32(0xd10143ff), 0xa9047bfd, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1, 0xaa0303e2,
		0xa9401043, 0xa90013e3, 0xa9411043, 0xa90113e3, 0xa9421043, 0xa90213e3, 0xa9431043, 0xa90313e3,
		0xd63f0200, 0xa9447bfd, 0x910143ff, 0xd65f03c0]! { write32(u64(code) + u64(i * 4), op) }
	C.__builtin___clear_cache(code, voidptr(u64(code) + 72))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { WideScanProbe(code) }
	$if macos {
		native := unsafe { WideScanCall(voidptr(C.vswscanf)) }
		// The variadic entry has the same two named arguments as the native API.
		wide_scan_test_cases(native, u64(C.dlsym(C.dlopen(c'/usr/lib/libSystem.B.dylib', 2), c'swscanf')), probe)
		wide_scan_test_encoding(native, false)
		println('IOS-SWSCANF-NATIVE: exact native counts and writes for game and scalar/string/float/positional formats')
	}
	for _ in 0 .. 2 {
		objc_start()
		call := unsafe { WideScanCall(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_vswscanf')!)) }
		entry := runtime_symbol('/usr/lib/libSystem.B.dylib', '_swscanf')!
		wide_scan_test_cases(call, entry, probe)
		wide_scan_test_encoding(call, false)
		$if macos { assert C.setlocale(i32(C.LC_ALL), c'en_US.UTF-8') != unsafe { nil } }
		$if linux { assert C.setlocale(i32(C.LC_ALL), c'C.UTF-8') != unsafe { nil } }
		wide_scan_test_encoding(call, true)
		$if macos { wide_scan_test_encoding(unsafe { WideScanCall(voidptr(C.vswscanf)) }, true) }
		assert C.setlocale(i32(C.LC_ALL), c'C') != unsafe { nil }
		wide_scan_test_guard(call)
		mut handles := [8]u64{}
		state := WideScanThread{call}
		for i in 0 .. 8 { assert C.pthread_create(unsafe { voidptr(&handles[i]) }, unsafe { nil }, wide_scan_test_worker, unsafe { voidptr(&state) }) == 0 }
		for handle in handles { assert C.pthread_join(voidptr(handle), unsafe { nil }) == 0 }
		mut rejected := false; runtime_symbol('/usr/lib/libobjc.A.dylib', '_swscanf') or { rejected = true }; assert rejected
		objc_stop()
	}
	println('IOS-SWSCANF: Darwin variadic and va_list entries, native parsing, exact writes, guarded spans, long-double layout, eight threads and two runtime lifetimes')
}
