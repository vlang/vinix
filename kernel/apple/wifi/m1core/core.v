@[translated]
module m1core
import apple.wifi.wificore as _
#include "brcm_m1.h"
#include "apple_platform_io.h"
#include <string.h>

#include <stddef.h>
#include <stdint.h>














// SPDX-License-Identifier: ISC
// *Experimental BCM4378 FullMAC PCIe driver for Vinix.
// *The caller owns the PCIe bw_m1_host, DART mapping, firmware files and serialization.
// *Firmware/DMA addresses are never CPU pointers. See tests/m1-wifi/README.md.
//

pub enum Bw_space {
	bw_config
	bw_regs
	bw_tcm
}

pub enum Bw_state {
	bw_off
	bw_chip
	bw_booting
	bw_ready
	bw_joining
	bw_link
	bw_fault
}

pub enum Bw_error {
	bw_ok      = 0
	bw_einval  = -1
	bw_enospc  = -2
	bw_eio     = -3
	bw_etime   = -4
	bw_eproto  = -5
	bw_enotsup = -6
	bw_enolink = -7
}

// Initialize software only. Pool must already be isolated by DART; bus master
// *remains disabled until platform code has established that isolation.

fn C.bw_init(arg &C.bw_device, arg_2 &C.bw_ops, cookie voidptr, pool_cpu voidptr, pool_dma u64, pool_len usize, registers_size u32, tcm_size u32) i32

// Probe only accesses the declared endpoint. Reads core inventory and OTP;
// *it does not upload firmware or turn on the radio.

fn C.bw_probe(arg &C.bw_device) i32

fn C.bw_start(arg &C.bw_device, arg_2 &C.bw_firmware) i32

fn C.bw_radio(arg &C.bw_device, enabled i32) i32

fn C.bw_scan(arg &C.bw_device) i32

fn C.bw_networks(arg &C.bw_device, output &u8, capacity usize) i32

fn C.bw_join_wpa2(arg &C.bw_device, ssid &u8, ssid_len usize, passphrase &u8, passphrase_len usize) i32

fn C.bw_disconnect(arg &C.bw_device) i32

fn C.bw_poll(arg &C.bw_device, budget u32) i32

fn C.bw_transmit(arg &C.bw_device, ethernet &u8, length usize) i32

fn C.bw_stop(arg &C.bw_device)

// Bounded, bw_m1_host-testable parsers. NVRAM input is board-specific text; output
// *includes double NUL, padding, and the Broadcom complement length token.

fn C.bw_nvram_pack(arg &u8, arg_2 usize, arg_3 &u8, arg_4 usize, arg_5 &usize) i32

fn C.bw_otp_parse(arg &u8, arg_2 usize, arg_3 &C.bw_otp) i32

fn C.bw_state_name(arg i32) &char

// SPDX-License-Identifier: GPL-2.0-or-later

// Private, kernel-only platform contract. All register pointers are mapped
// *Device memory. PCI window is the DT non-prefetchable 32-bit range.

pub struct C.bw_m1_plan {
pub mut:
	config          u64
	config_size     u64
	rc              u64
	port            u64
	phy             u64
	gpio            u64
	dart            u64
	window          u64
	window_bus      u64
	window_size     u64
	pool_cpu        u64
	pool_physical   u64
	tables_cpu      u64
	tables_physical u64
	sid             u32
	gpio_active_low u32
	calibration     &u8
	seed            &u8
	calibration_len usize
	seed_len        usize
	mac             [6]u8
	antenna         [16]char
}

// Fixed-size UAPI byte arrays, no embedded pointers. Integer fields LE.
// *STATUS: state@0,error@4,revision@8,dart_error@12,rx64@16,tx64@24,
// *        MAC@32,OTP module@40,vendor@56,revision@72,silicon@88,
// *        antenna@104,board@120 (32 bytes),drops64@152,
// *        radio_on@160,scanning@164,network_count@168,scan_error@172.
// *UPLOAD: part@0,total@4,offset@8,count@12,data[4096]@16.
// *        part 0 firmware,1 NVRAM text,2 CLM,3 TXCAP.
// *BOOT: revision@0,module[16]@8,vendor[16]@24,modrev[16]@40,
// *      antenna[16]@56,board[32]@72; other bytes MUST be zero.
// *JOIN: SSID length32@0,passphrase length32@4,SSID[32]@8,password[64]@40.
// *RADIO: enabled32@0; zero takes the firmware radio down, one brings it up.
// *SCAN: no argument; starts an asynchronous all-channel scan.
// *NETWORKS: version32@0,count32@4,scanning32@8,error32@12, then 32
// *          entries of 48 bytes: ssid_len8@0,secure8@1,channel16@2,
// *          rssi16@4,BSSID[6]@8,SSID[32]@16. Unused entries are zero.
//

// The memory and string routines are implemented in V, in lib/stubs, and
// exported under these names. V has no `const`, so these prototypes describe the
// definitions rather than the C standard's spelling: a qualifier the definition
// does not carry would be a conflicting declaration under
// `-target-libc-headers`, where V emits its own prototype for them too.
// Keep const-correct declarations for handwritten C and third-party callers.
// Only the generated V translation unit needs the unqualified definitions.
// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-or-later
// *Apple M1 PCIe/DART integration. Register sequences based on U-Boot
// *drivers/pci/pcie_apple.c, Copyright (C) 2021 Alyssa Rosenzweig,
// *Google LLC, Corellium LLC and Mark Kettenis; and Linux apple-dart.c /
// *io-pgtable-dart.c, Copyright The Asahi Linux Contributors.
// * *Owns only PCI 01:00.0 and its declared RID-to-SID entry. The physical
// *Wi-Fi/Bluetooth combo chip shares PERST: refuse takeover if Bluetooth is
// *bus mastering. No interrupt handler, DART bypass, or guessed MMIO base.
//

