// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module inet

// Keep the lwIP-facing C ABI. Callers serialize through the network lock.
// These hooks also let host tests compile this file without the kernel.
fn C.krandom__fill(buf voidptr, count u64, allow_insecure bool) bool
fn C.time__monotonic_ns() u64
fn C.vinix_explicit_bzero(buf voidptr, len usize)
fn C.memcpy(dest voidptr, src voidptr, length usize) voidptr

__global (
	net_pool           [256]u8
	net_pool_left      usize
	net_fallback_state u64
	net_id_shuffle     [65536]u16
	net_id_index       u32
	net_id_shuffled    bool
	net_isn_key        [16]u8
	net_isn_keyed      bool
)

fn net_cycle_counter() u64 {
	$if amd64 {
		mut low := u32(0)
		mut high := u32(0)
		asm volatile amd64 {
			rdtsc
			; =a (low)
			  =d (high)
		}
		return (u64(high) << 32) | u64(low)
	} $else $if arm64 {
		mut value := u64(0)
		asm volatile aarch64 {
			mrs value, CNTVCT_EL0
			; =r (value)
		}
		return value
	} $else {
		return 0
	}
}

fn net_refill() {
	net_pool_left = sizeof(net_pool)
	if C.krandom__fill(unsafe { &net_pool[0] }, sizeof(net_pool), true) {
		return
	}
	// Only used before inet.initialise() has initialized the generator.
	for i := 0; i < net_pool.len; i += 8 {
		net_fallback_state += u64(0x9e3779b97f4a7c15)
		mut word := net_fallback_state ^ net_cycle_counter()
		word = (word ^ (word >> 30)) * u64(0xbf58476d1ce4e5b9)
		word = (word ^ (word >> 27)) * u64(0x94d049bb133111eb)
		word ^= word >> 31
		unsafe { C.memcpy(&net_pool[i], &word, 8) }
	}
}

// Batch small requests, clearing every byte as it leaves the pool, as
// arc4random does. No caller can recover earlier output from the pool.
@[export: 'vinix_net_random_bytes']
fn net_random_bytes(out voidptr, length usize) {
	mut remaining := length
	mut target := usize(out)
	for remaining != 0 {
		if net_pool_left == 0 {
			net_refill()
		}
		take := if remaining < net_pool_left { remaining } else { net_pool_left }
		unsafe {
			from := &net_pool[sizeof(net_pool) - net_pool_left]
			C.memcpy(voidptr(target), from, take)
			C.vinix_explicit_bzero(from, take)
		}
		target += take
		remaining -= take
		net_pool_left -= take
	}
}

@[export: 'vinix_net_random']
fn net_random() u32 {
	mut value := u32(0)
	net_random_bytes(unsafe { &value }, sizeof(value))
	return value
}

// arc4random_uniform(3): reject the biased portion of the 32-bit range.
@[export: 'vinix_net_random_uniform']
fn net_random_uniform(upper_bound u32) u32 {
	if upper_bound < 2 {
		return 0
	}
	minimum := (u32(0) - upper_bound) % upper_bound
	for {
		value := net_random()
		if value >= minimum {
			return value % upper_bound
		}
	}
	return 0
}

// OpenBSD's ip_randomid(): shuffle every ID once, then swap each draw into
// a random slot among the preceding 32768. Skip zero, and never reuse an ID
// within 32768 datagrams, so fragments of different datagrams stay apart.
@[export: 'vinix_ip_randomid']
fn net_ip_randomid() u16 {
	if !net_id_shuffled {
		// Knuth's inside-out shuffle fills the table as it goes.
		for i := u32(0); i < 65536; i++ {
			j := net_random_uniform(i + 1)
			unsafe {
				net_id_shuffle[i] = net_id_shuffle[j]
				net_id_shuffle[j] = u16(i)
			}
		}
		net_id_shuffled = true
	}
	for {
		mut step := u16(0)
		net_random_bytes(unsafe { &step }, sizeof(step))
		i := net_id_index & 0xffff
		j := (net_id_index - u32(step & 0x7fff)) & 0xffff
		id := unsafe { net_id_shuffle[i] }
		unsafe {
			net_id_shuffle[i] = net_id_shuffle[j]
			net_id_shuffle[j] = id
		}
		net_id_index++
		if id != 0 {
			return id
		}
	}
	return 0
}

// RFC 6528: a 4-microsecond clock plus SipHash-2-4 of the connection tuple
// under a secret key. Hash all address bytes; the tuple length separates
// IPv4 and IPv6. Preserve the C bridge's raw address/port byte order.
fn net_tuple_isn(now_ns u64, local voidptr, local_port u16, remote voidptr,
	remote_port u16, length usize) u32 {
	if !net_isn_keyed {
		net_random_bytes(unsafe { &net_isn_key[0] }, sizeof(net_isn_key))
		net_isn_keyed = true
	}
	mut tuple := [36]u8{}
	unsafe {
		C.memcpy(&tuple[0], local, length)
		C.memcpy(&tuple[length], remote, length)
		C.memcpy(&tuple[length * 2], &local_port, 2)
		C.memcpy(&tuple[length * 2 + 2], &remote_port, 2)
		return u32(now_ns / 4000) + u32(net_siphash24(&net_isn_key[0], &tuple[0],
			length * 2 + 4))
	}
}

