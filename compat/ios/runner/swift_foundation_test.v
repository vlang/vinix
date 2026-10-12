// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
$if macos {
	#include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringGetCString(voidptr, &char, i64, u32) bool
fn C.CFRelease(voidptr)
type LogCall = fn (u64, u64, u64)
type LogLiteral = fn (&u8, i64, bool) SwiftStringWords
type LogAllocate = fn (i64, u64) SwiftArrayAllocation
type LogRelease = fn (u64)
type LogWitness = fn (u64, u64, u64) u64
type LogExistential = fn (u64, u64, u64, &u64) u64
type LogBridge = fn (u64, u64) u64
type LogSign = fn (u64, u64) u64
struct LogApi {
	native bool
	call LogCall
	literal LogLiteral
	allocate LogAllocate
	release LogRelease
	bridge LogBridge
	integer u64
	string_type u64
	int_table u64
	string_table u64
	element u64
}
struct LogCallback {
mut:
	api LogApi
	calls u64
	table u64
}
fn log_resolve_worker() u64 {
	return runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$sSSs7CVarArg10FoundationMc') or { panic(err) }
}
fn log_callback(metadata u64, table u64, source u64) u64 {
	mut target := unsafe { &LogCallback(read64(source)) }
	assert metadata == target.api.integer && table == target.table
	if !target.api.native { worker := spawn log_resolve_worker(); assert worker.wait() != 0 }
	target.calls++
	array := target.api.allocate(2, target.api.integer)
	unsafe { *(&u64(array.bytes)) = 123; *(&u64(array.bytes + 8)) = u64(i64(-7)) }
	return array.owner
}
fn log_custom(api LogApi) {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	data := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1) && data != u64(-1)
	write32(code, 0xaa1403e2); write32(code + 4, 0x58000070); write32(code + 8, 0xd61f0200)
	unsafe { *(&u64(code + 16)) = u64(voidptr(log_callback)) }
	write32(code + 32, 0xdac10020); write32(code + 36, 0xd65f03c0)
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 40) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	mut target := unsafe { &LogCallback(C.__builtin_alloca(sizeof(LogCallback))) }
	unsafe { *target = LogCallback{ api: api, table: data + u64(page) - 16 } }
	mut entry := code
	if api.native { sign := unsafe { LogSign(voidptr(code + 32)) }; entry = sign(code, (target.table + 8) | (u64(0x95c4) << 48)) }
	unsafe { *(&u64(target.table)) = read64(api.int_table); *(&u64(target.table + 8)) = entry }
	assert C.mprotect(unsafe { voidptr(data) }, page, C.PROT_READ) == 0
	assert C.mprotect(unsafe { voidptr(data + u64(page)) }, page, C.PROT_NONE) == 0
	array := api.allocate(1, api.element)
	unsafe { *(&u64(array.bytes)) = u64(target); *(&u64(array.bytes + 24)) = api.integer; *(&u64(array.bytes + 32)) = target.table }
	output := log_capture(api, 'IOS-NSLOG-CUSTOM: %ld %ld', array.owner)
	if !api.native { assert output.contains('IOS-NSLOG-CUSTOM: 123 -7\n'), output }
	unsafe { output.free() }
	assert target.calls == 1 && read64(array.bytes) == u64(target)
	api.release(array.owner)
	assert C.munmap(unsafe { voidptr(code) }, page) == 0 && C.munmap(unsafe { voidptr(data) }, page * 2) == 0
}