fn C.vinix_mmio_read8(arg voidptr) u8

fn C.vinix_mmio_read16(arg voidptr) u16

fn C.vinix_mmio_read32(arg voidptr) u32

fn C.vinix_mmio_write8(arg voidptr, arg_2 u8)

fn C.vinix_mmio_write16(arg voidptr, arg_2 u16)

fn C.vinix_mmio_write32(arg voidptr, arg_2 u32)









@[export: 'vinix_m1_core_get32']
pub fn m1_get32(p &u8) u32 {
	unsafe {
	return u32(p[0]) | u32(p[1]) << 8 | u32(p[2]) << 16 | u32(p[3]) << 24

	}
}

@[export: 'vinix_m1_core_put32']
pub fn m1_put32(p &u8, v u32) {
	unsafe {
	for i := u32(0); i < u32(4); i++ {
		p[i] = u8((v >> (u32(8) * i)))
	}

	}
}

@[export: 'vinix_m1_core_put64']
pub fn m1_put64(p &u8, v u64) {
	unsafe {
	m1_put32(p, u32(v))
	m1_put32(p + 4, u32((v >> 32)))

	}
}

@[export: 'vinix_m1_core_r32']
pub fn m1_r32(a u64) u32 {
	unsafe {
	v := C.vinix_mmio_read32(voidptr(usize(a)))
	m1_barrier()
	return v

	}
}

@[export: 'vinix_m1_core_w32']
pub fn m1_w32(a u64, v u32) {
	unsafe {
	m1_barrier()
	C.vinix_mmio_write32(voidptr(usize(a)), v)

	}
}

@[export: 'vinix_m1_core_w16']
pub fn m1_w16(a u64, v u16) {
	unsafe {
	m1_barrier()
	C.vinix_mmio_write16(voidptr(usize(a)), v)

	}
}

@[export: 'vinix_m1_core_set']
pub fn m1_set(a u64, mask u32) {
	unsafe {
	m1_w32(a, m1_r32(a) | mask)

	}
}

@[export: 'vinix_m1_core_wait_bits']
pub fn m1_wait_bits(a u64, mask u32, expect u32, iterations u32) i32 {
	unsafe {
	for i := u32(0); i < iterations; i++ {
		if (m1_r32(a) & mask) == expect {
			return 0
		}
		m1_delay(u32(100))
	}
	return i32(i32(Bw_error.bw_etime))

	}
}

pub struct M1Host {
pub mut:
	p              C.bw_m1_plan
	dev            C.bw_device
	endpoint       u64
	bar0           u64
	bar2           u64
	bar0_len       u32
	bar2_len       u32
	dart_error     u32
	prepared       i32
	attempted      i32
	endpoint_valid i32
	frames         [64][1514]u8
	length         [64]u16
	head           u16
	tail           u16
	drops          u64
	total          [4]usize
	used           [4]usize
	firmware       [4194304]u8
	nvram          [65536]u8
	clm            [1048576]u8
	txcap          [1048576]u8
}

__global bw_m1_host M1Host

@[export: 'vinix_m1_core_flush_dart']
pub fn m1_flush_dart() i32 {
	unsafe {
	m1_w32(bw_m1_host.p.dart + u64(52), 1 << bw_m1_host.p.sid)
	m1_w32(bw_m1_host.p.dart + u64(32), 1 << 20)
	return m1_wait_bits(bw_m1_host.p.dart + u64(32), u32(4), u32(0), u32(1000))

	}
}

@[export: 'vinix_m1_core_stop_dma']
pub fn m1_stop_dma(unused voidptr) {
	unsafe {


	if bw_m1_host.endpoint_valid {
		cmd := u16(m1_r32(bw_m1_host.endpoint + u64(4)))
		m1_w16(bw_m1_host.endpoint + u64(4), u16((u32(cmd) & ~4)))
		m1_r32(bw_m1_host.endpoint + u64(4))
	}
	// Revoke this stream only. Tables/pool remain quarantined for the rest
	//     *of this boot, so no late completion can touch a reallocated object.

	if bw_m1_host.prepared {
		m1_w32(bw_m1_host.p.dart + u64(256) + u64(bw_m1_host.p.sid * u32(4)), u32(0))
		m1_flush_dart()
	}

	}
}

@[export: 'vinix_m1_core_bus_read']
pub fn m1_bus_read(unused voidptr, space u32, off u32, width u32) u32 {
	unsafe {


	base := if space == u32(Bw_space.bw_config) {
		bw_m1_host.endpoint
	} else {
		(if space == u32(Bw_space.bw_regs) { bw_m1_host.bar0 } else { bw_m1_host.bar2 })
	}
	limit := if space == u32(Bw_space.bw_config) {
		u32(4096)
	} else {
		(if space == u32(Bw_space.bw_regs) { bw_m1_host.bar0_len } else { bw_m1_host.bar2_len })
	}
	if (width != u32(1) && width != u32(2) && width != u32(4)) || width > limit || off > limit - width || (off & (width - u32(1))) {
		return u32(4294967295)
	}
	p := voidptr(usize((base + u64(off))))
	v := if width == u32(1) {
		u32(C.vinix_mmio_read8(voidptr(p)))
	} else {
		(if width == u32(2) {
			u32(C.vinix_mmio_read16(voidptr(p)))
		} else {
			C.vinix_mmio_read32(voidptr(p))
		})
	}
	m1_barrier()
	return v

	}
}

