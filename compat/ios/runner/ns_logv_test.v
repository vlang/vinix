// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
type NSLogVCall = fn (u64, u64)
type NSLogVMake = fn (u64, &u8, i64, u32, bool) u64
type NSLogVDrop = fn (u64)
type NSLogVPush = fn () u64
type NSLogVProbe = fn (u64, u64, u64, u64, &u64)
type NSLogVVariadic = fn (u64, u64, u64)
struct NSLogVApi {
	native bool
	entry u64
	probe u64
	guard u64
	make NSLogVMake
	drop NSLogVDrop
	push NSLogVPush
	pop NSLogVDrop
}
fn nslogv_make(_allocator u64, bytes &u8, length i64, _encoding u32, _external bool) u64 {
	return owned_string(unsafe { tos(bytes, int(length)) })
}
fn nslogv_api(native bool, probe u64, guard u64) NSLogVApi {
	$if macos { if native {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		core := C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', 2)
		obj := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		return NSLogVApi{native: true, entry: u64(C.dlsym(foundation, c'NSLogv')), probe: probe, guard: guard,
			make: unsafe { NSLogVMake(C.dlsym(core, c'CFStringCreateWithBytes')) }, drop: unsafe { NSLogVDrop(C.dlsym(core, c'CFRelease')) },
			push: unsafe { NSLogVPush(C.dlsym(obj, c'objc_autoreleasePoolPush')) }, pop: unsafe { NSLogVDrop(C.dlsym(obj, c'objc_autoreleasePoolPop')) }}
	} }
	return NSLogVApi{entry: runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_NSLogv') or { panic(err) }, probe: probe, guard: guard,
		make: nslogv_make, drop: objc_release, push: objc_pool_push, pop: objc_pool_pop}
}
fn nslogv_string(api NSLogVApi, text string) u64 { return api.make(0, text.str, i64(text.len), 0x08000100, false) }
fn nslogv_capture(api NSLogVApi, format string, arguments u64, variadic bool) string {
	stream := C.tmpfile()
	assert stream != unsafe { nil }
	saved := C.dup(2)
	assert saved >= 0 && C.fflush(C.ios_host_stdio(2)) == 0 && C.dup2(i32(C.fileno(stream)), 2) == 2
	value := nslogv_string(api, format)
	if variadic {
		unsafe { NSLogVVariadic(voidptr(api.probe + 128))(u64(voidptr(C.ios_nslog)), value, arguments) }
	} else {
		unsafe { NSLogVCall(voidptr(api.entry))(value, arguments) }
		mut capture := [u64(0xcafe), 0, 0, 0xbeef]!
		unsafe { NSLogVProbe(voidptr(api.probe))(api.entry, value, arguments, api.guard, &capture[1]) }
		assert capture[0] == 0xcafe && capture[1] == api.guard && capture[2] == 0x1234 && capture[3] == 0xbeef
	}
	api.drop(value)
	assert C.fflush(C.ios_host_stdio(2)) == 0 && C.dup2(saved, 2) == 2
	C.close(saved)
	assert C.fseek(stream, 0, 0) == 0
	mut bytes := []u8{len: 2 * 1024 * 1024 + 4096}
	count := C.fread(bytes.data, 1, usize(bytes.len), stream)
	assert count < usize(bytes.len) && C.fclose(stream) == 0
	result := unsafe { tos(&u8(bytes.data), int(count)).clone() }
	unsafe { bytes.free() }
	return result
}
fn nslogv_case(api NSLogVApi, format string, words &[8]u64, expected string) {
	before := unsafe { *words }
	output := nslogv_capture(api, format, u64(words), false)
	if api.native {
		// Foundation includes its host timestamp/process prefix. The complete
		// message suffix and exactly two calls must still match.
		assert output.count(expected) == 2 && output.ends_with(expected), output
	} else { assert output == expected + expected, output }
	assert C.memcmp(words, unsafe { &before[0] }, 64) == 0
	unsafe { output.free() }
}
fn nslogv_cases(api NSLogVApi) {
	pool := api.push()
	object := nslogv_string(api, 'λ Fortnite 🎮')
	mut words := [u64(i64(-42)), u64(i64(-12345678901)), u64(123456789012), u64(0x3ff4000000000000), u64(c'bytes'), object, 0, 0]!
	nslogv_case(api, 'CASE: %d %ld %llu %.2f %s %@ %%', &words, 'CASE: -42 -12345678901 123456789012 1.25 bytes λ Fortnite 🎮 %\n')
	words = [u64(8), u64(2), u64(0x3ff4000000000000), u64(i64(-6)), u64(3), u64(c'abcdef'), 0, 0]!
	nslogv_case(api, 'CASE: <%*.*f> <%*.*s>', &words, 'CASE: <    1.25> <abc>\n')
	words = [u64(c'abc'), u64(c'abc'), u64(i64(-8)), u64(42), 0, 0, 0, 0]!
	nslogv_case(api, 'CASE: <%8s> <%-8s> <%*d>', &words, 'CASE: <     abc> <abc     > <42      >\n')
	words = [u64(0xff), u64(i64(-128)), u64(0x12345), u64(0xffff), u64(0xabc), u64(9), 0, 0]!
	nslogv_case(api, 'CASE: %hhu %hhd %hu %hd %#lx %zu', &words, 'CASE: 255 -128 9029 -1 0xabc 9\n')
	words = [u64(0), 0, 0, 0, 0, 0, 0, 0]!
	nslogv_case(api, 'CASE: %@ %s <%c> end', &words, 'CASE: (null) (null) <> end\n')
	nslogv_case(api, 'CASE: newline\n', &words, 'CASE: newline\n')
	nslogv_case(api, 'CASE: two\nlines', &words, 'CASE: two\nlines\n')
	output := nslogv_capture(api, 'CASE: literal %%\x00ignored %n', api.guard, false)
	if api.native { assert output.count('CASE: literal %\n') == 2 } else { assert output == 'CASE: literal %\nCASE: literal %\n' }
	unsafe { output.free() }
	nul := nslogv_string(api, 'π\x00tail')
	words[0] = nul
	nslogv_case(api, 'CASE: %@ suffix', &words, 'CASE: π\n')
	api.drop(nul)
	// Exactly one slot before an inaccessible page; the final %s byte may
	// also abut that page when a precision supplies the readable extent.
	page := usize(C.getpagesize())
	region := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert region != voidptr(-1)
	end := u64(region) + u64(page)
	unsafe { *(&u64(end - 8)) = 42 }
	assert C.mprotect(voidptr(end), page, C.PROT_NONE) == 0
	guarded := nslogv_capture(api, 'CASE: %ld', end - 8, false)
	assert guarded.count('CASE: 42\n') == 2
	unsafe { guarded.free(); *(&u8(end - 1)) = `x` }
	words[0] = end - 1
	nslogv_case(api, 'CASE: %.1s', &words, 'CASE: x\n')
	assert C.munmap(region, page * 2) == 0
	if !api.native {
		words[0] = object
		legacy := nslogv_capture(api, 'CASE: legacy %@', u64(unsafe { &words[0] }), true)
		assert legacy == 'CASE: legacy λ Fortnite 🎮\n'
		unsafe { legacy.free() }
	}
	api.drop(object)
	api.pop(pool)
}
__global nslogv_descriptions = i64(0)
fn nslogv_reentry_worker() { assert runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', '_NSLogv') or { panic(err) } != 0 }
fn nslogv_description(_owner u64, _selector &char) u64 {
	C.ios_ref_change(unsafe { &nslogv_descriptions }, 1)
	worker := spawn nslogv_reentry_worker()
	worker.wait()
	ns_logv_checked(make_string(c'INNER'), 0) or { panic(err) }
	return make_string(c'custom description')
}
fn nslogv_worker(format u64, object u64) {
	mut words := [object, u64(42)]!
	for _ in 0 .. 16 { ns_logv_checked(format, u64(unsafe { &words[0] })) or { panic(err) } }
}
fn nslogv_private(api NSLogVApi) {
	if _ := runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', '_NSLogv') { assert false }
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixNSLogvDescription', 0)
	assert objc_add_method(cls, u64(c'description'), u64(unsafe { voidptr(nslogv_description) }), c'@16@0:8')
	objc_register_class(cls)
	object := objc_new(cls)
	mut words := [object, u64(0), 0, 0, 0, 0, 0, 0]!
	before := nslogv_descriptions
	nslogv_case(api, 'CASE: %@', &words, 'INNER\nCASE: custom description\n')
	assert nslogv_descriptions == before + 2 && obj_header(object).refs == 1
	for format in ['%', '%n', '%2$ld', '%Lf', '%ls', '%5@', '%..d', '%llf', '%10000000d', '%999999999999999999999d', '%*d %n']! {
		value := nslogv_string(api, format)
		if _ := ns_logv_checked(value, api.guard) { assert false, format }
		api.drop(value)
	}
	assert nslogv_descriptions == before + 2
	nslogv_limits(api)
	for value in [u64(0), 1, ~u64(0)]! { if _ := ns_logv_checked(value, 0) { assert false } }
	value := nslogv_string(api, 'CASE: %@')
	words[0] = 1
	if _ := ns_logv_checked(value, u64(unsafe { &words[0] })) { assert false }
	api.drop(value)
	// Concurrent whole-message writes must not interleave. Descriptions and
	// their nested logging run before taking the stderr lock.
	stream := C.tmpfile()
	saved := C.dup(2)
	assert C.fflush(C.ios_host_stdio(2)) == 0 && C.dup2(i32(C.fileno(stream)), 2) == 2
	format := nslogv_string(api, 'WORKER: %@ %ld')
	text := nslogv_string(api, 'parallel')
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn nslogv_worker(format, text) }
	workers.wait()
	unsafe { workers.free() }
	api.drop(format)
	api.drop(text)
	assert C.fflush(C.ios_host_stdio(2)) == 0 && C.dup2(saved, 2) == 2
	C.close(saved)
	assert C.fseek(stream, 0, 0) == 0
	mut capture := [8192]u8{}
	count := C.fread(unsafe { &capture[0] }, 1, 8192, stream)
	assert C.fclose(stream) == 0 && count == 128 * 'WORKER: parallel 42\n'.len
	assert unsafe { tos(&capture[0], int(count)) }.count('WORKER: parallel 42\n') == 128
	api.drop(object)
	objc_dispose_class(cls)
}
fn nslogv_limits(api NSLogVApi) {
	large := 'x'.repeat(65536)
	format := nslogv_string(api, large)
	view := ns_logv_snapshot(format) or { panic(err) }
	assert view.len == 65536
	C.free(view.str)
	api.drop(format)
	longer := large + 'x'
	oversized := nslogv_string(api, longer)
	if _ := ns_logv_checked(oversized, api.guard) { assert false }
	api.drop(oversized)
	unsafe { large.free(); longer.free() }
	excess := '%d'.repeat(513)
	if _ := ns_logv_pass(excess, api.guard, 0, true) { assert false }
	unsafe { excess.free() }
	mut words := [u64(1024 * 1024 + 1), u64(42)]!
	star := nslogv_string(api, '%*d')
	if _ := ns_logv_checked(star, u64(unsafe { &words[0] })) { assert false }
	api.drop(star)
	output := u64(C.malloc(1024 * 1024 + 1))
	assert output != 0
	words[0] = 42
	assert ns_logv_pass('%1048576d', u64(unsafe { &words[0] }), output, false) or { panic(err) } == 1024 * 1024
	if _ := ns_logv_pass('%1048576dX', u64(unsafe { &words[0] }), output, false) { assert false }
	if _ := ns_logv_pass('%d', 1, output, false) { assert false }
	if _ := ns_logv_pass('%d', ~u64(7), output, false) { assert false }
	C.free(unsafe { voidptr(output) })
}
fn test_ns_logv() {
	page := usize(C.getpagesize())
	code := C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert code != voidptr(-1)
	defer { assert C.munmap(code, page * 2) == 0 }
	// Call x0=format/x1=va_list with protected spare argument/x8/x20
	// registers, preserving the x20/x21 contexts and capture canaries.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0403f3, 0xaa0003f0, 0xaa0103e0, 0xaa0203e1, 0xaa0303f4, 0xaa0303e8, 0xaa0303e2, 0xaa0303e4, 0xaa0303e5, 0xaa0303e6, 0xaa0303e7, 0xd2824695, 0xd63f0200, 0xa9005674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(u64(code) + u64(i * 4), op) }
	// Separate legacy variadic shim: copy eight anonymous words to SP.
	// The variadic frame must keep FP/LR above its anonymous words.
	write32(u64(code) + 128, 0xd10143ff) // sub sp,sp,#80
	write32(u64(code) + 132, 0xa9047bfd) // stp fp,lr,[sp,#64]
	write32(u64(code) + 136, 0xaa0003f0)
	write32(u64(code) + 140, 0xaa0103e0)
	for i, op in [u32(0xa9401043), 0xa90013e3, 0xa9411043, 0xa90113e3, 0xa9421043, 0xa90213e3, 0xa9431043, 0xa90313e3, 0xd63f0200, 0xa9447bfd, 0x910143ff, 0xd65f03c0]! { write32(u64(code) + 144 + u64(i * 4), op) }
	C.__builtin___clear_cache(code, voidptr(u64(code) + 192))
	assert C.mprotect(code, page, C.PROT_READ | C.PROT_EXEC) == 0 && C.mprotect(voidptr(u64(code) + u64(page)), page, C.PROT_NONE) == 0
	$if macos {
		nslogv_cases(nslogv_api(true, u64(code), u64(code) + u64(page)))
		println('IOS-NSLOGV-NATIVE: direct and guarded x0/x1 ABI, preserved contexts, reusable slots, UTF-8/object/scalar/star/precision formats, nil, NUL and newline behavior, exact protected argument/string extents')
	}
	if _ := ns_logv_checked(0, 0) { assert false }
	for _ in 0 .. 2 {
		objc_start()
		api := nslogv_api(false, u64(code), u64(code) + u64(page))
		nslogv_cases(api)
		nslogv_private(api)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_foundation_arena == 0
		objc_stop()
		if _ := ns_logv_checked(0, 0) { assert false }
	}
	println('IOS-NSLOGV: Foundation va_list export and legacy NSLog stderr, bounded validated grammar/scalars/strings/messages, exactly-once reentrant descriptions, copied format, rejected unsafe formats/objects/lifetimes, atomic concurrent writes and two drained runtimes')
}
