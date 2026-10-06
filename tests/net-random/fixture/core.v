// SPDX-License-Identifier: GPL-2.0-or-later
// Independent deterministic network randomness oracle; original checks remain.
@[has_globals]
module fixture

#include <net-random-native-abi.h>

fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.printf(&char, ...) i32
fn C.vinix_siphash24(&u8, voidptr, usize) u64
fn C.vinix_ip_randomid() u16
fn C.vinix_tcp_isn_at(u64, u32, u16, u32, u16) u32
fn C.vinix_tcp_isn6_at(u64, &u32, u16, &u32, u16) u32
fn C.vinix_tcp_isn_bytes(voidptr, u16, voidptr, u16, u32) u32
fn C.vinix_net_random_uniform(u32) u32
fn C.vinix_net_random() u32
fn C.vinix_net_random_bytes(voidptr, usize)
fn C.vinix_pick_port(u16, u16, fn (u16, voidptr) i32, voidptr) u16
fn C.nrf_port_taken(u16, voidptr) i32
fn C.nrf_single_port_taken(u16, voidptr) i32

__global nrf_generator_state u64 = 0x243f6a8885a308d3
__global nrf_requests u64
__global nrf_generator_enabled bool = true
__global nrf_failures i32
__global nrf_last_seen [65536]i32
__global nrf_taken [65536]bool

@[export: 'krandom__fill']
pub fn fill(buf voidptr, count u64, allow_insecure bool) bool {
	unsafe {
		mut out := &u8(buf)
		mut remaining := count
		nrf_requests++
		if !nrf_generator_enabled { return false }
		for remaining != 0 {
			nrf_generator_state += u64(0x9e3779b97f4a7c15)
			mut z := nrf_generator_state
			z = (z ^ (z >> 30)) * u64(0xbf58476d1ce4e5b9)
			z = (z ^ (z >> 27)) * u64(0x94d049bb133111eb)
			z ^= z >> 31
			take := if remaining < 8 { usize(remaining) } else { usize(8) }
			C.memcpy(out, &z, take)
			out += take
			remaining -= take
		}
	}
	return true
}

@[export: 'time__monotonic_ns']
pub fn monotonic_ns() u64 { return 0 }

fn check(ok bool, what &char) {
	if !ok {
		C.printf(c'FAIL: %s\n', what)
		nrf_failures++
	}
}

fn test_siphash() {
	unsafe {
		mut key := [16]u8{}
		mut message := [15]u8{}
		for i in 0 .. 16 { key[i] = u8(i) }
		for i in 0 .. 15 { message[i] = u8(i) }
		check(C.vinix_siphash24(&key[0], &message[0], 15) == u64(0xa129ca6149be45e5), c'siphash: 15 bytes')
		check(C.vinix_siphash24(&key[0], &message[0], 0) == u64(0x726fdb47dd0e0e31), c'siphash: empty')
	}
}

fn test_siphash_lengths_and_alignment() {
	unsafe {
		mut key := [32]u8{}
		mut message := [80]u8{}
		for offset in 0 .. 16 {
			for i in 0 .. 16 { key[offset + i] = u8(i) }
			for i in 0 .. 64 { message[offset + i] = u8(i) }
			for n in 0 .. 64 {
				check(C.vinix_siphash24(&key[offset], &message[offset], usize(n)) == vectors[n], c'siphash: tail length or unaligned input')
			}
		}
		for i in 0 .. 16 { key[i] = u8(i) }
		check(C.vinix_siphash24(&key[0], nil, 0) == vectors[0], c'siphash: empty null input')
	}
}

fn test_ids() {
	unsafe {
		mut consecutive := i32(0)
		mut closest := i32(4 * 65536)
		mut previous := u16(0)
		for i in 0 .. 65536 { nrf_last_seen[i] = -1 }
		for i := i32(0); i < 4 * 65536; i++ {
			id := C.vinix_ip_randomid()
			check(id != 0, c'ip id: 0 handed out')
			if nrf_last_seen[id] >= 0 && i - nrf_last_seen[id] < closest {
				closest = i - nrf_last_seen[id]
			}
			nrf_last_seen[id] = i
			if i > 0 && id == u16(previous + 1) { consecutive++ }
			previous = id
		}
		check(closest >= 32768, c'ip id: reused within 32768 datagrams')
		check(consecutive < 32, c'ip id: in sequence')
		C.printf(c'ip id: closest reuse after %d, %d in sequence of %d\n', closest, consecutive, i32(4 * 65536))
	}
}

