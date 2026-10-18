// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <resolv.h>
#include <netdb.h>
$if macos {
	#flag -lresolv
}
__global C.h_errno i32
fn C.res_send(&u8, i32, &u8, i32) i32
type ResolverSend = fn (&u8, i32, &u8, i32) i32

// Encode presentation-format labels, including BIND's escaped dots and decimal
// octets. This is a DNS name, not a hostname: arbitrary label bytes are valid.
// The caller supplies 272 zeroed bytes (header + maximal DNS name + question).
fn resolver_question(name &char, class i32, kind i32, packet &u8) i32 {
	if name == unsafe { nil } { return -1 }
	mut at := u64(0)
	mut label := u32(12)
	mut end := u32(13)
	unsafe {
		if name[0] != 0 && !(name[0] == 46 && name[1] == 0) {
			for {
				mut byte := u8(name[at])
				if byte == 0 || byte == 46 {
					length := end - label - 1
					if length == 0 || length > 63 { return -1 }
					packet[label] = u8(length)
					if byte == 0 || name[at + 1] == 0 { break }
					label = end
					end++
					at++
					if end >= 267 { return -1 }
					continue
				}
				if byte == 92 {
					at++
					byte = u8(name[at])
					// BIND ignores a final backslash, including after the last dot.
					if byte == 0 {
						length := end - label - 1
						if length > 63 { return -1 }
						packet[label] = u8(length)
						if length == 0 { end = label }
						break
					}
					if byte >= 48 && byte <= 57 {
						mut decimal := u32(0)
						for _ in 0 .. 3 {
							digit := u8(name[at])
							if digit < 48 || digit > 57 { return -1 }
							decimal = decimal * 10 + digit - 48
							at++
						}
						if decimal > 255 { return -1 }
						byte = u8(decimal)
						at--
					}
				}
				if end >= 266 || end - label > 63 { return -1 }
				packet[end] = byte
				end++
				at++
			}
			if end >= 267 { return -1 }
			packet[end] = 0
			end++
		} else { packet[12] = 0 }
		packet[2] = 1 // Standard recursive query, one question, no EDNS record.
		packet[5] = 1
		packet[end] = u8(u32(kind) >> 8); packet[end + 1] = u8(kind)
		packet[end + 2] = u8(u32(class) >> 8); packet[end + 3] = u8(class)
	}
	return i32(end + 4)
}

fn resolver_query_send(name &char, class i32, kind i32, answer &u8, capacity i32, send ResolverSend) i32 {
	// BIND clears the response rcode before constructing the query. Restrict
	// that write to the supplied buffer even for invalid/short arguments.
	if answer != unsafe { nil } && capacity >= 4 { unsafe { answer[3] &= 0xf0 } }
	mut packet := [272]u8{}
	length := resolver_question(name, class, kind, unsafe { &packet[0] })
	if length < 0 {
		unsafe { C.h_errno = 3 }
		darwin_set_errno(if name == unsafe { nil } { 22 } else { 40 })
		return -1
	}
	if answer == unsafe { nil } || capacity < 12 {
		unsafe { C.h_errno = 2 }
		darwin_set_errno(22)
		return -1
	}
	if C.getentropy(unsafe { &packet[0] }, 2) != 0 {
		unsafe { C.h_errno = 2 }
		darwin_set_errno(darwin_native_error(unsafe { *C.ios_errno_address() }))
		return -1
	}
	// The existing libc resolver owns server selection, timeouts, UDP retries,
	// and TCP fallback. V owns the query wire format and BIND query semantics.
	result := send(unsafe { &packet[0] }, length, answer, capacity)
	if result < 0 {
		unsafe { C.h_errno = 2 }
		darwin_set_errno(resolver_transport_error())
		return -1
	}
	if result < 12 { unsafe { C.h_errno = 2 }; return -1 }
	rcode := unsafe { answer[3] & 15 }
	if rcode != 0 || unsafe { answer[6] == 0 && answer[7] == 0 } {
		unsafe { C.h_errno = match rcode { 0 { i32(4) } 2 { i32(2) } 3 { i32(1) } else { i32(3) } } }
		return -1
	}
	return result
}

fn darwin_res_query(name &char, class i32, kind i32, answer &u8, capacity i32) i32 {
	return resolver_query_send(name, class, kind, answer, capacity, resolver_native_send)
}

fn resolver_native_send(packet &u8, length i32, answer &u8, capacity i32) i32 {
	$if linux { darwin_set_errno(0) }
	return C.res_send(packet, length, answer, capacity)
}

fn resolver_transport_error() int {
	native := unsafe { *C.ios_errno_address() }
	// musl can time out without changing errno, or leave a transient socket
	// error from its nonblocking exchange. BIND reports ETIMEDOUT instead.
	$if linux { if native == 0 || native == C.EAGAIN || native == C.EINPROGRESS { return 60 } }
	return darwin_native_error(native)
}

fn resolver_query_symbol(symbol string) ?u64 {
	if symbol == '_res_9_query' { return u64(unsafe { voidptr(darwin_res_query) }) }
	return none
}
