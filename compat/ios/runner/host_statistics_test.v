// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos { fn C.mach_task_self() u32 }

type HostStats = fn (u32, i32, voidptr, &u32) i32
type HostStatsWide = fn (u64, i64, voidptr, &u32) i32

fn hs_parse() {
	mut memory := MachHostMemory{}
	valid := 'MemTotal: 8000 kB\nMemFree: 800 kB\nCached: 800 kB\nSlab: 400 kB\nZswap: 200 kB\nZswapped: 1200 kB\nVinixPageouts: 8589934597\nVinixRefaults: 4294967299\nIgnored: arbitrary\n'
	assert mach_host_memory_parse(valid.str, valid.len, unsafe { &memory })
	assert memory.total == 8192000 && memory.free == 819200 && memory.cached == 819200 && memory.slab == 409600 && memory.compressed == 204800 && memory.uncompressed == 1228800 && memory.pageouts == 8589934597 && memory.pageins == 4294967299
	for bad in ['', 'MemTotal: 1 kB\n', 'MemTotal: 1 kB\nMemFree: 2 kB\n', 'MemTotal: 1 kB\nMemFree: 0 kB\nMemFree: 0 kB', 'MemTotal: 18446744073709551616 kB\nMemFree: 0 kB', 'MemTotal: 18446744073709551615 kB\nMemFree: 0 kB', 'MemTotal: -1 kB\nMemFree: 0 kB', 'MemTotal: 1 MB\nMemFree: 0 kB', 'MemTotal: 1 kB junk\nMemFree: 0 kB', 'MemTotal: 1 kB\nMemFree: 0 kB\nCached:', 'MemTotal: 1 kB\nMemFree: 0 kB\nVinixRefaults: 1 kB']! {
		before := memory.total
		assert !mach_host_memory_parse(bad.str, bad.len, unsafe { &memory }) && memory.total == before
	}
	minimum := 'MemTotal: 1 kB\nMemFree: 0 kB'
	assert mach_host_memory_parse(minimum.str, minimum.len, unsafe { &memory }) && memory.cached == 0 && memory.pageouts == 0
}

