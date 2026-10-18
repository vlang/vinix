// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) i32
type RQQuery = fn (&char, i32, i32, &u8, i32) i32
type RQMake = fn (i32, &char, i32, i32, voidptr, i32, voidptr, &u8, i32) i32
type RQState = fn () voidptr
type RQInit = fn () i32
type RQServers = fn (voidptr, voidptr, i32)

fn rq_names(native RQMake) {
	for name in ['', '.', '\\', 'a', 'a.', 'a\\', 'a.\\', 'a..b', '.a', 'a\\.b.example',
		'a\\046b.example', 'a\\000b.example', 'a\\255b.example', 'a\\999b.example',
		'a\\1', 'a\\12', 'é.test', 'a'.repeat(63)+'.test', 'a'.repeat(64)+'.test',
		'a.'.repeat(126)+'a', 'a.'.repeat(127)+'a']! {
		for class in [i32(1), -1, 65536]! { for kind in [i32(1), 16, 33, 65535, 65536]! {
			mut packet := [272]u8{}
			length := resolver_question(name.str, class, kind, unsafe { &packet[0] })
			if native != unsafe { nil } {
				mut reference := [272]u8{}
				expected := native(0, name.str, class, kind, unsafe { nil }, 0, unsafe { nil }, unsafe { &reference[0] }, 272)
				assert length == expected, name
				if length > 0 { assert C.memcmp(unsafe { &packet[2] }, unsafe { &reference[2] }, usize(length - 2)) == 0, name }
			}
			if name in ['a..b', '.a', 'a\\999b.example', 'a\\1', 'a\\12', 'a'.repeat(64)+'.test', 'a.'.repeat(127)+'a'] { assert length == -1 }
			else { assert length >= 17 && length <= 271 }
		} }
	}
	assert resolver_question(unsafe { nil }, 1, 33, unsafe { nil }) == -1
}

fn rq_no_send(_ &u8, _ i32, _ &u8, _ i32) i32 { panic('invalid query reached transport') }

fn rq_fake_send(packet &u8, length i32, answer &u8, capacity i32) i32 {
	assert length >= 17 && capacity >= 12
	assert unsafe { packet[2] == 1 && packet[3] == 0 && packet[5] == 1 }
	mode := unsafe { packet[13] }
	if mode == `t` { $if linux { darwin_set_errno(0) } $else { darwin_set_errno(60) }; return -1 }
	if mode == `e` {
		$if linux { darwin_set_errno(111) } $else { darwin_set_errno(61) }
		return -1
	}
	mut response := [512]u8{}
	unsafe { C.memcpy(&response[0], packet, usize(length)) }
	response[2] = 0x81; response[3] = if mode >= `0` && mode <= `9` { mode - `0` } else { u8(0) }
	response[7] = if mode == `n` { u8(0) } else { u8(1) }
	copied := if capacity < 512 { capacity } else { i32(512) }
	unsafe { C.memcpy(answer, &response[0], usize(copied)) }
	return if mode == `s` { i32(8) } else { i32(512) }
}

