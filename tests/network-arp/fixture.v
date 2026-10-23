// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <lwip/init.h>
#include <lwip/etharp.h>
#include <lwip/stats.h>

struct C.ip4_addr {
mut:
	addr u32
}

struct C.pbuf {}

struct C.netif {
mut:
	ip_addr    C.ip_addr
	hwaddr     [6]u8
	hwaddr_len u8
	linkoutput fn (&C.netif, &C.pbuf) i8
	state      voidptr
}

struct C.ip_addr {
mut:
	u_addr C.ip_addr_union
}

union C.ip_addr_union {
	ip4 C.ip4_addr
}

struct C.stats_mem {
	used u32
}

struct C.stats_ {
	mem  C.stats_mem
	memp [64]&C.stats_mem
}

@[c_extern]
__global C.lwip_stats C.stats_

fn C.lwip_init()
fn C.pbuf_alloc(int, u16, int) &C.pbuf
fn C.pbuf_take(&C.pbuf, voidptr, u16) i8
fn C.pbuf_copy_partial(&C.pbuf, voidptr, u16, u16) u16
fn C.pbuf_free(&C.pbuf) u8
fn C.etharp_query(&C.netif, &C.ip4_addr, &C.pbuf) i8
fn C.etharp_input(&C.pbuf, &C.netif)
fn C.etharp_cleanup_netif(&C.netif)
fn C.etharp_tmr()

// Deterministic platform services for the unmodified production lwIP sources.
@[export: 'sys_now']
fn now() u32 { return 0 }

@[export: 'vinix_net_random']
fn random_word() u32 { return 0x12345678 }

@[export: 'vinix_tcp_isn']
fn isn(_a u32, _b u16, _c u32, _d u16) u32 { return 1 }

@[export: 'vinix_tcp_isn6']
fn isn6(_a &u32, _b u16, _c &u32, _d u16) u32 { return 1 }

@[export: 'vinix_lwip_assert']
fn lwip_assert(message &char, file &char, line int) {
	panic('${unsafe { cstring_to_vstring(file) }}:${line}: ${unsafe { cstring_to_vstring(message) }}')
}

struct Capture {
mut:
	packets []u8
}

fn transmit(netif &C.netif, packet &C.pbuf) i8 {
	mut bytes := [46]u8{}
	n := C.pbuf_copy_partial(packet, &bytes[0], bytes.len, 0)
	if n == bytes.len && bytes[12] == 8 && bytes[13] == 0 {
		mut capture := unsafe { &Capture(netif.state) }
		capture.packets << bytes[45]
	}
	return 0
}

fn queue(mut netif C.netif, address C.ip4_addr, tag u8) {
	// IP/UDP-shaped payloads, tagged like consecutive A and AAAA queries.
	mut bytes := [32]u8{}
	bytes[0] = 0x45
	bytes[9] = 17
	bytes[31] = tag
	packet := C.pbuf_alloc(C.PBUF_LINK, bytes.len, C.PBUF_RAM)
	assert packet != unsafe { nil }
	assert C.pbuf_take(packet, &bytes[0], bytes.len) == 0
	assert C.etharp_query(&netif, &address, packet) == 0
	C.pbuf_free(packet) // lwIP must own the retained reference.
}

fn reply(mut netif C.netif) {
	bytes := [u8(0), 1, 8, 0, 6, 4, 0, 2, 0x52, 0x55, 10, 0, 2, 3, 10, 0, 2, 3, 0x52, 0x54, 0,
		0x12, 0x34, 0x56, 10, 0, 2, 15]!
	packet := C.pbuf_alloc(C.PBUF_RAW, bytes.len, C.PBUF_RAM)
	assert packet != unsafe { nil }
	assert C.pbuf_take(packet, &bytes[0], bytes.len) == 0
	C.etharp_input(packet, &netif) // consumes the reply and flushes the queue.
}

fn allocations() u64 {
	mut used := u64(C.lwip_stats.mem.used)
	for i in 0 .. int(C.MEMP_MAX) { used += C.lwip_stats.memp[i].used }
	return used
}

fn main() {
	C.lwip_init()
	mut capture := Capture{}
	mut netif := C.netif{}
	netif.state = &capture
	netif.linkoutput = transmit
	netif.hwaddr = [u8(0x52), 0x54, 0, 0x12, 0x34, 0x56]!
	netif.hwaddr_len = 6
	unsafe { netif.ip_addr.u_addr.ip4.addr = 0x0f02000a }
	address := C.ip4_addr{ addr: 0x0302000a }
	baseline := allocations()
	queue(mut netif, address, 1)
	queue(mut netif, address, 28)
	assert capture.packets.len == 0
	reply(mut netif)
	assert capture.packets == [u8(1), 28], 'cold ARP lost a DNS packet: ${capture.packets}'
	C.etharp_cleanup_netif(&netif)
	assert allocations() == baseline
	for _ in 0 .. 200 {
		capture.packets.clear()
		for tag in 1 .. 9 { queue(mut netif, address, u8(tag)) }
		reply(mut netif)
		assert capture.packets == [u8(6), 7, 8], 'queue must remain bounded to three packets'
		C.etharp_cleanup_netif(&netif)
		assert allocations() == baseline, 'resolution leaked retained packets'
		queue(mut netif, address, 1)
		queue(mut netif, address, 28)
		for _ in 0 .. 6 { C.etharp_tmr() }
		assert allocations() == baseline, 'unanswered ARP leaked retained packets'
		queue(mut netif, address, 1)
		queue(mut netif, address, 28)
		C.etharp_cleanup_netif(&netif)
		assert allocations() == baseline, 'interface removal leaked retained packets'
	}
	println('ARP-QUEUE-PASS paired DNS, bounded queue, 200 resolution/expiry/removal cycles; allocations flat')
}
