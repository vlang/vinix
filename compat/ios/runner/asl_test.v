// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn C.dup(i32) i32
fn C.dup2(i32, i32) i32

type AslOpen = fn (&char, &char, u32) u64
type AslClose = fn (u64)
type AslFilter = fn (u64, i32) i32
type AslFile = fn (u64, i32) i32
type AslVLog = fn (u64, u64, i32, &char, voidptr) i32
type AslProbe = fn (u64, u64, i32, &char, &u64) i32

fn asl_address(symbol string) u64 {
	return runtime_symbol('/usr/lib/libSystem.B.dylib', symbol) or { panic(err) }
}

@[_naked]
fn asl_variadic_probe() {
	asm volatile arm64 {
		sub sp, sp, 64
		stp x29, x30, [sp, 48]
		mov x29, sp
		mov x16, x0
		mov x0, x1
		mov x1, xzr
		ldp x9, x10, [x4]
		stp x9, x10, [sp]
		ldp x9, x10, [x4, 16]
		stp x9, x10, [sp, 16]
		ldp x9, x10, [x4, 32]
		stp x9, x10, [sp, 32]
		blr x16
		ldp x29, x30, [sp, 48]
		add sp, sp, 64
		ret
	}
}

fn asl_capture(client u64, level i32, format &char, words &u64, variadic bool) string {
	sink := C.tmpfile()
	assert sink != unsafe { nil }
	saved := C.dup(2)
	assert saved >= 0
	assert C.fflush(C.ios_host_stdio(2)) == 0
	assert C.dup2(i32(C.fileno(sink)), 2) == 2
	darwin_set_errno(13)
	result := if variadic {
		unsafe { AslProbe(voidptr(asl_variadic_probe))(asl_address('_asl_log'), client, level, format, words) }
	} else {
		unsafe { AslVLog(voidptr(asl_address('_asl_vlog')))(client, 0, level, format, words) }
	}
	assert result == 0 && unsafe { *C.ios_errno_address() } == 13
	assert C.fflush(C.ios_host_stdio(2)) == 0
	assert C.dup2(saved, 2) == 2
	C.close(saved)
	assert C.fseek(sink, 0, 0) == 0
	mut bytes := []u8{len: 16384}
	count := C.fread(bytes.data, 1, usize(bytes.len), sink)
	assert count < usize(bytes.len) && C.fclose(sink) == 0
	text := unsafe { tos(bytes.data, int(count)) }.clone()
	unsafe { bytes.free() }
	return text
}

fn asl_worker(index int) {
	open := unsafe { AslOpen(voidptr(asl_address('_asl_open'))) }
	close := unsafe { AslClose(voidptr(asl_address('_asl_close'))) }
	filter := unsafe { AslFilter(voidptr(asl_address('_asl_set_filter'))) }
	log := unsafe { AslVLog(voidptr(asl_address('_asl_vlog'))) }
	for _ in 0 .. 64 {
		darwin_set_errno(42 + index)
		client := open(c'worker', c'user', 4)
		assert client != 0 && filter(client, 0) == 63
		assert log(client, 0, 7, unsafe { &char(1) }, unsafe { nil }) == 0
		assert unsafe { *C.ios_errno_address() } == i32(42 + index)
		close(client)
		assert unsafe { *C.ios_errno_address() } == i32(42 + index)
	}
}