fn isn(now_ns u64, local_port u16) u32 {
	return C.vinix_tcp_isn_at(now_ns, 0x0f02000a, local_port, 0x0202000a, 80)
}

fn test_isn() {
	mut close := i32(0)
	check(isn(4000 * 1000, 50000) - isn(0, 50000) == 1000, c'isn: 4 microsecond clock')
	check(isn(4000, 50000) == isn(7999, 50000), c'isn: clock granularity')
	for port := u16(49152); port < 50152; port++ {
		gap := isn(0, port + 1) - isn(0, port)
		if gap < (u32(1) << 24) || gap > ~(u32(1) << 24) { close++ }
	}
	check(close < 40, c'isn: neighbouring ports start close together')
	check(C.vinix_tcp_isn_at(0, 0x0f02000a, 50000, 0x0302000a, 80) != isn(0, 50000), c'isn: remote address left out')
	check(C.vinix_tcp_isn_at(0, 0x0f02000a, 50000, 0x0202000a, 443) != isn(0, 50000), c'isn: remote port left out')
	C.printf(c'isn: %d of 1000 neighbouring ports within 2^24\n', close)
}

fn test_isn6() {
	unsafe {
		mut local := [u32(0x01000020), 0, 0, 1]!
		mut remote := [u32(0x01000020), 0, 0, 2]!
		original := C.vinix_tcp_isn6_at(0, &local[0], 50000, &remote[0], 80)
		check(C.vinix_tcp_isn6_at(4000000, &local[0], 50000, &remote[0], 80) - original == 1000, c'isn6: clock')
		for word in 0 .. 4 {
			local[word] ^= 0x00008000
			check(C.vinix_tcp_isn6_at(0, &local[0], 50000, &remote[0], 80) != original, c'isn6: local address word omitted')
			local[word] ^= 0x00008000
			remote[word] ^= 0x00008000
			check(C.vinix_tcp_isn6_at(0, &local[0], 50000, &remote[0], 80) != original, c'isn6: remote address word omitted')
			remote[word] ^= 0x00008000
		}
		check(C.vinix_tcp_isn6_at(0, &local[0], 50001, &remote[0], 80) != original, c'isn6: local port')
		check(C.vinix_tcp_isn6_at(0, &local[0], 50000, &remote[0], 81) != original, c'isn6: remote port')
	}
}

@[export: 'nrf_port_taken']
pub fn port_taken(port u16, context voidptr) i32 {
	return unsafe { if nrf_taken[port] { i32(1) } else { i32(0) } }
}

fn test_ports() {
	unsafe {
		mut consecutive := i32(0)
		mut previous := u16(0)
		for i in 0 .. 2000 {
			port := C.vinix_pick_port(C.VINIX_EPHEMERAL_FIRST, C.VINIX_EPHEMERAL_LAST, C.nrf_port_taken, nil)
			check(port >= C.VINIX_EPHEMERAL_FIRST, c'ports: below the range')
			if i > 0 && (u32(port) == u32(previous) + 1 || port == previous) { consecutive++ }
			previous = port
		}
		check(consecutive < 10, c'ports: in sequence')
		for port in C.VINIX_EPHEMERAL_FIRST .. C.VINIX_EPHEMERAL_LAST + 1 { nrf_taken[port] = true }
		nrf_taken[51000] = false
		for _ in 0 .. 64 {
			check(C.vinix_pick_port(C.VINIX_EPHEMERAL_FIRST, C.VINIX_EPHEMERAL_LAST, C.nrf_port_taken, nil) == 51000, c'ports: the one free port missed')
		}
		nrf_taken[51000] = true
		check(C.vinix_pick_port(C.VINIX_EPHEMERAL_FIRST, C.VINIX_EPHEMERAL_LAST, C.nrf_port_taken, nil) == 0, c'ports: none free')
		C.printf(c'ports: %d of %d picks next to the one before\n', consecutive, i32(2000))
	}
}

fn test_uniform() {
	unsafe {
		mut counts := [3]i32{}
		for _ in 0 .. 30000 {
			value := C.vinix_net_random_uniform(3)
			check(value < 3, c'uniform: out of range')
			if value < 3 { counts[value]++ }
		}
		for i in 0 .. 3 { check(counts[i] > 9000 && counts[i] < 11000, c'uniform: skewed') }
		check(C.vinix_net_random_uniform(1) == 0 && C.vinix_net_random_uniform(0) == 0, c'uniform: degenerate bounds')
	}
}