// Private fixture metadata exercises the measured 40-byte existential Array
// layout. Only destruction is used; runtime-wide existential creation and
// boxed CVarArg support are deliberately outside this feature.
fn log_fixture_destroy(value u64, metadata u64) {
	concrete := read64(value + 24)
	destroy := unsafe { SwiftLogDestroy(voidptr(read64(read64(concrete - 8) + 8))) }
	destroy(value, concrete)
}
fn log_fixture_element(data u64) u64 {
	witness := data + 64; metadata := data + 8
	unsafe {
		*(&u64(metadata - 8)) = witness; *(&u64(metadata)) = 0x303
		*(&u64(metadata + 16)) = swift_integer_metadata() - 16 + 560
		*(&u64(witness + 8)) = u64(voidptr(log_fixture_destroy))
		*(&u64(witness + 64)) = 40; *(&u64(witness + 72)) = 40
	}
	write32(metadata + 8, 0x80000001); write32(metadata + 12, 1); write32(witness + 80, 0x30007)
	return metadata
}
fn log_api(native bool, data u64) LogApi {
	mut core := unsafe { voidptr(nil) }; mut foundation := unsafe { voidptr(nil) }
	$if macos { if native {
		core = C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
		foundation = C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', C.RTLD_NOW)
		assert core != unsafe { nil } && foundation != unsafe { nil }
	} }
	mut values := [10]u64{}
	for i, name in ['_$s10Foundation5NSLogyySS_s7CVarArg_pdtF', '_$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC',
		'_$ss27_allocateUninitializedArrayySayxG_BptBwlF', '_swift_bridgeObjectRelease',
		'_$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF', '_$sSiN', '_$sSSN', '_$sSis7CVarArgsWP',
		'_$sSSs7CVarArg10FoundationMc', '_swift_getWitnessTable']! {
		is_foundation := i == 0 || i == 4 || i == 8
		if native { values[i] = u64(C.dlsym(if is_foundation { foundation } else { core }, name[1..].str)) }
		else { values[i] = runtime_symbol('/usr/lib/swift/' + if is_foundation { 'libswiftFoundation.dylib' } else { 'libswiftCore.dylib' }, name) or { panic(err) } }
		assert values[i] != 0, name
	}
	lookup := unsafe { LogWitness(voidptr(values[9])) }
	table := lookup(values[8], values[6], 0)
	mut element := u64(0)
	$if macos { if native {
		get_type := unsafe { LogExistential(C.dlsym(core, c'swift_getExistentialTypeMetadata')) }
		mut protocol := u64(C.dlsym(core, c'$ss7CVarArgMp'))
		element = get_type(1, 0, 1, unsafe { &protocol })
		assert read64(read64(element - 8) + 64) == 40
	} }
	if !native { element = log_fixture_element(data) }
	return LogApi{ native: native, call: unsafe { LogCall(voidptr(values[0])) }, literal: unsafe { LogLiteral(voidptr(values[1])) },
		allocate: unsafe { LogAllocate(voidptr(values[2])) }, release: unsafe { LogRelease(voidptr(values[3])) },
		bridge: unsafe { LogBridge(voidptr(values[4])) }, integer: values[5], string_type: values[6], int_table: values[7],
		string_table: table, element: element }
}