@[export: 'vinix_m1_core_bus_write']
pub fn m1_bus_write(unused voidptr, space u32, off u32, width u32, v u32) {
	unsafe {


	base := if space == u32(Bw_space.bw_config) {
		bw_m1_host.endpoint
	} else {
		(if space == u32(Bw_space.bw_regs) { bw_m1_host.bar0 } else { bw_m1_host.bar2 })
	}
	limit := if space == u32(Bw_space.bw_config) {
		u32(4096)
	} else {
		(if space == u32(Bw_space.bw_regs) { bw_m1_host.bar0_len } else { bw_m1_host.bar2_len })
	}
	if (width != u32(1) && width != u32(2) && width != u32(4)) || width > limit || off > limit - width || (off & (width - u32(1))) {
		return
	}
	p := voidptr(usize((base + u64(off))))
	m1_barrier()
	if width == u32(1) {
		C.vinix_mmio_write8(voidptr(p), u8(v))
	} else if width == u32(2) {
		C.vinix_mmio_write16(voidptr(p), u16(v))
	} else {
		C.vinix_mmio_write32(voidptr(p), v)
	}

	}
}

@[export: 'vinix_m1_core_bus_time']
pub fn m1_bus_time(u voidptr) u64 {
	unsafe {


	return m1_clock_us()

	}
}

@[export: 'vinix_m1_core_bus_delay']
pub fn m1_bus_delay(u voidptr, v u32) {
	unsafe {


	m1_delay(v)

	}
}

@[export: 'vinix_m1_core_bus_sync']
pub fn m1_bus_sync(u voidptr, p voidptr, n usize, to_device i32) {
	unsafe {


	m1_cache_sync(voidptr(p), n, to_device)

	}
}

@[export: 'vinix_m1_core_receive']
pub fn m1_receive(u voidptr, p &C.bw_const_byte, n usize) {
	unsafe {


	next := (u32(bw_m1_host.tail) + 1) % u32(64)
	if n > usize(1514) || next == u32(bw_m1_host.head) {
		bw_m1_host.drops++
		return
	}
	C.memcpy(voidptr( &bw_m1_host.frames[bw_m1_host.tail][0] ), voidptr(p), n)
	bw_m1_host.length[bw_m1_host.tail] = u16(n)
	bw_m1_host.tail = u16(next)

	}
}

@[export: 'vinix_m1_core_dart_prepare']
pub fn m1_dart_prepare() i32 {
	unsafe {
	p := &bw_m1_host.p
	if ((m1_r32(p.dart) >> 24) & u32(15)) != u32(14) || (m1_r32(p.dart + u64(96)) & u32(32768)) {
		return i32(i32(Bw_error.bw_enotsup))
	}
	// Validate the existing RID table before modifying any entry.

	slot := i32(-1)
	for i := u32(0); i < u32(16); i++ {
		v := m1_r32(p.port + u64(2088) + u64(u32(4) * i))
		if v & u32(2147483648) {
			if (v & u32(65535)) == u32(256) {
				slot = i32(i)
			} else if ((v >> 16) & u32(15)) == p.sid {
				return i32(i32(Bw_error.bw_enotsup))
			}
		} else if slot < 0 {
			slot = i32(i)
		}
	}
	if slot < 0 {
		return i32(i32(Bw_error.bw_enospc))
	}
	// Install an RID2SID entry ONLY for Wi-Fi's RID 0x100.
	//     *Bluetooth has a separate DT stream and is not assigned this mapping.

	root := &u64(voidptr(usize(p.tables_cpu)))
	leaf := root + 2048

	C.memset(voidptr(root), 0, u64(32768))
	root[8] = (p.tables_physical + u64(16384)) | u64(1)
	for i := u32(0); i < (4 * 1024 * 1024) / u32(16384); i++ {
		leaf[i] = (p.pool_physical + u64(i) * u64(16384)) | u64(3)
	}
	m1_cache_sync(voidptr(root), usize(32768), 1)
	bw_m1_host.prepared = 1
	// revoke on any subsequent partial-initialization failure

	m1_w32(p.dart + u64(256) + u64(p.sid * u32(4)), u32(0))
	for i := u32(0); i < u32(4); i++ {
		m1_w32(p.dart + u64(512) + u64(p.sid * u32(16)) + u64(i * u32(4)), u32(0))
	}
	m1_w32(p.dart + u64(512) + u64(p.sid * u32(16)), u32((p.tables_physical >> 12)) | u32(2147483648))
	if m1_flush_dart() {
		return i32(i32(Bw_error.bw_etime))
	}
	m1_w32(p.dart + u64(256) + u64(p.sid * u32(4)), u32(128))
	m1_set(p.dart + u64(252), 1 << p.sid)
	m1_w32(p.port + u64(2088) + u64(u32(4) * u32(slot)), u32(2147483904) | (p.sid << 16))
	return 0

	}
}

