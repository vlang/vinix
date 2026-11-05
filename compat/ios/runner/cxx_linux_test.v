// SPDX-License-Identifier: GPL-2.0-or-later
// Execute the adapted C++ archive through the public ARM64 symbol bridge.
// The companion native ELF reference retains its comparisons while a V
// generator corrects two constructor lifetimes; it covers streams/exceptions.
// neither fixture establishes exception unwinding through Mach-O frames.
module main

import os

$if ios_cxx ? {
	#include "gnu-cxx-abi-probe.h"
	fn C.vinix_ios_gnu_cxx_abi_probe(&u64, u64, &u8, u64) i32
	type LinuxCxxVoid = fn (u64)
	type LinuxCxxPointer = fn () u64
	type LinuxCxxInit = fn (u64, &char, u64)
	type LinuxCxxAppend = fn (u64, &char, u64) u64
	type LinuxCxxCompare = fn (u64, u64, u64, &char, u64) i32
	type LinuxCxxGrow = fn (u64, u64, u64, u64, u64, u64, u64, &char)
	type LinuxCxxSort = fn (&i64, &i64, voidptr)
	type LinuxCxxFacet = fn (u64, u64) u64

	const linux_cxx_string = '__ZNSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE'
	const linux_cxx_canary = u64(0x129ae174ff3682cd)

	fn linux_cxx_address(name string) u64 {
		return runtime_symbol('/usr/lib/libc++.1.dylib', name) or { panic(err) }
	}

	fn linux_cxx_string_bytes(object u64) []u8 {
		// Apple's alternate layout stores short bytes first and its size in
		// byte 23. A long string stores pointer, length, and tagged capacity.
		tag := unsafe { *(&u8(object + 23)) }
		length := if tag & 0x80 == 0 { u64(tag) } else { read64(object + 8) }
		assert length < 4096
		data := if tag & 0x80 == 0 { object } else { read64(object) }
		assert unsafe { *(&u8(data + length)) } == 0
		return unsafe { (&u8(data)).vbytes(int(length)).clone() }
	}

	fn linux_cxx_strings() {
		mut storage := [linux_cxx_canary, u64(0), 0, 0, linux_cxx_canary]!
		object := u64(unsafe { &storage[1] })
		init := unsafe { LinuxCxxInit(voidptr(linux_cxx_address(linux_cxx_string + '6__initEPKcm'))) }
		append := unsafe { LinuxCxxAppend(voidptr(linux_cxx_address(linux_cxx_string + '6appendEPKcm'))) }
		compare := unsafe { LinuxCxxCompare(voidptr(linux_cxx_address('__ZNKSt3__112basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEE7compareEmmPKcm'))) }
		grow := unsafe { LinuxCxxGrow(voidptr(linux_cxx_address(linux_cxx_string + '21__grow_by_and_replaceEmmmmmmPKc'))) }
		destroy := unsafe { LinuxCxxVoid(voidptr(linux_cxx_address(linux_cxx_string + 'D1Ev'))) }
		binary := [u8(`a`), 0, `b`, `c`]!
		init(object, unsafe { &char(&binary[0]) }, 4)
		assert unsafe { *(&u8(object + 23)) } == 4
		mut expected := binary[..].clone()
		mut bytes := linux_cxx_string_bytes(object)
		assert bytes == expected
		unsafe { bytes.free() }
		assert compare(object, 1, 3, unsafe { &char(&binary[1]) }, 3) == 0
		for _ in 0 .. 16 {
			assert append(object, c'0123456789', 10) == object
			expected << '0123456789'.bytes()
		}
		assert unsafe { *(&u8(object + 23)) } & 0x80 != 0
		bytes = linux_cxx_string_bytes(object)
		assert bytes == expected
		unsafe { bytes.free() }
		// Force reallocation while the replacement bytes alias the old buffer.
		// __cap_ includes the terminator; capacity() excludes it.
		capacity := (read64(object + 16) & ~(u64(1) << 63)) - 1
		old := read64(object)
		mut replaced := expected[..9].clone()
		replaced << expected[5..17]
		replaced << expected[11..]
		grow(object, capacity, 64, u64(expected.len), 9, 2, 12, unsafe { &char(old + 5) })
		assert read64(object) != old
		assert (read64(object + 16) & ~(u64(1) << 63)) - 1 >= capacity + 64
		bytes = linux_cxx_string_bytes(object)
		assert bytes == replaced
		unsafe { bytes.free() }
		assert storage[0] == linux_cxx_canary && storage[4] == linux_cxx_canary
		destroy(object)
		assert storage[0] == linux_cxx_canary && storage[4] == linux_cxx_canary
		unsafe {
			expected.free()
			replaced.free()
		}

		mut values := [i64(123), 1099511627776, -1099511627776, 0, 42, 42, i64(456)]!
		mut comparator := u8(0)
		sort := unsafe { LinuxCxxSort(voidptr(linux_cxx_address('__ZNSt3__16__sortIRNS_6__lessIllEEPlEEvT0_S5_T_'))) }
		sort(unsafe { &values[1] }, unsafe { &values[6] }, unsafe { &comparator })
		assert values == [i64(123), -1099511627776, 0, 42, 42, 1099511627776, i64(456)]!
	}

	fn linux_cxx_locale() {
		mut storage := [linux_cxx_canary, u64(0), linux_cxx_canary]!
		object := u64(unsafe { &storage[1] })
		init := unsafe { LinuxCxxVoid(voidptr(linux_cxx_address('__ZNSt3__16localeC1Ev'))) }
		destroy := unsafe { LinuxCxxVoid(voidptr(linux_cxx_address('__ZNSt3__16localeD1Ev'))) }
		use_facet := unsafe { LinuxCxxFacet(voidptr(linux_cxx_address('__ZNKSt3__16locale9use_facetERNS0_2idE'))) }
		init(object)
		facet := use_facet(object, linux_cxx_address('__ZNSt3__15ctypeIcE2idE'))
		assert facet != 0
		// ctype<char> follows locale::facet's vptr and reference count with
		// its mask table. Darwin's public mask is 32 bits, unlike glibc's
		// native 16-bit __ctype_b entries. Test independent ASCII properties.
		table := read64(facet + 16)
		assert table != 0
		for value in 0 .. 128 {
			mask := read32(table + u64(value) * 4)
			upper := value >= `A` && value <= `Z`
			lower := value >= `a` && value <= `z`
			digit := value >= `0` && value <= `9`
			assert (mask & 0x8000 != 0) == upper
			assert (mask & 0x1000 != 0) == lower
			assert (mask & 0x100 != 0) == (upper || lower)
			assert (mask & 0x400 != 0) == digit
			assert (mask & 0x4000 != 0) == (value in [9, 10, 11, 12, 13, 32])
			assert (mask & 0x200 != 0) == (value < 32 || value == 127)
			assert (mask & 0x40000 != 0) == (value >= 32 && value <= 126)
			assert (mask & 0x20000 != 0) == (value in [9, 32])
			assert (mask & 0x10000 != 0) == (digit || (value >= `a` && value <= `f`) || (value >= `A` && value <= `F`))
		}
		assert use_facet(object, linux_cxx_address('__ZNSt3__17codecvtIcc11__mbstate_tE2idE')) != 0
		destroy(object)
		assert storage[0] == linux_cxx_canary && storage[2] == linux_cxx_canary
		thread_data := unsafe { LinuxCxxPointer(voidptr(linux_cxx_address('__ZNSt3__119__thread_local_dataEv'))) }
		key := thread_data()
		assert key != 0 && read64(key) <= u64(0xffffffff)
	}

	fn linux_cxx_conversions() {
		mut words := [48]u64{}
		mut bytes := [192]u8{}
		assert C.vinix_ios_gnu_cxx_abi_probe(unsafe { &words[0] }, 48, unsafe { &bytes[0] }, 192) == 0
		// The generated dependency adapter reports native observations only.
		// Keep the expected layouts, conversions, stream contents and file
		// positioning checks here, in V, outside the C++ library being tested.
		expected := [u64(128), 8, 16, 144, 8, 32, 1, 90, 1, 81, 3, 1, 65, 66, 67, 3, 1, 1, 78,
			1, 82, 2, 1, 104, 105, 1, 1, 20, 1099511627776, 6, 1, 0, 3, 3, 99, 97, 116, 0, 3, 3,
			0, 90, 0, 90, 0, 1, 1, 8]!
		assert words == expected
		for offset in [0, 136, 144, 168] {
			for i in 0 .. 8 {
				assert bytes[offset + i] == u8(linux_cxx_canary >> (8 * i))
			}
		}
		for i in 16 .. 136 {
			assert bytes[i] == 0xa5
		}
		assert bytes[176] == `c` && bytes[177] == `a` && bytes[178] == `t`
		for i in 179 .. bytes.len {
			assert bytes[i] == 0
		}
	}

	struct LinuxCxxWorker {
	mut:
		completed bool
	}

	fn linux_cxx_worker(context voidptr) voidptr {
		mut state := unsafe { &LinuxCxxWorker(context) }
		state.completed = true
		return unsafe { voidptr(0x1234) }
	}

	fn linux_cxx_threads() {
		join := unsafe { LinuxCxxVoid(voidptr(linux_cxx_address('__ZNSt3__16thread4joinEv'))) }
		destroy := unsafe { LinuxCxxVoid(voidptr(linux_cxx_address('__ZNSt3__16threadD1Ev'))) }
		for _ in 0 .. 16 {
			mut state := LinuxCxxWorker{}
			mut storage := [linux_cxx_canary, u64(0), linux_cxx_canary]!
			object := u64(unsafe { &storage[1] })
			assert darwin_pthread_create(unsafe { voidptr(object) }, unsafe { nil }, unsafe { voidptr(linux_cxx_worker) }, unsafe { &state }) == 0
			name := mach_threads_join_begin(storage[1])
			assert name != 0
			join(object)
			assert storage[1] == 0 && state.completed
			// pthread_join can clear a native robust list before an emulated
			// owner-death update. Retire the matching adapter registration.
			assert mach_thread_find(name) == unsafe { nil }
			assert storage[0] == linux_cxx_canary && storage[2] == linux_cxx_canary
			destroy(object)
		}
		assert system_data.thread_ports == unsafe { nil }
	}

	fn test_linux_cxx_archive_and_darwin_symbol_abi() {
		$if !linux || !arm64 {
			assert false, 'this fixture requires the real Linux ARM64 ABI'
		}
		mut symbol_count := 0
		// Read the captured input directly: this frozen V compiler's runtime
		// embed-file reload path double-frees V_RESOURCE_PATH under ASan.
		symbols := os.read_file(os.join_path(os.dir(@FILE), 'abi', 'cxx-symbols.txt')) or { panic(err) }
		for name in symbols.split_into_lines() {
			if name.len == 0 || name.starts_with('#') { continue }
			assert linux_cxx_address(name) != 0
			symbol_count++
		}
		assert symbol_count >= 230
		if _ := runtime_symbol('/usr/lib/libc++.1.dylib', '__ZNSt3__1vinix_missing_cxx_exportEv') {
			assert false, 'unknown C++ export was manufactured'
		}
		assert linux_cxx_address('___cxa_throw') == u64(unsafe { voidptr(cxx_unwind_unsupported) })
		assert linux_cxx_address('___cxa_rethrow') == u64(unsafe { voidptr(cxx_unwind_unsupported) })
		for _ in 0 .. 2 {
			objc_start()
			system_data_start() or { panic(err) }
			linux_cxx_strings()
			linux_cxx_locale()
			linux_cxx_conversions()
			linux_cxx_threads()
			system_data_stop()
			objc_stop()
			assert system_data == unsafe { nil } && ios_runtime.live == 0
		}
		println('IOS-LINUX-CXX-SYMBOLS: ${symbol_count} curated symbols; unknown export and Mach-O unwind boundaries retained')
		println('IOS-LINUX-CXX-STRINGS: alternate layout, embedded NUL, heap growth, aliasing, sentinels and signed 64-bit sort')
		println('IOS-LINUX-CXX-LOCALE: Darwin 32-bit ASCII masks, mbstate-tagged facet and 64-bit TLS key')
		println('IOS-LINUX-CXX-CONVERSIONS: guarded 128-byte state, native 16-byte fpos, explicit/null conversion state, wide streams and codecvt roundtrip')
		println('IOS-LINUX-CXX-THREADS: 32 native C++ joins retire adapter-created threads')
		println('IOS-LINUX-CXX-CLEANUP: two complete runtime lifetimes with zero live objects')
	}
}