fn test_asl_runtime_and_lifetime() {
	for _ in 0 .. 2 {
		objc_start()
		system_data_start()!
		open := unsafe { AslOpen(voidptr(asl_address('_asl_open'))) }
		close := unsafe { AslClose(voidptr(asl_address('_asl_close'))) }
		filter := unsafe { AslFilter(voidptr(asl_address('_asl_set_filter'))) }
		log := unsafe { AslVLog(voidptr(asl_address('_asl_vlog'))) }
		mut label := [u8(`v`), `i`, `n`, `i`, `x`, 0]!
		darwin_set_errno(42)
		client := open(unsafe { &char(&label[0]) }, c'user', 4)
		assert client != 0 && unsafe { *C.ios_errno_address() } == 42
		label[0] = `X`
		mut previous := i32(63)
		for mask in [i32(0), 0, 63, 255, -1, 256, 0x7fffffff, 0]! {
			assert filter(client, mask) == previous
			previous = i32(u16(mask))
			assert unsafe { *C.ios_errno_address() } == 42
		}
		assert filter(0, 0) == 63 && filter(0, 0) == 0
		assert log(0, 0, 7, unsafe { &char(1) }, unsafe { nil }) == 0
		assert log(client, 0, 7, unsafe { &char(1) }, unsafe { nil }) == 0
		assert log(1, 0, 7, unsafe { &char(1) }, unsafe { nil }) == -1
		assert log(client, 1, 7, c'%s', unsafe { nil }) == -1
		for name in ['_asl_add_log_file', '_asl_remove_log_file']! {
			file := unsafe { AslFile(voidptr(asl_address(name))) }
			for descriptor in [i32(-1), 0x7fffffff, 2]! {
				assert file(0, descriptor) == 0 && file(client, descriptor) == 0
				assert file(1, descriptor) == -1
			}
		}
		mut words := [u64(c'text'), u64(i64(-17)), u64(0x4004000000000000), u64(0xfeed), u64(3),
			u64(c'abcdef')]!
		probe := unsafe { &words[0] }
		assert asl_capture(client, 7, c'%s %d %.1f %#llx %.*s', probe, false) == ''
		assert filter(client, 255) == 0
		for variadic in [false, true]! {
			text := asl_capture(client, 7, c'%s %d %.1f %#llx %.*s', probe, variadic)
			assert text == 'vinix: text -17 2.5 0xfeed abc\n'
			unsafe { text.free() }
		}
		assert filter(client, 128) == 255
		for level in [i32(-1), 7, 8, 0x7fffffff]! {
			text := asl_capture(client, level, c'%s', probe, true)
			assert text == 'vinix: text\n'
			unsafe { text.free() }
		}
		long := 'z'.repeat(8192)
		words[0] = u64(long.str)
		text := asl_capture(client, 7, c'%s', probe, true)
		assert text == 'vinix: ' + long + '\n'
		unsafe {
			text.free()
			long.free()
		}
		for format in [unsafe { &char(nil) }, c'%n', c'%Lf', c'%@', c'%1$d', c'%']! {
			assert log(client, 0, 7, format, unsafe { nil }) == -1
		}
		stderr_client := open(c'local', unsafe { nil }, 5)
		assert filter(stderr_client, 0) == 63
		words[0] = u64(c'stderr bypass')
		local := asl_capture(stderr_client, 7, c'%s', probe, true)
		assert local == 'local: stderr bypass\n'
		unsafe { local.free() }
		close(stderr_client)
		close(client)
		assert system_data.asl_clients == unsafe { nil }
		mut workers := []thread{cap: 8}
		for i in 0 .. 8 { workers << spawn asl_worker(i) }
		workers.wait()
		unsafe { workers.free() }
		assert system_data.asl_clients == unsafe { nil }
		// Shutdown owns clients the application leaves open. All label storage
		// belongs to that same allocation and is retired with it.
		assert open(unsafe { nil }, unsafe { nil }, 0) != 0
		system_data_stop()
		assert system_data == unsafe { nil }
		objc_stop()
	}
	println('IOS-ASL: typed clients/filter/file/vlog ABI, native 16-bit masks and level clamping, real packed variadic calls, mixed scalars/strings and large output, stderr/filter policy, explicit format rejection, errno, 1024 threaded client lifetimes and two shutdown cycles passed')
}

fn test_asl_library_scope() {
	for symbol in ['_asl_open', '_asl_close', '_asl_add_log_file', '_asl_remove_log_file',
		'_asl_set_filter', '_asl_log', '_asl_vlog']! {
		assert asl_address(symbol) != 0
		for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib']! {
			mut rejected := false
			libsystem_symbol(library, symbol) or { rejected = true }
			assert rejected
		}
	}
}