@[export: 'vinix_m1_core_bar_size']
pub fn m1_bar_size(offset u32, size &u64) i32 {
	unsafe {
	c := bw_m1_host.endpoint
	lo := m1_r32(c + u64(offset))
	hi := m1_r32(c + u64(offset) + u64(4))

	if (lo & u32(7)) != u32(4) {
		return i32(i32(Bw_error.bw_enotsup))
	}
	m1_w32(c + u64(offset), u32(4294967295))
	m1_w32(c + u64(offset) + u64(4), u32(4294967295))
	mask := u64(m1_r32(c + u64(offset) + u64(4))) << 32 | u64((m1_r32(c + u64(offset)) & ~15))
	m1_w32(c + u64(offset), lo)
	m1_w32(c + u64(offset) + u64(4), hi)
	n := ~mask + u64(1)
	if !n || (n & (n - u64(1))) || n > u64(16 * 1024 * 1024) {
		return i32(i32(Bw_error.bw_eproto))
	}
	 *size = n 
	return 0

	}
}

@[export: 'vinix_m1_core_disable_interrupts']
pub fn m1_disable_interrupts() i32 {
	unsafe {
	seen := [256]u8{}
	next := m1_r32(bw_m1_host.endpoint + u64(52)) & u32(255)
	for i := u32(0); next && i < u32(48); i++ {
		if next < u32(64) || (next & u32(3)) || i32(seen[next]) {
			return i32(i32(Bw_error.bw_eproto))
		}
		seen[next] = u8(1)
		cap := m1_r32(bw_m1_host.endpoint + u64(next))
		type_ := cap & u32(255)
		ctl := u16((cap >> 16))
		if type_ == u32(5) {
			m1_w16(bw_m1_host.endpoint + u64(next) + u64(2), u16((u32(ctl) & ~1)))
		}
		if type_ == u32(17) {
			m1_w16(bw_m1_host.endpoint + u64(next) + u64(2), u16(((u32(ctl) & ~32768) | 16384)))
		}
		next = (cap >> 8) & u32(255)
	}
	return if next { i32(Bw_error.bw_eproto) } else { 0 }

	}
}

@[export: 'vinix_m1_core_platform_start']
pub fn m1_platform_start() i32 {
	unsafe {
	p := &bw_m1_host.p
	e := i32(0)
	// Existing link: do not take a combo device away from an active driver.

	if m1_r32(p.port + u64(520)) & u32(1) {
		bt := m1_r32(p.config + u64(1052672))
		if bt != u32(4294967295) && (m1_r32(p.config + u64(1052676)) & u32(4)) {
			return i32(i32(Bw_error.bw_enotsup))
		}
		if m1_r32(p.config + u64(1048576)) != u32(4294967295) && (m1_r32(p.config + u64(1048580)) & u32(4)) {
			return i32(i32(Bw_error.bw_enotsup))
		}
	}
	m1_set(p.port + u64(2048), u32(1))
	// GPIO mode=output, peripheral selection cleared; preserve pull settings.

	gpio := m1_r32(p.gpio) & ~(96 | 15)
	gpio |= 2
	m1_w32(p.gpio, gpio | u32((if p.gpio_active_low { 0 } else { 1 })))
	m1_set(p.phy + u64(4), 1 << 15)
	m1_set(p.phy, u32(1))
	e = m1_wait_bits(p.phy, u32(4), u32(4), u32(500))
	if e {
		 goto reset
		 
	}
	m1_set(p.phy, u32(2))
	e = m1_wait_bits(p.phy, u32(8), u32(8), u32(500))
	if e {
		 goto reset
		 
	}
	m1_w32(p.phy + u64(4), m1_r32(p.phy + u64(4)) & ~(1 << 15))
	m1_set(p.phy, u32(1536))
	m1_set(p.port + u64(2064), u32(1))
	m1_delay(u32(100))
	m1_set(p.port + u64(2068), u32(1))
	m1_w32(p.gpio, gpio | u32((if p.gpio_active_low { 1 } else { 0 })))
	m1_delay(u32(100000))
	e = m1_wait_bits(p.port + u64(2052), u32(1), u32(1), u32(2500))
	if e {
		 goto reset
		 
	}
	m1_w32(p.port + u64(264), u32(4294967295))
	m1_w32(p.port + u64(128), u32(1))
	e = m1_wait_bits(p.port + u64(520), u32(1), u32(1), u32(1000))
	if e {
		 goto reset
		 
	}
	// Only the root port and the fixed DT secondary bus are configured.

	rc := p.config
	if (m1_r32(rc + u64(8)) >> 16) != u32(1540) {
		e = i32(Bw_error.bw_enotsup)
		 goto reset
		 
	}
	m1_w16(rc + u64(4), u16(1026))
	m1_w32(rc + u64(24), u32(65792))
	bw_m1_host.endpoint = p.config + u64(1048576)
	if m1_r32(bw_m1_host.endpoint) != 1143280868 {
		e = i32(Bw_error.bw_enotsup)
		 goto reset
		 
	}
	bw_m1_host.endpoint_valid = 1
	m1_w16(bw_m1_host.endpoint + u64(4), u16(1024))
	e = m1_disable_interrupts()
	if e {
		 goto reset
		 
	}
	size0 := u64(0)
	size2 := u64(0)

	e = m1_bar_size(u32(16), &size0)
	if e || m1_assign_error( &e , i32(m1_bar_size(u32(24), &size2))) {
		 goto reset
		 
	}
	if size0 < u64(12288) || size2 < u64(4194304) {
		e = i32(Bw_error.bw_eproto)
		 goto reset
		 
	}
	arena := (p.window_bus + p.window_size - u64(32 * 1024 * 1024)) & ~u64(1048575)
	a0 := (arena + size0 - u64(1)) & ~(size0 - u64(1))
	a2 := (a0 + size0 + size2 - u64(1)) & ~(size2 - u64(1))

	if a0 < p.window_bus || a2 + size2 > p.window_bus + p.window_size {
		e = i32(Bw_error.bw_enospc)
		 goto reset
		 
	}
	// 32-bit non-prefetchable bridge window; CPU addresses may exceed 4 GiB.

	base := u32(arena)
	limit := u32((a2 + size2 - u64(1)))

	m1_w32(rc + u64(32), ((limit >> 16) & 65520) << 16 | ((base >> 16) & 65520))
	m1_w32(bw_m1_host.endpoint + u64(16), u32(a0) | u32(4))
	m1_w32(bw_m1_host.endpoint + u64(20), u32(0))
	m1_w32(bw_m1_host.endpoint + u64(24), u32(a2) | u32(4))
	m1_w32(bw_m1_host.endpoint + u64(28), u32(0))
	bw_m1_host.bar0 = p.window + (a0 - p.window_bus)
	bw_m1_host.bar2 = p.window + (a2 - p.window_bus)
	bw_m1_host.bar0_len = u32(size0)
	bw_m1_host.bar2_len = u32(size2)
	e = m1_dart_prepare()
	if e {
		 goto reset
		 
	}
	bw_m1_host.prepared = 1
	// stop_dma can now revoke the stream

	m1_w16(rc + u64(4), u16(1030))
	m1_w16(bw_m1_host.endpoint + u64(4), u16(1026))
	// MEM, not bus master yet

	ops := C.bw_ops{
		read:    m1_bus_read
		write:   m1_bus_write
		time_us:  m1_bus_time
		delay_us: m1_bus_delay
		sync:     m1_bus_sync
		stop_dma: m1_stop_dma
		receive:  m1_receive
	}

	e = C.bw_init(&bw_m1_host.dev, &ops, voidptr((voidptr(0))), voidptr(usize(p.pool_cpu)), u64(268435456), usize((4 * 1024 * 1024)), bw_m1_host.bar0_len, bw_m1_host.bar2_len)
	if e || m1_assign_error( &e , i32(C.bw_probe(&bw_m1_host.dev))) {
		 goto reset
		 
	}
	return 0
	reset:
	m1_stop_dma(voidptr((voidptr(0))))
	// Do not leave a failed reset sequence halfway asserted. A failed probe
	//     *is terminal for this boot; no allocator object is released/reused.

	m1_w32(p.gpio, gpio | u32((if p.gpio_active_low { 1 } else { 0 })))
	bw_m1_host.dev.error = e
	bw_m1_host.dev.state = i32(Bw_state.bw_fault)
	return e

	}
}