fn log_capture(api LogApi, format string, owner u64) string {
	if api.native {
		value := api.literal(format.str, i64(format.len), false)
		api.call(value.first, value.second, owner)
		return '' // Native output is captured once around the complete batch.
	}
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	backup := C.dup(2); assert backup >= 0
	assert C.fflush(C.ios_host_stdio(2)) == 0 && C.dup2(fds[1], 2) == 2
	C.close(fds[1])
	value := api.literal(format.str, i64(format.len), false)
	api.call(value.first, value.second, owner)
	assert C.fflush(C.ios_host_stdio(2)) == 0 && C.dup2(backup, 2) == 2
	C.close(backup)
	mut poll := C.pollfd{ fd: fds[0], events: 1 }
	assert C.poll(unsafe { &poll }, 1, 2000) > 0
	mut bytes := [8192]u8{}; count := C.read(fds[0], unsafe { &bytes[0] }, bytes.len)
	assert count >= 0; C.close(fds[0])
	return unsafe { tos(&bytes[0], int(count)) }.clone()
}
fn log_cases(api LogApi) {
	array := api.allocate(2, api.element)
	text := 'λ Fortnite native Swift log argument'
	value := api.literal(text.str, i64(text.len), false)
	unsafe {
		*(&SwiftStringWords(array.bytes)) = value
		*(&u64(array.bytes + 24)) = api.string_type; *(&u64(array.bytes + 32)) = api.string_table
		*(&u64(array.bytes + 40)) = u64(i64(-42))
		*(&u64(array.bytes + 64)) = api.integer; *(&u64(array.bytes + 72)) = api.int_table
	}
	output := log_capture(api, 'IOS-NSLOG-CASE: %@ integer=%ld %%', array.owner)
	if !api.native { assert output.contains('IOS-NSLOG-CASE: '+text+' integer=-42 %\n'), output }
	unsafe { output.free() }
	assert read64(array.owner + 8) == 3 && read64(array.bytes + 40) == u64(i64(-42))
	if !api.native { assert ios_runtime.swift_arrays.len == 1 && ios_runtime.swift_buffers.len == 0 }
	api.release(array.owner)
	empty := api.allocate(0, api.element)
	plain := log_capture(api, 'IOS-NSLOG-EMPTY: utf8 π %% literal', empty.owner)
	if !api.native { assert plain.contains('IOS-NSLOG-EMPTY: utf8 π % literal\n'), plain }
	unsafe { plain.free() }; api.release(empty.owner)
	// The String bridge returns a caller-owned object and borrows String words.
	object := api.bridge(value.first, value.second)
	if !api.native { assert string_text(object) == text; objc_release(object) }
	$if macos { if api.native {
		mut buffer := [256]u8{}
		assert C.CFStringGetCString(unsafe { voidptr(object) }, unsafe { &char(&buffer[0]) }, 256, 0x08000100)
		assert unsafe { (&char(&buffer[0])).vstring() } == text
		C.CFRelease(unsafe { voidptr(object) })
	} }
}
fn log_native_batch() {
	api := log_api(true, 0)
	mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0
	backup := C.dup(2); assert backup >= 0 && C.dup2(fds[1], 2) == 2; C.close(fds[1])
	log_cases(api); log_custom(api)
	assert C.fflush(C.ios_host_stdio(2)) == 0 && C.dup2(backup, 2) == 2; C.close(backup)
	mut poll := C.pollfd{ fd: fds[0], events: 1 }
	assert C.poll(unsafe { &poll }, 1, 2000) > 0, 'Native NSLog produced no captured output'
	mut bytes := [8192]u8{}; count := C.read(fds[0], unsafe { &bytes[0] }, bytes.len); assert count > 0; C.close(fds[0])
	text := unsafe { tos(&bytes[0], int(count)) }
	assert text.contains('IOS-NSLOG-CASE: λ Fortnite native Swift log argument integer=-42 %\n'), text
	assert text.contains('IOS-NSLOG-EMPTY: utf8 π % literal\n'), text
	assert text.contains('IOS-NSLOG-CUSTOM: 123 -7\n'), text
}
fn log_invalid(api LogApi) {
	empty := api.allocate(0, api.element)
	for format in ['%', '%n', '%*d', '%2$ld', '%Lf', '%10000000d', '%5@', 'NUL\x00format']! {
		value := api.literal(format.str, i64(format.len), true)
		if _ := swift_nslog_checked(value.first, value.second, empty.owner) { assert false }
	}
	value := api.literal('%ld'.str, 3, true)
	if _ := swift_nslog_checked(value.first, value.second, empty.owner) { assert false }
	for owner in [u64(0), 1, ~u64(0)]! { if _ := swift_nslog_checked(value.first, value.second, owner) { assert false } }
	api.release(empty.owner)
	assert ios_runtime.swift_arrays.len == 0
}
fn test_swift_foundation() {
	$if macos {
		log_native_batch()
		println('IOS-SWIFT-NSLOG-NATIVE: actual NSLog formatting of String and Int existential arguments, UTF-8, percent escaping and empty arrays; borrowed inputs and caller-owned NSString bridge')
	}
	if _ := swift_foundation_symbol('_$s10Foundation5NSLogyySS_s7CVarArg_pdtF') { assert false }
	for _ in 0 .. 2 {
		objc_start()
		page := usize(C.getpagesize())
		data := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert data != u64(-1)
		api := log_api(false, data)
		assert C.mprotect(unsafe { voidptr(data) }, page, C.PROT_READ) == 0
		baseline := ios_runtime.live
		log_cases(api); log_custom(api); log_invalid(api)
		assert ios_runtime.live == baseline && ios_runtime.swift_arrays.len == 0
		objc_stop()
		assert ios_runtime.swift_foundation_arena == 0
		assert C.munmap(unsafe { voidptr(data) }, page) == 0
		if _ := swift_foundation_symbol('_$s10Foundation5NSLogyySS_s7CVarArg_pdtF') { assert false }
	}
	println('IOS-SWIFT-NSLOG: borrowed existential Arrays, copied inline values and actual encoding witnesses, owned encoding release and bridged NSString autorelease scope, UTF-8/printf/object formatting, rejected unsafe formats and foreign storage, no owned temporaries after two drained lifetimes')
}