@[export: 'vinix_tcp_isn_at']
fn net_tcp_isn_at(now_ns u64, local_address u32, local_port u16,
	remote_address u32, remote_port u16) u32 {
	return net_tuple_isn(now_ns, unsafe { &local_address }, local_port,
		unsafe { &remote_address }, remote_port, 4)
}

@[export: 'vinix_tcp_isn']
fn net_tcp_isn(local_address u32, local_port u16, remote_address u32,
	remote_port u16) u32 {
	return net_tcp_isn_at(C.time__monotonic_ns(), local_address, local_port,
		remote_address, remote_port)
}

@[export: 'vinix_tcp_isn_bytes']
fn net_tcp_isn_bytes(local voidptr, local_port u16, remote voidptr,
	remote_port u16, length u32) u32 {
	if length != 4 && length != 16 {
		return 0
	}
	return net_tuple_isn(C.time__monotonic_ns(), local, local_port, remote,
		remote_port, usize(length))
}

@[export: 'vinix_tcp_isn6_at']
fn net_tcp_isn6_at(now_ns u64, local_address &u32, local_port u16,
	remote_address &u32, remote_port u16) u32 {
	return net_tuple_isn(now_ns, local_address, local_port, remote_address, remote_port, 16)
}

@[export: 'vinix_tcp_isn6']
fn net_tcp_isn6(local_address &u32, local_port u16, remote_address &u32,
	remote_port u16) u32 {
	return net_tcp_isn6_at(C.time__monotonic_ns(), local_address, local_port,
		remote_address, remote_port)
}

type NetPortTaken = fn (u16, voidptr) i32

// OpenBSD's in_pcbpickport(): random starting port, then probe the inclusive
// range with wraparound. Zero means every port is already bound.
@[export: 'vinix_pick_port']
fn net_pick_port(first u16, last u16, taken NetPortTaken, context voidptr) u16 {
	count := u32(last) - u32(first) + 1
	mut candidate := u32(first) + net_random_uniform(count)
	for tried := u32(0); tried < count; tried++ {
		if taken(u16(candidate), context) == 0 {
			return u16(candidate)
		}
		candidate = if candidate == u32(last) { u32(first) } else { candidate + 1 }
	}
	return 0
}

@[inline]
fn net_load64(input &u8) u64 {
	mut value := u64(0)
	for i := 7; i >= 0; i-- {
		value = (value << 8) | unsafe { u64(input[i]) }
	}
	return value
}

@[inline]
fn net_rotl64(value u64, bits u32) u64 {
	return (value << bits) | (value >> (64 - bits))
}

struct NetSipState {
mut:
	v0 u64
	v1 u64
	v2 u64
	v3 u64
}

@[inline]
fn (mut state NetSipState) round() {
	state.v0 += state.v1
	state.v1 = net_rotl64(state.v1, 13) ^ state.v0
	state.v0 = net_rotl64(state.v0, 32)
	state.v2 += state.v3
	state.v3 = net_rotl64(state.v3, 16) ^ state.v2
	state.v0 += state.v3
	state.v3 = net_rotl64(state.v3, 21) ^ state.v0
	state.v2 += state.v1
	state.v1 = net_rotl64(state.v1, 17) ^ state.v2
	state.v2 = net_rotl64(state.v2, 32)
}

// SipHash-2-4 (Aumasson and Bernstein), with a 64-bit result and borrowed
// buffers. Unaligned input and the final short block use byte loads only.
@[export: 'vinix_siphash24']
fn net_siphash24(key &u8, data voidptr, length usize) u64 {
	k0 := net_load64(key)
	k1 := net_load64(unsafe { key + 8 })
	mut state := NetSipState{
		v0: u64(0x736f6d6570736575) ^ k0
		v1: u64(0x646f72616e646f6d) ^ k1
		v2: u64(0x6c7967656e657261) ^ k0
		v3: u64(0x7465646279746573) ^ k1
	}
	input := unsafe { &u8(data) }
	whole := length & ~usize(7)
	for at := usize(0); at < whole; at += 8 {
		word := net_load64(unsafe { input + at })
		state.v3 ^= word
		state.round()
		state.round()
		state.v0 ^= word
	}
	mut last := u64(length) << 56
	for i := usize(0); i < length & 7; i++ {
		last |= unsafe { u64(input[whole + i]) } << (8 * i)
	}
	state.v3 ^= last
	state.round()
	state.round()
	state.v0 ^= last
	state.v2 ^= 0xff
	for _ in 0 .. 4 {
		state.round()
	}
	return state.v0 ^ state.v1 ^ state.v2 ^ state.v3
}