@[export: 'brcm_m1_prepare']
pub fn brcm_m1_prepare(p &C.bw_m1_plan) i32 {
	unsafe {
	mut __c2v_condition_0 := false
	mut __c2v_condition_1 := false
	__c2v_condition_1 = (usize(p) == 0)
	__c2v_condition_0 = __c2v_condition_1
	if !__c2v_condition_0 {
		mut __c2v_condition_2 := false
		__c2v_condition_2 = bw_m1_host.attempted
		__c2v_condition_0 = __c2v_condition_2
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_3 := false
		__c2v_condition_3 = !p.config
		__c2v_condition_0 = __c2v_condition_3
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_4 := false
		__c2v_condition_4 = p.config_size < u64(1056768)
		__c2v_condition_0 = __c2v_condition_4
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_5 := false
		__c2v_condition_5 = !p.rc
		__c2v_condition_0 = __c2v_condition_5
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_6 := false
		__c2v_condition_6 = !p.port
		__c2v_condition_0 = __c2v_condition_6
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_7 := false
		__c2v_condition_7 = !p.phy
		__c2v_condition_0 = __c2v_condition_7
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_8 := false
		__c2v_condition_8 = !p.gpio
		__c2v_condition_0 = __c2v_condition_8
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_9 := false
		__c2v_condition_9 = !p.dart
		__c2v_condition_0 = __c2v_condition_9
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_10 := false
		__c2v_condition_10 = !p.window
		__c2v_condition_0 = __c2v_condition_10
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_11 := false
		__c2v_condition_11 = p.window_size < u64(64 * 1024 * 1024)
		__c2v_condition_0 = __c2v_condition_11
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_12 := false
		__c2v_condition_12 = p.window_bus > u64(u32(4294967295))
		__c2v_condition_0 = __c2v_condition_12
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_13 := false
		__c2v_condition_13 = p.window_size > u64(4294967296) - p.window_bus
		__c2v_condition_0 = __c2v_condition_13
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_14 := false
		__c2v_condition_14 = !p.pool_cpu
		__c2v_condition_0 = __c2v_condition_14
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_15 := false
		__c2v_condition_15 = !p.tables_cpu
		__c2v_condition_0 = __c2v_condition_15
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_16 := false
		__c2v_condition_16 = !p.pool_physical
		__c2v_condition_0 = __c2v_condition_16
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_17 := false
		__c2v_condition_17 = !p.tables_physical
		__c2v_condition_0 = __c2v_condition_17
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_18 := false
		__c2v_condition_18 = p.pool_cpu > u64(-1) - u64((4 * 1024 * 1024))
		__c2v_condition_0 = __c2v_condition_18
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_19 := false
		__c2v_condition_19 = p.tables_cpu > u64(-1) - u64(32768)
		__c2v_condition_0 = __c2v_condition_19
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_20 := false
		__c2v_condition_20 = (p.pool_cpu & u64(16383))
		__c2v_condition_0 = __c2v_condition_20
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_21 := false
		__c2v_condition_21 = (p.pool_physical & u64(16383))
		__c2v_condition_0 = __c2v_condition_21
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_22 := false
		__c2v_condition_22 = (p.tables_cpu & u64(16383))
		__c2v_condition_0 = __c2v_condition_22
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_23 := false
		__c2v_condition_23 = (p.tables_physical & u64(16383))
		__c2v_condition_0 = __c2v_condition_23
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_24 := false
		__c2v_condition_24 = p.pool_physical > u64(68719476736) - u64((4 * 1024 * 1024))
		__c2v_condition_0 = __c2v_condition_24
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_25 := false
		__c2v_condition_25 = p.tables_physical > u64(68719476736) - u64(32768)
		__c2v_condition_0 = __c2v_condition_25
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_26 := false
		__c2v_condition_26 = (p.pool_physical < p.tables_physical + u64(32768) && p.tables_physical < p.pool_physical + u64((4 * 1024 * 1024)))
		__c2v_condition_0 = __c2v_condition_26
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_27 := false
		__c2v_condition_27 = p.sid != u32(1)
		__c2v_condition_0 = __c2v_condition_27
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_28 := false
		__c2v_condition_28 = p.gpio_active_low > u32(1)
		__c2v_condition_0 = __c2v_condition_28
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_29 := false
		__c2v_condition_29 = (usize(p.calibration) == 0)
		__c2v_condition_0 = __c2v_condition_29
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_30 := false
		__c2v_condition_30 = !p.calibration_len
		__c2v_condition_0 = __c2v_condition_30
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_31 := false
		__c2v_condition_31 = p.calibration_len > usize(1024 * 1024)
		__c2v_condition_0 = __c2v_condition_31
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_32 := false
		__c2v_condition_32 = (usize(p.seed) == 0)
		__c2v_condition_0 = __c2v_condition_32
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_33 := false
		__c2v_condition_33 = p.seed_len != usize(256)
		__c2v_condition_0 = __c2v_condition_33
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_34 := false
		__c2v_condition_34 = !p.antenna[0]
		__c2v_condition_0 = __c2v_condition_34
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_35 := false
		__c2v_condition_35 = i32(p.antenna[15])
		__c2v_condition_0 = __c2v_condition_35
	}
	if __c2v_condition_0 {
		return i32(i32(Bw_error.bw_einval))
	}
	bw_m1_host.attempted = 1
	bw_m1_host.p =  *p 
	return m1_platform_start()

	}
}