fn test_pooling() {
	before := nrf_requests
	for _ in 0 .. 64 { C.vinix_net_random() }
	check(nrf_requests - before <= 2, c'pool: the generator asked for every value')
}

fn test_pool_boundaries_and_fallback() {
	unsafe {
		mut output := [1026]u8{}
		lengths := [usize(0), 1, 255, 256, 257, 511, 512, 513, 1024]!
		for i in 0 .. lengths.len {
			C.memset(&output[0], 0xa5, sizeof(output))
			C.vinix_net_random_bytes(&output[1], lengths[i])
			check(output[0] == 0xa5 && output[lengths[i] + 1] == 0xa5, c'pool: output bounds')
		}
		before := nrf_requests
		C.vinix_net_random_bytes(nil, 0)
		check(nrf_requests == before, c'pool: empty request refilled')
		nrf_generator_enabled = false
		C.memset(&output[0], 0xa5, sizeof(output))
		C.vinix_net_random_bytes(&output[1], 1024)
		check(nrf_requests > before, c'pool: fallback not reached')
		check(output[0] == 0xa5 && output[1025] == 0xa5, c'pool: fallback bounds')
		mut combined := u32(0)
		for i in 1 .. 1025 { combined |= output[i] }
		check(combined != 0, c'pool: fallback returned only zeros')
		nrf_generator_enabled = true
	}
}

fn test_uniform_large_bounds() {
	unsafe {
		bounds := [u32(2), 3, 256, 65535, 0x80000000, 0x80000001, 0xffffffff]!
		for i in 0 .. bounds.len {
			for _ in 0 .. 1000 {
				check(C.vinix_net_random_uniform(bounds[i]) < bounds[i], c'uniform: large unsigned bound')
			}
		}
		check(C.vinix_tcp_isn_bytes(nil, 0, nil, 0, 0) == 0 && C.vinix_tcp_isn_bytes(nil, 0, nil, 0, 15) == 0, c'isn: invalid address length')
	}
}

@[export: 'nrf_single_port_taken']
pub fn single_port_taken(port u16, context voidptr) i32 {
	check(port == u16(0xffff), c'ports: inclusive upper endpoint')
	return unsafe { *(&i32(context)) }
}

fn test_port_callback_context() {
	unsafe {
		mut occupied := i32(0)
		check(C.vinix_pick_port(u16(0xffff), u16(0xffff), C.nrf_single_port_taken, &occupied) == u16(0xffff), c'ports: one-port range')
		occupied = -1
		check(C.vinix_pick_port(u16(0xffff), u16(0xffff), C.nrf_single_port_taken, &occupied) == 0, c'ports: negative callback result means occupied')
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		test_siphash()
		test_siphash_lengths_and_alignment()
		test_ids()
		test_isn()
		mut local6 := [16]u8{}
		mut remote6 := [16]u8{}
		local6[0] = 0x20
		local6[1] = 1
		local6[2] = 0x0d
		local6[3] = 0xb8
		remote6[0] = 0x20
		remote6[1] = 1
		remote6[2] = 0x0d
		remote6[3] = 0xb8
		first6 := C.vinix_tcp_isn_bytes(&local6[0], 50000, &remote6[0], 443, 16)
		for i in 0 .. 16 {
			remote6[i] ^= 1
			check(first6 != C.vinix_tcp_isn_bytes(&local6[0], 50000, &remote6[0], 443, 16), c'isn: IPv6 remote address byte left out')
			remote6[i] ^= 1
			local6[i] ^= 1
			check(first6 != C.vinix_tcp_isn_bytes(&local6[0], 50000, &remote6[0], 443, 16), c'isn: IPv6 local address byte left out')
			local6[i] ^= 1
		}
		check(first6 != C.vinix_tcp_isn_bytes(&local6[0], 50000, &remote6[0], 443, 4), c'isn: IPv4 and IPv6 tuples not separated')
		test_isn6()
		test_ports()
		test_uniform()
		test_pooling()
		test_uniform_large_bounds()
		test_port_callback_context()
		test_pool_boundaries_and_fallback()
		if nrf_failures != 0 {
			C.printf(c'net-random: %d failures\n', nrf_failures)
			return 1
		}
		C.printf(c'net-random: PASS\n')
	}
	return 0
}
