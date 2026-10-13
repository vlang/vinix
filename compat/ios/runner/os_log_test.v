// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <dlfcn.h>
}
fn C.dlsym(voidptr, &char) voidptr
fn C.dlopen(&char, i32) voidptr
fn C.__builtin_os_log_format(&u8, &char, ...) voidptr
fn C.__builtin_os_log_format_buffer_size(&char, ...) u64
fn C.dup(i32) i32
fn C.dup2(i32, i32) i32
type OsLogCreate = fn (&char, &char) u64
type OsLogEnabled = fn (u64, u8) bool
type OsLogEmit = fn (u64, u64, u8, &char, &u8, u32)
type OsLogErrorType = fn () u8

fn log_test_record(bytes &[256]u8, descriptor u8, width int, value u64) u32 {
	unsafe { bytes[0] = if descriptor >> 4 != 0 { u8(2) } else { u8(0) }; if descriptor & 15 == 1 { bytes[0] |= 1 }; bytes[1] = 1; bytes[2] = descriptor; bytes[3] = u8(width) }
	for i in 0 .. width { unsafe { bytes[4 + i] = u8(value >> (u32(i) * 8)) } }
	return u32(width + 4)
}
fn log_test_text(format &char, records &u8, size u32) string {
	mut output := [4096]u8{}
	length := os_log_render(format, records, size, &output)
	assert length >= 0
	return unsafe { tos(&output[0], length) }.clone()
}
fn test_log_native() {
	$if macos {
		lib := unsafe { voidptr(-2) }
		create := unsafe { OsLogCreate(C.dlsym(lib, c'os_log_create')) }
		enabled := unsafe { OsLogEnabled(C.dlsym(lib, c'os_log_type_enabled')) }
		a := create(c'org.vinix.logging.fixture', c'fortnite'); b := create(c'org.vinix.logging.fixture', c'fortnite')
		assert a != 0 && a == b && a != create(c'org.vinix.logging.fixture', c'other')
		default_log := u64(C.dlsym(lib, c'_os_log_default')); disabled := u64(C.dlsym(lib, c'_os_log_disabled'))
		assert default_log != 0 && disabled != 0 && default_log != disabled
		for kind in [u8(0), 1, 2, 0x10, 0x11]! { assert !enabled(disabled, kind) }
		swift := C.dlopen(c'/usr/lib/swift/libswiftos.dylib', C.RTLD_NOW); assert swift != unsafe { nil }
		getter := unsafe { OsLogErrorType(C.dlsym(swift, c'$sSo13os_log_type_ta0A0E5errorABvgZ')) }
		assert getter != unsafe { nil } && getter() == 0x10
		mut bytes := [256]u8{}; mut expected := [256]u8{}
		ptr := unsafe { &bytes[0] }
		C.__builtin_os_log_format(ptr, c'MarketplaceKit error retrieving CT Token: %{public}s', c'network error')
		size := C.__builtin_os_log_format_buffer_size(c'MarketplaceKit error retrieving CT Token: %{public}s', c'network error')
		assert size == u64(log_test_record(&expected, 0x22, 8, u64(c'network error'))) && C.memcmp(ptr, unsafe { &expected[0] }, usize(size)) == 0
		assert log_test_text(c'MarketplaceKit error retrieving CT Token: %{public}s', ptr, u32(size)) == 'MarketplaceKit error retrieving CT Token: network error'
		C.__builtin_os_log_format(ptr, c'%{private}s', unsafe { &char(1) })
		assert C.__builtin_os_log_format_buffer_size(c'%{private}s', unsafe { &char(1) }) == 12
		assert log_test_record(&expected, 0x21, 8, 1) == 12 && C.memcmp(ptr, unsafe { &expected[0] }, 12) == 0
		assert log_test_text(c'%{private}s', ptr, 12) == '<private>'
		C.__builtin_os_log_format(ptr, c'%lld', i64(-42))
		assert log_test_record(&expected, 0, 8, u64(i64(-42))) == 12 && C.memcmp(ptr, unsafe { &expected[0] }, 12) == 0
		assert log_test_text(c'%lld', ptr, 12) == '-42'
		println('IOS-OSLOG-NATIVE: canonical installed handles, disabled policy, Swift error getter and compiler-produced public-string/private-string/signed-scalar records match the V decoder')
	}
}
fn log_test_worker(handle u64) {
	for _ in 0 .. 1000 {
		assert darwin_os_log_create(c'org.vinix.logging.fixture', c'fortnite') == handle
		assert objc_retain(handle) == handle; objc_release(handle)
		assert swift_unknown_retain(handle) == handle; swift_unknown_release(handle)
	}
}
fn log_description(owner u64, _selector &char) u64 {
	assert objc_class(owner) != 0
	assert darwin_os_log_create(c'org.vinix.logging.fixture', c'reentrant') != 0
	return make_string(c'custom error description')
}
fn test_log_runtime() {
	for _ in 0 .. 2 {
		objc_start(); system_data_start() or { panic(err) }
		default_log := os_log_symbol('__os_log_default') or { panic('default') }
		disabled := os_log_symbol('__os_log_disabled') or { panic('disabled') }
		assert default_log == u64(unsafe { &system_data.log_default[0] }) && default_log != disabled
		assert objc_retain(default_log) == default_log; objc_release(default_log)
		a := darwin_os_log_create(c'org.vinix.logging.fixture', c'fortnite')
		assert a != darwin_os_log_create(c'org.vinix.logging.fixture', c'other') && system_data.log_count == 2
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn log_test_worker(a) }; workers.wait()
		assert system_data.log_count == 2
		for kind in [u8(0), 1, 2, 0x10, 0x11]! {
			assert darwin_os_log_type_enabled(a, kind) == (kind != 2) && !darwin_os_log_type_enabled(disabled, kind)
		}
		getter := runtime_symbol('/usr/lib/swift/libswiftos.dylib', '_$sSo13os_log_type_ta0A0E5errorABvgZ') or { panic(err) }
		assert unsafe { OsLogErrorType(voidptr(getter))() } == 0x10
		mut bytes := [256]u8{}; ptr := unsafe { &bytes[0] }
		for descriptor in [u8(0x20), 0x21, 0x40, 0x41]! {
			log_test_record(&bytes, descriptor, 8, 1)
			format := match descriptor { 0x20 { c'%s' } 0x21 { c'%{private}s' } 0x40 { c'%@' } else { c'%{private}@' } }
			assert log_test_text(format, ptr, 12) == '<private>'
		}
		log_test_record(&bytes, 0x22, 8, u64(c'network error'))
		assert log_test_text(c'MarketplaceKit error retrieving CT Token: %{public}s', ptr, 12) == 'MarketplaceKit error retrieving CT Token: network error'
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixLogDescription', 0)
		assert objc_add_method(cls, u64(c'description'), u64(unsafe { voidptr(log_description) }), c'@16@0:8'); objc_register_class(cls)
		object := objc_new(cls); baseline := ios_runtime.live
		log_test_record(&bytes, 0x42, 8, object)
		$if macos {
			mut generated := [256]u8{}
			C.__builtin_os_log_format(unsafe { &generated[0] }, c'Unexpected error retrieving CT Token: %{public}@', unsafe { voidptr(object) })
			assert C.memcmp(ptr, unsafe { &generated[0] }, 12) == 0
		}
		assert log_test_text(c'Unexpected error retrieving CT Token: %{public}@', ptr, 12) == 'Unexpected error retrieving CT Token: custom error description'
		assert ios_runtime.live == baseline; objc_release(object); objc_dispose_class(cls)
		log_test_record(&bytes, 0, 4, u64(u32(i32(-42))))
		assert log_test_text(c'%d', ptr, 8) == '-42'
		log_test_record(&bytes, 2, 8, 0x123456789abcdef)
		assert log_test_text(c'%{public}llx', ptr, 12) == '123456789abcdef'
		log_test_record(&bytes, 1, 8, 123)
		assert log_test_text(c'%{private}llu', ptr, 12) == '<private>'
		log_test_record(&bytes, 0, 8, 0x3ff4000000000000)
		assert log_test_text(c'%g', ptr, 12) == '1.25'
		bytes[0] = 0; bytes[1] = 0
		assert log_test_text(c'literal %%', ptr, 2) == 'literal %'
		mut output := [4096]u8{}
		assert os_log_render(c'%s', unsafe { nil }, 0, &output) == -1
		for size in [u32(0), 1, 3, 4097]! { assert os_log_render(c'literal', ptr, size, &output) == -1 }
		log_test_record(&bytes, 0x22, 8, 1)
		for format in [c'%s', c'%{public}d', c'%{public}.*s', c'%{public}ls', c'%{public}s extra %d']! { assert os_log_render(format, ptr, 12, &output) == -1 }
		bytes[3] = 7; assert os_log_render(c'%{public}s', ptr, 12, &output) == -1
		bytes[3] = 8; bytes[1] = 2; assert os_log_render(c'%{public}s', ptr, 12, &output) == -1
		page := u64(C.getpagesize())
		region := u64(C.mmap(unsafe { nil }, usize(page * 2), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert region != u64(-1) && C.mprotect(unsafe { voidptr(region + page) }, usize(page), C.PROT_NONE) == 0
		guard_record := region + page - 4
		unsafe { *(&u8(guard_record)) = 2; *(&u8(guard_record + 1)) = 1; *(&u8(guard_record + 2)) = 0x22; *(&u8(guard_record + 3)) = 8 }
		assert os_log_render(c'%{public}s', unsafe { &u8(guard_record) }, 4, &output) == -1
		// A bounded public string may fill exactly its cap without a terminator.
		mut text := [1024]u8{}; C.memset(unsafe { &text[0] }, `a`, 1024)
		log_test_record(&bytes, 0x22, 8, u64(unsafe { &text[0] }))
		assert os_log_render(c'%{public}s', ptr, 12, &output) == 1027
		guard_string := region + page - 1024
		C.memset(unsafe { voidptr(guard_string) }, `a`, 1024)
		log_test_record(&bytes, 0x22, 8, guard_string)
		assert os_log_render(c'%{public}s', ptr, 12, &output) == 1027
		assert C.munmap(unsafe { voidptr(region) }, usize(page * 2)) == 0
		// Invoke all four exported fixed-argument entry points through bindings.
		file := C.tmpfile(); assert file != unsafe { nil }
		saved := C.dup(2); assert saved >= 0; C.fflush(C.ios_host_stdio(2))
		assert C.dup2(i32(C.fileno(file)), 2) == 2
		log_test_record(&bytes, 2, 4, 42)
		for i, name in ['__os_log_impl', '__os_log_error_impl', '__os_log_debug_impl', '__os_log_fault_impl']! {
			entry := os_log_symbol(name) or { panic('emit') }
			darwin_set_errno(13)
			unsafe { OsLogEmit(voidptr(entry))(0, default_log, [u8(0), 0x10, 2, 0x11]![i], c'number=%{public}d', ptr, 8) }
			assert unsafe { *C.ios_errno_address() } == 13
		}
		darwin_os_log_impl(0, disabled, 0x10, unsafe { &char(1) }, unsafe { &u8(1) }, 4096)
		C.fflush(C.ios_host_stdio(2)); assert C.dup2(saved, 2) == 2; C.close(saved)
		assert C.fseek(file, 0, 0) == 0
		mut captured := [256]u8{}; got := C.fread(unsafe { &captured[0] }, 1, 256, file); C.fclose(file)
		assert unsafe { tos(&captured[0], int(got)) } == 'number=42\nnumber=42\nnumber=42\n'
		objc_stop(); assert ios_runtime.live == 0
		system_data_stop(); assert system_data == unsafe { nil }
	}
	println('IOS-OSLOG: both MarketplaceKit formats, privacy without dereference, reentrant custom descriptions, scalar decoding, bounded malformed input, canonical handles across 8000 concurrent ARC operations, fixed-argument sink calls and two drained lifetimes')
}