@[export: 'brcm_m1_status']
pub fn brcm_m1_status(out &u8) i32 {
	unsafe {
	if usize(out) == 0 {
		return i32(i32(Bw_error.bw_einval))
	}
	C.memset(voidptr(out), 0, u64(256))
	m1_put32(out, u32(bw_m1_host.dev.state))
	m1_put32(out + 4, u32(bw_m1_host.dev.error))
	m1_put32(out + 8, u32(bw_m1_host.dev.revision))
	m1_put32(out + 12, bw_m1_host.dart_error)
	m1_put64(out + 16, bw_m1_host.dev.rx_frames)
	m1_put64(out + 24, bw_m1_host.dev.tx_frames)
	C.memcpy(voidptr(out + 32), bw_m1_host.p.mac, u64(6))
	C.memcpy(voidptr(out + 40), bw_m1_host.dev.otp.module_, u64(16))
	C.memcpy(voidptr(out + 56), bw_m1_host.dev.otp.vendor, u64(16))
	C.memcpy(voidptr(out + 72), bw_m1_host.dev.otp.revision, u64(16))
	C.memcpy(voidptr(out + 88), bw_m1_host.dev.otp.silicon, u64(16))
	C.memcpy(voidptr(out + 104), bw_m1_host.p.antenna, u64(16))
	C.memcpy(voidptr(out + 120), voidptr(c'apple,shikoku'), u64(13))
	m1_put64(out + 152, bw_m1_host.drops)
	m1_put32(out + 160, u32(bw_m1_host.dev.radio_on))
	m1_put32(out + 164, u32(bw_m1_host.dev.scan_pending))
	m1_put32(out + 168, bw_m1_host.dev.network_count)
	m1_put32(out + 172, u32(bw_m1_host.dev.scan_error))
	return 0

	}
}

@[export: 'vinix_m1_core_part']
pub fn m1_part(k u32) &u8 {
	unsafe {
	return if k == u32(0) {
		 &bw_m1_host.firmware[0] 
	} else {
		(if k == u32(1) {
			 &bw_m1_host.nvram[0] 
		} else {
			(if k == u32(2) {  &bw_m1_host.clm[0]  } else {  &bw_m1_host.txcap[0]  })
		})
	}

	}
}

@[export: 'vinix_m1_core_part_capacity']
pub fn m1_part_capacity(k u32) usize {
	unsafe {
	return usize(if k == u32(0) {
		sizeof([4194304]u8)
	} else {
		(if k == u32(1) { sizeof([65536]u8) } else { sizeof([1048576]u8) })
	})

	}
}