fn hs_packing() {
	page := u64(C.getpagesize())
	memory := MachHostMemory{total: 2000 * page, free: 200 * page, cached: 200 * page, slab: 100 * page, compressed: 50 * page, uncompressed: 300 * page, pageouts: 0x200000005, pageins: 0x100000003}
	region := C.mmap(unsafe { nil }, usize(page * 3), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)
	assert region != unsafe { voidptr(-1) }; defer { assert C.munmap(region, usize(page * 3)) == 0 }
	assert C.mprotect(voidptr(u64(region) + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	for wide in [false, true]! {
		for requested in u32(0) .. 67 {
			length := mach_host_statistics_count(requested, wide)
			if length == 0 { continue }
			for end_gap in [u64(0), 1, 3]! {
				C.memset(voidptr(u64(region) + page), 0xa5, usize(page))
				at := u64(region) + page * 2 - u64(length) * 4 - end_gap; mut count := requested
				mach_host_statistics_copy(memory, wide, length, voidptr(at), unsafe { &count })
				assert count == length
				mut words := [62]u32{}; unsafe { C.memcpy(voidptr(&words[0]), voidptr(at), usize(length) * 4) }
				assert words[0] == 200 && words[1] == 1450 && words[2] == 200 && words[3] == 100
				if wide {
					assert words[8] == 3 && words[9] == 1 && words[10] == 5 && words[11] == 2
					if length >= 38 { assert words[32] == 50 && words[34] == 200 && words[35] == 1450 && words[36] == 300 && words[37] == 0 }
					for i in 38 .. int(length) { assert words[i] == 0 }
				} else { assert words[6] == 0xffffffff && words[7] == 0xffffffff }
				for position in u64(region) + page .. at { assert unsafe { *(&u8(position)) } == 0xa5 }
				for position in at + u64(length) * 4 .. u64(region) + page * 2 { assert unsafe { *(&u8(position)) } == 0xa5 }
			}
		}
	}
	mut words := [62]u32{}; mut count := u32(62)
	mach_host_statistics_copy(MachHostMemory{total: page * 4, free: page, cached: ~u64(0), slab: ~u64(0), compressed: ~u64(0)}, true, 62, unsafe { voidptr(&words[0]) }, unsafe { &count })
	assert words[0] == 1 && words[1] == 0 && words[2] == 3 && words[3] == 0 && words[32] == 0
}

fn hs_calls(get HostStats, host u32, wide bool, id int) {
	mut environment := [32]u64{}; assert C.fegetenv(unsafe { voidptr(&environment[0]) }) == 0
	previous := unsafe { *C.ios_errno_address() }; defer { C.fesetenv(unsafe { voidptr(&environment[0]) }); darwin_set_errno(previous) }
	dirty := unsafe { HostStatsWide(voidptr(get)) }
	for rounding in [i32(C.FE_TONEAREST), C.FE_UPWARD, C.FE_DOWNWARD, C.FE_TOWARDZERO]! {
		assert C.fesetround(rounding) == 0; C.feclearexcept(C.FE_ALL_EXCEPT); C.feraiseexcept(C.FE_DIVBYZERO | C.FE_INEXACT)
		flags := C.fetestexcept(C.FE_ALL_EXCEPT)
		for flavor in [i32(2), 4, 0, 999]! {
			for requested in u32(0) .. 67 {
				mut words := [256]u32{init: 0xa5a5a5a5}; mut count := requested
				darwin_set_errno(90 + id)
				result := dirty(0xcafebabe00000000 | u64(host), i64(0x1234567800000000 | u64(flavor)), unsafe { voidptr(&words[0]) }, unsafe { &count })
				assert unsafe { *C.ios_errno_address() } == 90 + id && C.fegetround() == rounding && C.fetestexcept(C.FE_ALL_EXCEPT) == flags
				length := mach_host_statistics_count(requested, flavor == 4)
				expected := if flavor != 2 && !(wide && flavor == 4) { i32(4) } else if length == 0 { i32(5) } else { i32(0) }
				assert result == expected
				if result == 0 { assert count == length } else { assert count == requested }
				for i in int(if result == 0 { length } else { u32(0) }) .. words.len { assert words[i] == 0xa5a5a5a5 }
			}
		}
	}
}

fn hs_worker(get HostStats, host u32, id int) {
	for _ in 0 .. 16 {
		mut words := [62]u32{}; mut count := u32(40); darwin_set_errno(110 + id)
		assert darwin_mach_host_self() == host
		assert get(host, 4, unsafe { voidptr(&words[0]) }, unsafe { &count }) == 0 && count == 40
		assert darwin_mach_port_deallocate(system_data.task_self, host) == 0
		assert unsafe { *C.ios_errno_address() } == 110 + id
	}
}

fn test_host_statistics() {
	hs_parse(); hs_packing()
	assert system_data == unsafe { nil }
	for _ in 0 .. 2 {
		objc_start(); system_data_start()!
		assert runtime_symbol('/usr/lib/libSystem.B.dylib', '_mach_host_self')! == u64(unsafe { voidptr(darwin_mach_host_self) })
		host := darwin_mach_host_self(); assert host != 0
		task := system_data.task_self; mut refs := u32(0); mut kind := u32(0)
		assert darwin_mach_port_type(task, host, unsafe { &kind }) == 0 && kind == 0x10000
		assert darwin_mach_port_get_refs(task, host, 0, unsafe { &refs }) == 0; before := refs
		assert darwin_mach_host_self() == host
		assert darwin_mach_port_get_refs(task, host, 0, unsafe { &refs }) == 0 && refs == before + 1
		for right in i32(-1) .. 7 {
			refs = 0xa5a5a5a5
			assert darwin_mach_port_get_refs(task, host, right, unsafe { &refs }) == if right < 0 || right > 5 { i32(18) } else { i32(0) }
			if right > 0 && right <= 5 { assert refs == 0 }
			for delta in [i32(-65536), 0, 65536]! {
				expected := if right < 0 || right > 5 || (right == 0 && delta != 0) { i32(18) } else if right != 0 { i32(17) } else { i32(0) }
				assert darwin_mach_port_mod_refs(task, host, right, delta) == expected
			}
		}
		for pair in [['_host_statistics', '0']!, ['_host_statistics64', '1']!]! {
			get := unsafe { HostStats(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', pair[0])!)) }
			hs_calls(get, host, pair[1] == '1', 0)
			for invalid in [u32(0), 0xffffffff, 0x12345678, task]! {
				mut words := [62]u32{init: 0xa5a5a5a5}; mut count := u32(62)
				assert get(invalid, 2, unsafe { voidptr(&words[0]) }, unsafe { &count }) == if invalid == task { i32(22) } else { i32(0x10000003) }
				assert count == 62; for word in words { assert word == 0xa5a5a5a5 }
			}
			for library in ['/usr/lib/libobjc.A.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
				mut rejected := false; runtime_symbol(library, pair[0]) or { rejected = true }; assert rejected
			}
		}
		get64 := unsafe { HostStats(voidptr(runtime_symbol('/usr/lib/libSystem.B.dylib', '_host_statistics64')!)) }
		mut workers := []thread{cap: 8}; for id in 0 .. 8 { workers << spawn hs_worker(get64, host, id) }; workers.wait(); unsafe { workers.free() }
		mut code := [i32(1), 0]!; mut old := [1296]u32{}; mut state := [1296]u32{}; mut flavor := i32(6); mut state_count := u32(1296)
		mut descriptor_task := task
		$if macos { descriptor_task = C.mach_task_self() }
		assert darwin_exception_raise(host, descriptor_task, descriptor_task, 1, unsafe { &code[0] }, 1) == 5
		assert darwin_exception_raise_state(host, 1, unsafe { &code[0] }, 1, unsafe { &flavor }, unsafe { &old[0] }, 0, unsafe { &state[0] }, unsafe { &state_count }) == 4
		assert darwin_semaphore_signal(host) == 20 && darwin_semaphore_destroy(task, host) == 4
		$if linux {
			image_atfork_start()!
			pid := darwin_fork(); assert pid >= 0
			if pid == 0 {
				mut count := u32(40); mut words := [62]u32{}
				if get64(host, 4, unsafe { voidptr(&words[0]) }, unsafe { &count }) != i32(0x10000003) { C._exit(1) }
				fresh := darwin_mach_host_self(); if fresh == 0 || fresh == host { C._exit(2) }
				if get64(fresh, 4, unsafe { voidptr(&words[0]) }, unsafe { &count }) != 0 { C._exit(3) }
				C._exit(0)
			}
			mut status := i32(-1); assert darwin_waitpid(pid, unsafe { &status }, 0) == pid && status == 0
			image_atfork_stop()
		}
		assert darwin_mach_port_deallocate(task, host) == 0 && darwin_mach_port_deallocate(task, host) == 0
		$if linux {
			assert darwin_mach_port_type(task, host, unsafe { &kind }) == 15
			mut count := u32(40); mut words := [62]u32{}
			assert get64(host, 4, unsafe { voidptr(&words[0]) }, unsafe { &count }) == i32(0x10000003)
			fresh := darwin_mach_host_self(); assert fresh != host && fresh != 0
			assert darwin_mach_port_mod_refs(task, fresh, 0, -2) == 18
			assert darwin_mach_port_mod_refs(task, fresh, 0, 65535) == 0
			assert darwin_mach_port_mod_refs(task, fresh, 0, -65535) == 20
		}
		system_data_stop(); objc_stop()
	}
	println('IOS-HOST-STATISTICS: native count/error oracle, bounded snapshot parser, guarded revision layouts, 64-bit counters, saturation, errno/fenv, host rights, eight readers and two lifecycles passed')
}