fn rq_guarded() {
	page := u64(C.getpagesize())
	region := u64(C.mmap(unsafe { nil }, usize(page * 20), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	assert C.mprotect(unsafe { voidptr(region + page) }, usize(page * 17), C.PROT_READ | C.PROT_WRITE) == 0
	end := region + page * 18
	for capacity in [i32(0), 1, 3, 4, 7, 8, 11, 12, 13, 31, 512, 65535]! {
		answer := unsafe { &u8(end - u64(capacity)) }
		for mode in ['0', '1', '2', '3', '4', '5', '9', 'n', 'e', 's', 't']! {
			if capacity > 0 { unsafe { C.memset(answer, 0xa5, usize(capacity)) } }
			unsafe { *(answer - 1) = 0x5a; C.h_errno = 177 }
			darwin_set_errno(13)
			name := mode + '.test'
			status := resolver_query_send(name.str, 1, 33, answer, capacity, rq_fake_send)
			assert unsafe { *(answer - 1) } == 0x5a
			if capacity < 12 {
				assert status == -1 && C.h_errno == 2 && unsafe { *C.ios_errno_address() } == 22
				for i in 0 .. capacity { assert unsafe { answer[i] } == if i == 3 { u8(0xa0) } else { u8(0xa5) } }
			} else if mode == '0' { assert status == 512 && C.h_errno == 177 && unsafe { *C.ios_errno_address() } == 13 }
			else {
				expected := match mode { '2', 'e', 's', 't' { i32(2) } '3' { i32(1) } 'n' { i32(4) } else { i32(3) } }
				assert status == -1 && C.h_errno == expected
				if mode == 'e' { assert unsafe { *C.ios_errno_address() } == 61 }
				if mode == 't' { assert unsafe { *C.ios_errno_address() } == 60 }
			}
		}
	}
	// Presentation strings end at a guard page, including truncated escapes.
	for text in ['a', '.', 'a\\', 'a\\12', 'a\\255.test', 'a'.repeat(64)]! {
		name := end - u64(text.len + 1)
		unsafe { C.memcpy(voidptr(name), text.str, usize(text.len + 1)) }
		assert C.mprotect(unsafe { voidptr(region + page) }, usize(page * 17), C.PROT_READ) == 0
		mut packet := [272]u8{}
		resolver_question(unsafe { &char(name) }, 1, 33, unsafe { &packet[0] })
		assert C.mprotect(unsafe { voidptr(region + page) }, usize(page * 17), C.PROT_READ | C.PROT_WRITE) == 0
	}
	mut answer := [16]u8{}
	for name in ['a..b', 'a'.repeat(64), 'a\\999']! {
		assert resolver_query_send(name.str, 1, 33, unsafe { &answer[0] }, 16, rq_no_send) == -1
		assert C.h_errno == 3 && unsafe { *C.ios_errno_address() } == 40
	}
	assert darwin_res_query(unsafe { nil }, 1, 33, unsafe { &answer[0] }, 16) == -1
	assert C.h_errno == 3 && unsafe { *C.ios_errno_address() } == 22
	assert darwin_res_query(c'test', 1, 33, unsafe { nil }, 16) == -1
	assert darwin_res_query(c'test', 1, 33, unsafe { &answer[0] }, -1) == -1
	assert C.munmap(unsafe { voidptr(region) }, usize(page * 20)) == 0
}

fn rq_read(fd i32, data &u8, length int) {
	mut at := 0
	for at < length { n := C.recv(fd, unsafe { data + at }, usize(length - at), 0); assert n > 0; at += int(n) }
}

fn rq_write(fd i32, data &u8, length int) {
	mut at := 0
	for at < length { n := C.send(fd, unsafe { data + at }, usize(length - at), 0); assert n > 0; at += int(n) }
}

fn rq_response(mut packet [65535]u8, length int, rcode u8, answers bool, large bool) int {
	packet[2] = 0x81; packet[3] = 0x80 | rcode; packet[6] = 0; packet[7] = if answers { u8(1) } else { u8(0) }
	if !answers || rcode != 0 { return length }
	kind := u16(packet[length - 4]) << 8 | packet[length - 3]
	packet[length] = 0xc0; packet[length + 1] = 12
	packet[length + 2] = u8(kind >> 8); packet[length + 3] = u8(kind); packet[length + 5] = 1; packet[length + 9] = 60
	if kind == 33 {
		packet[length + 11] = 19
		packet[length + 15] = 10; packet[length + 16] = 1; packet[length + 17] = 0xbb
		for i, byte in [u8(6), `s`, `e`, `r`, `v`, `e`, `r`, 4, `t`, `e`, `s`, `t`, 0]! { packet[length + 18 + i] = byte }
		return length + 31
	}
	total := if large { 65535 } else { length + 17 }
	data_length := total - length - 12
	packet[length + 10] = u8(data_length >> 8); packet[length + 11] = u8(data_length)
	mut at := length + 12
	for at < total {
		count := if total - at > 256 { 255 } else { total - at - 1 }
		packet[at] = u8(count); at++
		for _ in 0 .. count { packet[at] = `X`; at++ }
	}
	return total
}

fn rq_server(udp i32, tcp i32, rcode u8, answers bool, large bool) {
	mut packet := [65535]u8{}
	mut peer := [16]u64{}; mut size := u32(128)
	n := int(C.recvfrom(udp, unsafe { &packet[0] }, 65535, 0, unsafe { voidptr(&peer[0]) }, unsafe { &size }))
	assert n >= 17 && packet[2] & 1 == 1 && packet[5] == 1
	if large {
		packet[2] = 0x83; packet[3] = 0x80
		assert C.sendto(udp, unsafe { &packet[0] }, usize(n), 0, unsafe { voidptr(&peer[0]) }, size) == n
		fd := i32(C.accept(tcp, unsafe { nil }, unsafe { nil })); assert fd >= 0
		mut prefix := [2]u8{}; rq_read(fd, unsafe { &prefix[0] }, 2)
		length := int(prefix[0]) * 256 + int(prefix[1]); assert length >= 17 && length < 272
		rq_read(fd, unsafe { &packet[0] }, length)
		written := rq_response(mut packet, length, rcode, answers, true)
		prefix[0] = u8(written >> 8); prefix[1] = u8(written)
		rq_write(fd, unsafe { &prefix[0] }, 2); rq_write(fd, unsafe { &packet[0] }, written)
		assert C.close(fd) == 0
	} else {
		written := rq_response(mut packet, n, rcode, answers, false)
		assert C.sendto(udp, unsafe { &packet[0] }, usize(written), 0, unsafe { voidptr(&peer[0]) }, size) == written
	}
}

fn rq_network(query RQQuery, native bool) {
	udp := i32(C.socket(C.AF_INET, C.SOCK_DGRAM, 0)); tcp := i32(C.socket(C.AF_INET, C.SOCK_STREAM, 0))
	assert udp >= 0 && tcp >= 0
	mut address := [4]u64{}
	$if macos { write32(u64(unsafe { &address[0] }), 0x210) }
	$else { write32(u64(unsafe { &address[0] }), u32(C.AF_INET)); unsafe { *(&u16(u64(&address[0]) + 2)) = C.htons(53) } }
	write32(u64(unsafe { &address[0] }) + 4, 0x0100007f)
	assert C.bind(udp, unsafe { voidptr(&address[0]) }, 16) == 0
	mut size := u32(16); assert C.getsockname(udp, unsafe { voidptr(&address[0]) }, unsafe { &size }) == 0
	assert C.bind(tcp, unsafe { voidptr(&address[0]) }, 16) == 0 && C.listen(tcp, 1) == 0
	$if macos {
		handle := C.dlopen(c'/usr/lib/libresolv.9.dylib', 2); assert handle != unsafe { nil }
		assert unsafe { RQInit(C.dlsym(handle, c'res_9_init'))() } == 0
		state := unsafe { RQState(C.dlsym(handle, c'__res_9_state'))() }
		write32(u64(state), 1); write32(u64(state) + 4, 1)
		unsafe { RQServers(C.dlsym(handle, c'res_9_setservers'))(state, &address[0], 1) }
		assert C.dlclose(handle) == 0
	}
	for pair in [[u8(0), 0]!, [u8(0), 1]!, [u8(1), 0]!, [u8(3), 0]!, [u8(15), 1]!]! {
		for capacity in [i32(61), 65535]! {
			job := spawn rq_server(udp, tcp, pair[0], pair[1] == 1, false)
			mut answer := [65536]u8{}; answer[capacity] = 0xa5
			unsafe { C.h_errno = 177 }; darwin_set_errno(13)
			status := query(c'fixture.test', 1, 33, unsafe { &answer[0] }, capacity)
			job.wait()
			assert answer[capacity] == 0xa5
			$if linux {
				// musl retries/discards these replies instead of returning them.
				if pair[0] !in [u8(0), 3]! {
					error_number := unsafe { *C.ios_errno_address() }
					assert status == -1 && C.h_errno == 2 && error_number == 60, 'rcode=${pair[0]} status=${status} errno=${error_number}'
					continue
				}
			}
			if pair[0] == 0 && pair[1] == 1 { assert status == 61 && C.h_errno == 177 }
			else { assert status == -1 && C.h_errno == match pair[0] { 0 { i32(4) } 3 { i32(1) } else { i32(3) } } }
			assert answer[3] & 15 == pair[0]
		}
	}
	job := spawn rq_server(udp, tcp, 0, true, true)
	mut large := [65536]u8{}; large[65535] = 0xa5
	assert query(c'fixture.test', 1, 16, unsafe { &large[0] }, 65535) == 65535
	job.wait(); assert large[65535] == 0xa5 && large[7] == 1 && large[65534] == `X`
	assert C.close(udp) == 0 && C.close(tcp) == 0
	println('IOS-RESOLVER-QUERY-WIRE: '+if native { 'native Mac' } else { 'V' }+' SRV replies, DNS errors, bounded UDP responses and 65535-byte TCP fallback')
}

fn rq_worker() {
	mut answer := [512]u8{}
	for _ in 0 .. 128 { assert resolver_query_send(c'0.test', 1, 33, unsafe { &answer[0] }, 512, rq_fake_send) == 512 }
}

fn test_resolver_query() {
	$if macos {
		handle := C.dlopen(c'/usr/lib/libresolv.9.dylib', 2); assert handle != unsafe { nil }
		rq_names(unsafe { RQMake(C.dlsym(handle, c'res_9_mkquery')) })
		rq_network(unsafe { RQQuery(C.dlsym(handle, c'res_9_query')) }, true)
		rq_network(darwin_res_query, false)
		assert C.dlclose(handle) == 0
	}
	$if linux { if os.exists('/opt/ios/check-mode') { rq_network(darwin_res_query, false) } }
	rq_names(unsafe { nil }); rq_guarded()
	mut jobs := []thread{}
	for _ in 0 .. 8 { jobs << spawn rq_worker() }; jobs.wait(); unsafe { jobs.free() }
	objc_start()
	entry := runtime_symbol('/usr/lib/libresolv.9.dylib', '_res_9_query') or { panic(err) }
	assert entry == u64(unsafe { voidptr(darwin_res_query) })
	for library in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libz.1.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! { if _ := runtime_symbol(library, '_res_9_query') { assert false } }
	if _ := resolver_query_symbol('_res_9_search') { assert false }
	objc_stop()
	println('IOS-RESOLVER-QUERY: scoped C ABI, native BIND name encoding and error semantics, guarded inputs/outputs, wire-format SRV data, UDP/TCP interoperability, 16-bit class/type conversion and eight workers')
}