@[export: 'brcm_m1_upload']
pub fn brcm_m1_upload(q &u8) i32 {
	unsafe {
	if (usize(q) == 0) || u32(bw_m1_host.dev.state) != u32(i32(Bw_state.bw_chip)) {
		return i32(i32(Bw_error.bw_einval))
	}
	k := m1_get32(q)
	total := m1_get32(q + 4)
	off := m1_get32(q + 8)
	n := m1_get32(q + 12)

	mut __c2v_condition_36 := false
	mut __c2v_condition_37 := false
	__c2v_condition_37 = k > u32(3)
	__c2v_condition_36 = __c2v_condition_37
	if !__c2v_condition_36 {
		mut __c2v_condition_38 := false
		__c2v_condition_38 = !n
		__c2v_condition_36 = __c2v_condition_38
	}
	if !__c2v_condition_36 {
		mut __c2v_condition_39 := false
		__c2v_condition_39 = n > u32(4096)
		__c2v_condition_36 = __c2v_condition_39
	}
	if !__c2v_condition_36 {
		mut __c2v_condition_40 := false
		__c2v_condition_40 = !total
		__c2v_condition_36 = __c2v_condition_40
	}
	if !__c2v_condition_36 {
		mut __c2v_condition_41 := false
		__c2v_condition_41 = usize(total) > m1_part_capacity(k)
		__c2v_condition_36 = __c2v_condition_41
	}
	if !__c2v_condition_36 {
		mut __c2v_condition_42 := false
		__c2v_condition_42 = usize(off) != bw_m1_host.used[k]
		__c2v_condition_36 = __c2v_condition_42
	}
	if !__c2v_condition_36 {
		mut __c2v_condition_43 := false
		__c2v_condition_43 = off > total
		__c2v_condition_36 = __c2v_condition_43
	}
	if !__c2v_condition_36 {
		mut __c2v_condition_44 := false
		__c2v_condition_44 = n > total - off
		__c2v_condition_36 = __c2v_condition_44
	}
	if !__c2v_condition_36 {
		mut __c2v_condition_45 := false
		__c2v_condition_45 = (bw_m1_host.total[k] && usize(total) != bw_m1_host.total[k])
		__c2v_condition_36 = __c2v_condition_45
	}
	if __c2v_condition_36 {
		return i32(i32(Bw_error.bw_einval))
	}
	bw_m1_host.total[k] = usize(total)
	C.memcpy(voidptr(m1_part(k) + off), voidptr(q + 16), u64(n))
	bw_m1_host.used[k] += usize(n)
	return 0

	}
}

@[export: 'vinix_m1_core_string_equal']
pub fn m1_string_equal(a &u8, b &char, n usize) i32 {
	unsafe {
	len := usize(0)
	for len < n && i32(b[len]) {
		len++
	}
	return i32(len < n && !C.memcmp(voidptr(a), voidptr(b), len) && i32(a[len]) == 0)

	}
}

@[export: 'brcm_m1_boot']
pub fn brcm_m1_boot(q &u8) i32 {
	unsafe {
	mut __c2v_condition_46 := false
	mut __c2v_condition_47 := false
	__c2v_condition_47 = (usize(q) == 0)
	__c2v_condition_46 = __c2v_condition_47
	if !__c2v_condition_46 {
		mut __c2v_condition_48 := false
		__c2v_condition_48 = u32(bw_m1_host.dev.state) != u32(i32(Bw_state.bw_chip))
		__c2v_condition_46 = __c2v_condition_48
	}
	if !__c2v_condition_46 {
		mut __c2v_condition_49 := false
		__c2v_condition_49 = m1_get32(q) != u32(bw_m1_host.dev.revision)
		__c2v_condition_46 = __c2v_condition_49
	}
	if !__c2v_condition_46 {
		mut __c2v_condition_50 := false
		__c2v_condition_50 = m1_get32(q + 4)
		__c2v_condition_46 = __c2v_condition_50
	}
	if !__c2v_condition_46 {
		mut __c2v_condition_51 := false
		__c2v_condition_51 = !m1_string_equal(q + 8,  &char(&bw_m1_host.dev.otp.module_[0]) , usize(16))
		__c2v_condition_46 = __c2v_condition_51
	}
	if !__c2v_condition_46 {
		mut __c2v_condition_52 := false
		__c2v_condition_52 = !m1_string_equal(q + 24,  &char(&bw_m1_host.dev.otp.vendor[0]) , usize(16))
		__c2v_condition_46 = __c2v_condition_52
	}
	if !__c2v_condition_46 {
		mut __c2v_condition_53 := false
		__c2v_condition_53 = !m1_string_equal(q + 40,  &char(&bw_m1_host.dev.otp.revision[0]) , usize(16))
		__c2v_condition_46 = __c2v_condition_53
	}
	if !__c2v_condition_46 {
		mut __c2v_condition_54 := false
		__c2v_condition_54 = !m1_string_equal(q + 56,  &char(&bw_m1_host.p.antenna[0]) , usize(16))
		__c2v_condition_46 = __c2v_condition_54
	}
	if !__c2v_condition_46 {
		mut __c2v_condition_55 := false
		__c2v_condition_55 = !m1_string_equal(q + 72, c'apple,shikoku', usize(32))
		__c2v_condition_46 = __c2v_condition_55
	}
	if __c2v_condition_46 {
		return i32(i32(Bw_error.bw_einval))
	}
	for i := u32(104); i < 128; i++ {
		if q[i] {
			return i32(i32(Bw_error.bw_einval))
		}
	}
	for i := u32(0); i < u32(4); i++ {
		if !bw_m1_host.total[i] || bw_m1_host.used[i] != bw_m1_host.total[i] {
			return i32(i32(Bw_error.bw_einval))
		}
	}
	f := C.bw_firmware{
		code:              &bw_m1_host.firmware[0] 
		nvram:             &bw_m1_host.nvram[0] 
		clm:               &bw_m1_host.clm[0] 
		txcap:             &bw_m1_host.txcap[0] 
		calibration:      bw_m1_host.p.calibration
		seed:             bw_m1_host.p.seed
		code_len:         bw_m1_host.total[0]
		nvram_len:        bw_m1_host.total[1]
		clm_len:          bw_m1_host.total[2]
		txcap_len:        bw_m1_host.total[3]
		calibration_len:  bw_m1_host.p.calibration_len
		seed_len:         bw_m1_host.p.seed_len
		silicon_revision: bw_m1_host.dev.revision
		mac:              [u8(0), u8(0), u8(0), u8(0), u8(0), u8(0)]!
	}

	C.memcpy(f.mac, bw_m1_host.p.mac, u64(6))
	// DART was populated, enabled and flushed before this first BME write.

	m1_w16(bw_m1_host.endpoint + u64(4), u16(1030))
	e := C.bw_start(&bw_m1_host.dev, &f)
	// Caller owns the entropy storage and must wipe its consumed copy.

	return e

	}
}

@[export: 'brcm_m1_join']
pub fn brcm_m1_join(q &u8) i32 {
	unsafe {
	if usize(q) == 0 {
		return i32(i32(Bw_error.bw_einval))
	}
	return C.bw_join_wpa2(&bw_m1_host.dev, q + 8, usize(m1_get32(q)), q + 40, usize(m1_get32(q + 4)))

	}
}

@[export: 'brcm_m1_radio']
pub fn brcm_m1_radio(q &u8) i32 {
	unsafe {
	if usize(q) == 0 {
		return i32(i32(Bw_error.bw_einval))
	}
	enabled := m1_get32(q)
	return if enabled <= u32(1) { C.bw_radio(&bw_m1_host.dev, i32(enabled)) } else { i32(Bw_error.bw_einval) }

	}
}

@[export: 'brcm_m1_scan']
pub fn brcm_m1_scan() i32 {
	unsafe {
	return C.bw_scan(&bw_m1_host.dev)

	}
}

@[export: 'brcm_m1_networks']
pub fn brcm_m1_networks(out &u8) i32 {
	unsafe {
	return C.bw_networks(&bw_m1_host.dev, out, usize((16 + 32 * 48)))

	}
}

@[export: 'brcm_m1_poll']
pub fn brcm_m1_poll() i32 {
	unsafe {
	if !bw_m1_host.prepared {
		return 0
	}
	if u32(bw_m1_host.dev.state) >= u32(i32(Bw_state.bw_ready)) && u32(bw_m1_host.dev.state) != u32(i32(Bw_state.bw_fault)) {
		err := m1_r32(bw_m1_host.p.dart + u64(64))
		if (err & u32(2147483648)) && ((err >> 24) & u32(15)) == bw_m1_host.p.sid {
			bw_m1_host.dart_error = err
			C.bw_stop(&bw_m1_host.dev)
			bw_m1_host.dev.error = i32(Bw_error.bw_eio)
			return i32(i32(Bw_error.bw_eio))
		}
	}
	e := C.bw_poll(&bw_m1_host.dev, u32(64))
	return if e < 0 { e } else { (i32(bw_m1_host.head) != i32(bw_m1_host.tail)) }

	}
}

@[export: 'brcm_m1_read']
pub fn brcm_m1_read(p &u8, n usize) i32 {
	unsafe {
	if usize(p) == 0 {
		return i32(i32(Bw_error.bw_einval))
	}
	if i32(bw_m1_host.head) == i32(bw_m1_host.tail) {
		return if u32(bw_m1_host.dev.state) == u32(i32(Bw_state.bw_fault)) { i32(Bw_error.bw_enolink) } else { 0 }
	}
	len := usize(bw_m1_host.length[bw_m1_host.head])
	if n < len {
		return i32(i32(Bw_error.bw_enospc))
	}
	C.memcpy(voidptr(p), voidptr( &bw_m1_host.frames[bw_m1_host.head][0] ), len)
	bw_m1_host.head = u16(((i32(bw_m1_host.head) + 1) % 64))
	return i32(len)

	}
}

@[export: 'brcm_m1_write']
pub fn brcm_m1_write(p &u8, n usize) i32 {
	unsafe {
	return C.bw_transmit(&bw_m1_host.dev, p, n)

	}
}

@[export: 'brcm_m1_stop']
pub fn brcm_m1_stop() {
	unsafe {
	if bw_m1_host.prepared {
		// DART may be prepared before bw_init installs the protocol callbacks.
		if usize(bw_m1_host.dev.ops.stop_dma) == 0 {
			m1_stop_dma(nil)
			return
		}
		if u32(bw_m1_host.dev.state) >= u32(i32(Bw_state.bw_ready)) && u32(bw_m1_host.dev.state) < u32(i32(Bw_state.bw_fault)) {
			C.bw_disconnect(&bw_m1_host.dev)
		} else {
			C.bw_stop(&bw_m1_host.dev)
		}
	}

	}
}


@[export: 'vinix_m1_core_assign_error']
pub fn m1_assign_error(p &i32, value i32) i32 {
	unsafe { *p = value; return value 
	}
}

@[export: 'vinix_m1_core_state']
pub fn m1_state() voidptr {
	unsafe { return &bw_m1_host 
	}
}
