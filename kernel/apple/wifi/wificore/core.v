@[translated]
module wificore
@[typedef]
struct C.bw_const_byte {}
#include "brcm_wifi.h"
#include <string.h>
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
struct SecretByte {
mut:
 volatile value u8
}

#include <stddef.h>
#include <stdint.h>















// SPDX-License-Identifier: ISC
// *Experimental BCM4378 FullMAC PCIe driver for Vinix.
// *The caller owns the PCIe host, DART mapping, firmware files and serialization.
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

pub struct C.bw_ops {
pub mut:
	read    fn (voidptr, u32, u32, u32) u32
	write   fn (voidptr, u32, u32, u32, u32)
	time_us  fn (voidptr) u64
	delay_us fn (voidptr, u32)
	// DMA sync is required even on machines where ordinary RAM is coherent.
	//     *to_device: clean/invalidate before publishing ownership to the device.
	//     *to_cpu: invalidate after observing a device-written completion/index.
	//     *Each allocated area is isolated on at least 128-byte cache boundaries.
	sync fn (voidptr, voidptr, usize, i32)
	// Must disable PCI bus mastering and drain/quiesce before return.
	//     *The driver NEVER frees or reuses the DMA pool after a fatal error.
	stop_dma fn (voidptr)
	receive  fn (voidptr, &C.bw_const_byte, usize)
}

pub struct C.bw_core {
pub mut:
	base u32
	wrap u32
	id   u16
	rev  u8
}

pub struct C.bw_mem {
pub mut:
	cpu &u8
	dma u64
	len usize
}

pub struct C.bw_ring {
pub mut:
	mem         C.bw_mem
	wi          u32
	ri          u32
	count       u16
	item        u16
	read       u16
	write      u16
	dma_indices u8
}

pub struct C.bw_packet {
pub mut:
	mem   C.bw_mem
	token u32
	owner u8
	kind  u8
}

pub struct C.bw_otp {
pub mut:
	module_  [16]char
	vendor   [16]char
	revision [16]char
	silicon  [16]char
}

pub struct C.bw_firmware {
pub mut:
	code             &u8
	nvram            &u8
	clm              &u8
	txcap            &u8
	calibration      &u8
	seed             &u8
	code_len         usize
	nvram_len        usize
	clm_len          usize
	txcap_len        usize
	calibration_len  usize
	seed_len         usize
	silicon_revision u8
	mac              [6]u8
}

pub struct C.bw_network {
pub mut:
	ssid_len u8
	secure   u8
	channel  u16
	rssi     i16
	bssid    [6]u8
	ssid     [32]u8
}

pub struct C.bw_device {
pub mut:
	ops              C.bw_ops
	cookie           voidptr
	state            i32
	error            i32
	regs_size        u32
	tcm_size         u32
	ram_base         u32
	ram_size         u32
	shared_          u32
	flags            u32
	rx_offset        u32
	ring_info        u32
	h2d_mb           u32
	d2h_mb           u32
	submission_count u16
	completion_count u16
	max_rx           u16
	revision         u8
	pcie_revision    u8
	version          u8
	index_size       u8
	mb_via_ctl       u8
	cores            [32]C.bw_core
	core_count       u32
	otp              C.bw_otp
	pool             C.bw_mem
	indices          [4]C.bw_mem
	allocated        usize
	rings            [6]C.bw_ring
	// five common rings and station best-effort TX
	rx              [528]C.bw_packet
	tx              [128]C.bw_packet
	request         C.bw_mem
	next_token      u32
	transaction     u16
	reply_length    u16
	reply_status    i16
	reply_command   u32
	request_busy    u8
	reply_ready     u8
	flow_pending    u8
	flow_open       u8
	associated      u8
	keyed           u8
	mac             [6]u8
	bssid           [6]u8
	radio_on        u8
	scan_pending    u8
	scan_sync       u16
	scan_error      i32
	network_count   u32
	networks        [32]C.bw_network
	join_deadline   u64
	flow_deadline   u64
	scan_deadline   u64
	rx_frames       u64
	tx_frames       u64
	bad_completions u64
	reply           [8192]u8
}

// Initialize software only. Pool must already be isolated by DART; bus master
// *remains disabled until platform code has established that isolation.

// Probe only accesses the declared endpoint. Reads core inventory and OTP;
// *it does not upload firmware or turn on the radio.

// Bounded, host-testable parsers. NVRAM input is board-specific text; output
// *includes double NUL, padding, and the Broadcom complement length token.

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
// SPDX-License-Identifier: ISC
// *Copyright (c) 2010-2016 Broadcom Corporation
// *Copyright (c) 2016,2017 Patrick Wildt <patrick@blueri.se>
// * *Permission to use, copy, modify, and/or distribute this software for any
// *purpose with or without fee is hereby granted, provided that the above
// *copyright notice and this permission notice appear in all copies.
// *THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
// *WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
// *MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
// *ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
// *WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
// *ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
// *OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
// * *New bounded Vinix implementation of the BCM4378 PCIe FullMAC protocol.
// *Register and wire-layout reference: OpenBSD bwfm{,reg}.h/.c and
// *if_bwfm_pci{.c,.h}. Not a transplant of the OpenBSD networking stack.
// *No allocation in the receive path. All entry points require serialization.
//

@[export: 'vinix_bw_core_l16']
pub fn wifi_l16(q voidptr) u16 {
	unsafe {
	p := &u8(q)
	return u16((i32(p[0]) | i32(u16(p[1])) << 8))

	}
}

@[export: 'vinix_bw_core_l32']
pub fn wifi_l32(q voidptr) u32 {
	unsafe {
	p := &u8(q)
	return u32(p[0]) | u32(p[1]) << 8 | u32(p[2]) << 16 | u32(p[3]) << 24

	}
}

@[export: 'vinix_bw_core_b16']
pub fn wifi_b16(q voidptr) u16 {
	unsafe {
	p := &u8(q)
	return u16((i32(u16(p[0])) << 8 | i32(p[1])))

	}
}

@[export: 'vinix_bw_core_b32']
pub fn wifi_b32(q voidptr) u32 {
	unsafe {
	p := &u8(q)
	return u32(p[0]) << 24 | u32(p[1]) << 16 | u32(p[2]) << 8 | u32(p[3])

	}
}

@[export: 'vinix_bw_core_s16']
pub fn wifi_s16(q voidptr, v u16) {
	unsafe {
	p := &u8(q)
	p[0] = u8(v)
	p[1] = u8((i32(v) >> 8))

	}
}

@[export: 'vinix_bw_core_s32']
pub fn wifi_s32(q voidptr, v u32) {
	unsafe {
	p := &u8(q)
	p[0] = u8(v)
	p[1] = u8((v >> 8))
	p[2] = u8((v >> 16))
	p[3] = u8((v >> 24))

	}
}

@[export: 'vinix_bw_core_s64']
pub fn wifi_s64(p voidptr, v u64) {
	unsafe {
	wifi_s32(voidptr(p), u32(v))
	wifi_s32(voidptr(&u8(p) + 4), u32((v >> 32)))

	}
}

@[export: 'vinix_bw_core_erase']
pub fn wifi_erase(p voidptr, n usize) {
	unsafe {
	for i := usize(0); i < n; i++ { (&SecretByte(usize(p) + i)).value = 0 }

	}
}

@[export: 'vinix_bw_core_range']
pub fn wifi_range(p u32, n usize, low u32, high u32) i32 {
	unsafe {
	return i32(p >= low && p <= high && n <= usize((high - p)))

	}
}

@[export: 'vinix_bw_core_mac_ok']
pub fn wifi_mac_ok(m &u8) i32 {
	unsafe {
	any := u32(0)
	for i := u32(0); i < u32(6); i++ {
		any |= u32(m[i])
	}
	return i32(any && !(i32(m[0]) & 1))

	}
}

@[export: 'vinix_bw_core_fail']
pub fn wifi_fail(d &C.bw_device, e i32) i32 {
	unsafe {
	if u32(d.state) != u32(i32(Bw_state.bw_fault)) {
		d.ops.stop_dma(voidptr(d.cookie))
	}
	d.state = i32(Bw_state.bw_fault)
	d.scan_pending = u8(0)
	d.radio_on = d.scan_pending
	d.keyed = d.radio_on
	d.associated = d.keyed
	d.error = e
	return e

	}
}

@[export: 'vinix_bw_core_rd']
pub fn wifi_rd(d &C.bw_device, s u32, o u32, w u32) u32 {
	unsafe {
	return d.ops.read(voidptr(d.cookie), s, o, w)

	}
}

@[export: 'vinix_bw_core_wr']
pub fn wifi_wr(d &C.bw_device, s u32, o u32, w u32, v u32) {
	unsafe {
	d.ops.write(voidptr(d.cookie), s, o, w, v)

	}
}

@[export: 'vinix_bw_core_bp_read']
pub fn wifi_bp_read(d &C.bw_device, a u32) u32 {
	unsafe {
	wifi_wr(d, u32(Bw_space.bw_config), u32(128), u32(4), a & ~4095)
	wifi_rd(d, u32(Bw_space.bw_config), u32(128), u32(4))
	return wifi_rd(d, u32(Bw_space.bw_regs), a & 4095, u32(4))

	}
}

@[export: 'vinix_bw_core_bp_write']
pub fn wifi_bp_write(d &C.bw_device, a u32, v u32) {
	unsafe {
	wifi_wr(d, u32(Bw_space.bw_config), u32(128), u32(4), a & ~4095)
	wifi_rd(d, u32(Bw_space.bw_config), u32(128), u32(4))
	wifi_wr(d, u32(Bw_space.bw_regs), a & 4095, u32(4), v)

	}
}

@[export: 'vinix_bw_core_core']
pub fn wifi_core(d &C.bw_device, id u32) &C.bw_core {
	unsafe {
	for i := u32(0); i < d.core_count; i++ {
		if u32(d.cores[i].id) == id {
			return  &d.cores[0] + i 
		}
	}
	return  nil 

	}
}

@[export: 'vinix_bw_core_chip_address']
pub fn wifi_chip_address(p u32) i32 {
	unsafe {
	return i32(p >= 402653184 && p <= 419422208 && !(p & 4095))

	}
}

@[export: 'vinix_bw_core_ram_address']
pub fn wifi_ram_address(d &C.bw_device, p u32, n usize) i32 {
	unsafe {
	return wifi_range(p, n, d.ram_base, d.ram_base + d.ram_size)

	}
}

@[export: 'vinix_bw_core_tcm_copy']
pub fn wifi_tcm_copy(d &C.bw_device, a u32, p &u8, n usize) {
	unsafe {
	for n != 0 && (a & 3) != 0 { wifi_wr(d, u32(Bw_space.bw_tcm), a, 1, u32(*p)); a++; p += 1; n-- }
	for n >= 4 { wifi_wr(d, u32(Bw_space.bw_tcm), a, 4, wifi_l32(voidptr(p))); a += 4; p += 4; n -= 4 }
	for n != 0 { wifi_wr(d, u32(Bw_space.bw_tcm), a, 1, u32(*p)); a++; p += 1; n-- }

	}
}

@[export: 'vinix_bw_core_alloc_mem']
pub fn wifi_alloc_mem(d &C.bw_device, n usize, m &C.bw_mem) i32 {
	unsafe {
	off := (d.allocated + usize(127)) & ~usize(127)
	if !n || n > d.pool.len || off > d.pool.len - n {
		return i32(i32(Bw_error.bw_enospc))
	}
	m.cpu = d.pool.cpu + off
	m.dma = d.pool.dma + u64(off)
	m.len = n
	d.allocated = off + n
	C.memset(voidptr(m.cpu), 0, n)
	d.ops.sync(voidptr(d.cookie), voidptr(m.cpu), n, 1)
	return 0

	}
}

@[export: 'bw_nvram_pack']
pub fn bw_nvram_pack(in_ &u8, n usize, out &u8, cap usize, used &usize) i32 {
	unsafe {
	pos := usize(0)
	w := usize(0)

	lines := u32(0)
	if (usize(in_) == 0) || (usize(out) == 0) || (usize(used) == 0) || !n || n > usize(65536) || cap < usize(8) {
		return i32(i32(Bw_error.bw_einval))
	}
	 *used = usize(0) 
	for pos < n {
		a := pos
		b := usize(0)
		e := usize(0)

		for pos < n && i32(in_[pos]) != `\n` && i32(in_[pos]) != `\r` {
			if !in_[pos] || (i32(in_[pos]) < 32 && i32(in_[pos]) != `\t`) || i32(in_[pos]) > 126 {
				return i32(i32(Bw_error.bw_einval))
			}
			pos++
		}
		b = pos
		for pos < n && (i32(in_[pos]) == `\n` || i32(in_[pos]) == `\r`) {
			pos++
		}
		for a < b && (i32(in_[a]) == ` ` || i32(in_[a]) == `\t`) {
			a++
		}
		for e = a; e < b; e++ {
			if i32(in_[e]) == `#` {
				b = e
				break
			}
		}
		for b > a && (i32(in_[b - usize(1)]) == ` ` || i32(in_[b - usize(1)]) == `\t`) {
			b--
		}
		if a == b {
			continue
		}
		for e = a; e < b && i32(in_[e]) != `=`; e++ {
			c := in_[e]
			if !((i32(c) >= `a` && i32(c) <= `z`) || (i32(c) >= `A` && i32(c) <= `Z`) || (i32(c) >= `0` && i32(c) <= `9`) || i32(c) == `_` || i32(c) == `.` || i32(c) == `/` || i32(c) == `:`) {
				return i32(i32(Bw_error.bw_einval))
			}
		}
		if e == a || e == b || b - a > usize(1024) || wifi_increment_lines( &lines , u32(1)) > u32(1024) {
			return i32(i32(Bw_error.bw_einval))
		}
		// No duplicate keys: ambiguous board calibration must not be guessed.

		for q := usize(0); q < w; {
			k := q
			for k < w && i32(out[k]) != `=` {
				k++
			}
			if k - q == e - a && !C.memcmp(voidptr(out + q), voidptr(in_ + a), e - a) {
				return i32(i32(Bw_error.bw_einval))
			}
			for q < w && i32(out[q]) {
				q++
			}
			q++
		}
		if b - a + usize(1) > cap - w {
			return i32(i32(Bw_error.bw_enospc))
		}
		C.memcpy(voidptr(out + w), voidptr(in_ + a), b - a)
		w += b - a
		out[w++] = u8(0)
	}
	if !lines || w > usize(65528) {
		return i32(i32(Bw_error.bw_einval))
	}
	padded := (w + usize(1) + usize(3)) & ~usize(3)
	if padded > cap - usize(4) {
		return i32(i32(Bw_error.bw_enospc))
	}
	C.memset(voidptr(out + w), 0, padded - w)
	words := u32((padded / usize(4)))
	wifi_s32(voidptr(out + padded), words | ((~words & 65535) << 16))
	 *used = padded + usize(4) 
	return 0

	}
}

@[export: 'vinix_bw_core_otp_value']
pub fn wifi_otp_value(out &char, in_ &u8, len usize) i32 {
	unsafe {
	if !len || len >= usize(16) {
		return i32(i32(Bw_error.bw_eproto))
	}
	for i := usize(0); i < len; i++ {
		c := in_[i]
		if !((i32(c) >= `A` && i32(c) <= `Z`) || (i32(c) >= `a` && i32(c) <= `z`) || (i32(c) >= `0` && i32(c) <= `9`) || i32(c) == `_` || i32(c) == `-` || i32(c) == `.`) {
			return i32(i32(Bw_error.bw_eproto))
		}
	}
	if i32(out[0]) && (i32(out[len]) != 0 || C.memcmp(voidptr(out), voidptr(in_), len)) {
		return i32(i32(Bw_error.bw_eproto))
	}
	C.memcpy(voidptr(out), voidptr(in_), len)
	out[len] = i8(0)
	return 0

	}
}

@[export: 'bw_otp_parse']
pub fn bw_otp_parse(in_ &u8, n usize, out &C.bw_otp) i32 {
	unsafe {
	p := usize(0)
	found := i32(0)
	if (usize(in_) == 0) || (usize(out) == 0) || !n || n > usize(4096) {
		return i32(i32(Bw_error.bw_einval))
	}
	C.memset(voidptr(out), 0, sizeof(C.bw_otp))
	for p < n {
		tag := in_[p++]
		if i32(tag) == 255 {
			break
		}
		if !tag {
			continue
		}
		if p == n {
			return i32(i32(Bw_error.bw_eproto))
		}
		len := usize(in_[p++])
		if len > n - p {
			return i32(i32(Bw_error.bw_eproto))
		}
		if i32(tag) == 21 && len >= usize(4) && wifi_l32(voidptr(in_ + p)) == u32(8) {
			q := p + usize(4)
			end := p + len

			for q < end {
				for q < end && (i32(in_[q]) == 0 || i32(in_[q]) == ` `) {
					q++
				}
				if q == end || i32(in_[q]) == 255 {
					break
				}
				s := q
				for q < end && i32(in_[q]) && i32(in_[q]) != ` ` && i32(in_[q]) != 255 {
					q++
				}
				if q - s >= usize(3) && i32(in_[s + usize(1)]) == `=` {
					v :=  &char(nil) 
					match i32(in_[s]) {
						i32(`M`) { // case comp body kind=BinaryOperator is_enum=false
							v =  &out.module_[0] 
						}
						i32(`V`) { // case comp body kind=BinaryOperator is_enum=false
							v =  &out.vendor[0] 
						}
						i32(`m`) { // case comp body kind=BinaryOperator is_enum=false
							v =  &out.revision[0] 
						}
						i32(`s`) { // case comp body kind=BinaryOperator is_enum=false
							v =  &out.silicon[0] 
						}
						else {
						}
					}

					if !(usize(v) == 0) && wifi_otp_value(v, in_ + s + 2, q - s - usize(2)) {
						return i32(i32(Bw_error.bw_eproto))
					}
				}
			}
			found = 1
		}
		p += len
	}
	return if found && i32(out.module_[0]) && i32(out.vendor[0]) && i32(out.revision[0]) {
		0
	} else {
		i32(Bw_error.bw_eproto)
	}

	}
}

@[export: 'bw_init']
pub fn bw_init(d &C.bw_device, ops &C.bw_ops, cookie voidptr, cpu voidptr, dma u64, len usize, regs u32, tcm u32) i32 {
	unsafe {
	mut __c2v_condition_0 := false
	mut __c2v_condition_1 := false
	__c2v_condition_1 = (usize(d) == 0)
	__c2v_condition_0 = __c2v_condition_1
	if !__c2v_condition_0 {
		mut __c2v_condition_2 := false
		__c2v_condition_2 = (usize(ops) == 0)
		__c2v_condition_0 = __c2v_condition_2
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_3 := false
		__c2v_condition_3 = (usize(ops.read) == 0)
		__c2v_condition_0 = __c2v_condition_3
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_4 := false
		__c2v_condition_4 = (usize(ops.write) == 0)
		__c2v_condition_0 = __c2v_condition_4
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_5 := false
		__c2v_condition_5 = (usize(ops.sync) == 0)
		__c2v_condition_0 = __c2v_condition_5
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_6 := false
		__c2v_condition_6 = (usize(ops.time_us) == 0)
		__c2v_condition_0 = __c2v_condition_6
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_7 := false
		__c2v_condition_7 = (usize(ops.delay_us) == 0)
		__c2v_condition_0 = __c2v_condition_7
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_8 := false
		__c2v_condition_8 = (usize(ops.stop_dma) == 0)
		__c2v_condition_0 = __c2v_condition_8
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_9 := false
		__c2v_condition_9 = (usize(ops.receive) == 0)
		__c2v_condition_0 = __c2v_condition_9
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_10 := false
		__c2v_condition_10 = (usize(cpu) == 0)
		__c2v_condition_0 = __c2v_condition_10
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_11 := false
		__c2v_condition_11 = (usize(cpu) & usize(127))
		__c2v_condition_0 = __c2v_condition_11
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_12 := false
		__c2v_condition_12 = !dma
		__c2v_condition_0 = __c2v_condition_12
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_13 := false
		__c2v_condition_13 = (dma & u64(127))
		__c2v_condition_0 = __c2v_condition_13
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_14 := false
		__c2v_condition_14 = len < usize((4 * 1024 * 1024))
		__c2v_condition_0 = __c2v_condition_14
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_15 := false
		__c2v_condition_15 = len > usize(16 * 1024 * 1024)
		__c2v_condition_0 = __c2v_condition_15
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_16 := false
		__c2v_condition_16 = dma > u64(-1) - u64(len)
		__c2v_condition_0 = __c2v_condition_16
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_17 := false
		__c2v_condition_17 = regs < u32(12288)
		__c2v_condition_0 = __c2v_condition_17
	}
	if !__c2v_condition_0 {
		mut __c2v_condition_18 := false
		__c2v_condition_18 = tcm < u32(4194304)
		__c2v_condition_0 = __c2v_condition_18
	}
	if __c2v_condition_0 {
		return i32(i32(Bw_error.bw_einval))
	}
	C.memset(voidptr(d), 0, sizeof(C.bw_device))
	d.ops =  *ops 
	d.cookie = cookie
	d.pool = C.bw_mem{
		cpu: &u8(cpu)
		dma: dma
		len: len
	}

	d.regs_size = regs
	d.tcm_size = tcm
	d.next_token = u32(1)
	return 0

	}
}

@[export: 'vinix_bw_core_inventory']
pub fn wifi_inventory(d &C.bw_device) i32 {
	unsafe {
	erom := wifi_bp_read(d, 402653436)
	if !wifi_chip_address(erom) {
		return i32(i32(Bw_error.bw_eproto))
	}
	words := [1024]u32{}
	for i := u32(0); i < u32(1024); i++ {
		words[i] = wifi_bp_read(d, erom + u32(4) * i)
	}
	p := u32(0)
	d.core_count = u32(0)
	for p < u32(1024) {
		a := words[p++]
		if (a & u32(15)) == u32(15) {
			return if d.core_count { 0 } else { i32(Bw_error.bw_eproto) }
		}
		if (a & u32(15)) != u32(1) {
			continue
		}
		if p == u32(1024) {
			return i32(i32(Bw_error.bw_eproto))
		}
		b := words[p++]
		if (b & u32(15)) != u32(1) {
			return i32(i32(Bw_error.bw_eproto))
		}
		c := C.bw_core{
			base: u32(0)
			wrap: u32(0)
			id:   u16(((a >> 8) & u32(4095)))
			rev:  u8((b >> 24))
		}

		wraptype := u32(if p < u32(1024) && (words[p] & u32(15)) == u32(3) { 3 } else { 2 })
		wrapcount := ((b >> 14) & u32(31)) + ((b >> 19) & u32(31))
		for p < u32(1024) {
			v := words[p]
			type_ := v & u32(15)
			if type_ == u32(1) || type_ == u32(15) {
				break
			}
			p++
			if (type_ & ~8) != u32(5) {
				continue
			}
			if type_ & u32(8) {
				if p == u32(1024) || words[p++] != u32(0) {
					return i32(i32(Bw_error.bw_enotsup))
				}
			}
			sz := (v >> 4) & u32(3)
			if sz == u32(3) {
				if p == u32(1024) {
					return i32(i32(Bw_error.bw_eproto))
				}
				z := words[p++]
				if z & u32(8) {
					if p == u32(1024) {
						return i32(i32(Bw_error.bw_eproto))
					}
					p++
				}
				continue
			}
			if sz > u32(1) {
				continue
			}
			st := (v >> 6) & u32(3)
			if !st && !c.base {
				c.base = v & u32(4294963200)
			}
			if st == wraptype && !c.wrap {
				c.wrap = v & u32(4294963200)
			}
		}
		if !wrapcount && u32(c.id) != 2112 && i32(c.id) != 2087 {
			continue
		}
		if !wifi_chip_address(c.base) || (wrapcount && !wifi_chip_address(c.wrap)) {
			return i32(i32(Bw_error.bw_eproto))
		}
		if d.core_count == 32 {
			return i32(i32(Bw_error.bw_enospc))
		}
		d.cores[d.core_count++] = c
	}
	return i32(i32(Bw_error.bw_eproto))

	}
}

@[export: 'bw_probe']
pub fn bw_probe(d &C.bw_device) i32 {
	unsafe {
	if (usize(d) == 0) || u32(d.state) != u32(i32(Bw_state.bw_off)) {
		return i32(i32(Bw_error.bw_einval))
	}
	if wifi_rd(d, u32(Bw_space.bw_config), u32(0), u32(4)) != 1143280868 {
		return i32(i32(Bw_error.bw_enotsup))
	}
	id := wifi_bp_read(d, u32(402653184))
	if (id & u32(65535)) != u32(17272) || ((id >> 28) & u32(15)) != u32(1) {
		return i32(i32(Bw_error.bw_enotsup))
	}
	d.revision = u8(((id >> 16) & u32(15)))
	if i32(d.revision) != 3 && i32(d.revision) != 5 {
		return i32(i32(Bw_error.bw_enotsup))
	}
	e := wifi_inventory(d)
	if e {
		return e
	}
	if is_null(wifi_core(d, 2119)) || is_null(wifi_core(d, 2121)) || is_null(wifi_core(d, 2108)) || is_null(wifi_core(d, 2048)) || is_null(wifi_core(d, 2112)) {
		return i32(i32(Bw_error.bw_enotsup))
	}
	d.pcie_revision = wifi_core(d, 2108).rev
	otp := [736]u8{}
	base := wifi_core(d, 2112).base + u32(4384)
	for i := u32(0); u64(i) < sizeof([736]u8); i += u32(4) {
		wifi_s32(voidptr( &otp[0]  + i), wifi_bp_read(d, base + i))
	}
	e = bw_otp_parse( &otp[0] , sizeof([736]u8), &d.otp)
	if e {
		return e
	}
	d.ram_base = 3481600
	d.state = i32(Bw_state.bw_chip)
	return 0

	}
}

@[export: 'vinix_bw_core_core_disable']
pub fn wifi_core_disable(d &C.bw_device, c &C.bw_core, pre u32, reset u32) i32 {
	unsafe {
	if (usize(c) == 0) || !c.wrap {
		return i32(i32(Bw_error.bw_eproto))
	}
	if !(wifi_bp_read(d, c.wrap + u32(2048)) & u32(1)) {
		wifi_bp_write(d, c.wrap + u32(1032), pre | u32(3))
		wifi_bp_read(d, c.wrap + u32(1032))
		wifi_bp_write(d, c.wrap + u32(2048), u32(1))
		d.ops.delay_us(voidptr(d.cookie), u32(20))
		i := u32(0)
		for i = u32(0); i < u32(300); i++ {
			if wifi_bp_read(d, c.wrap + u32(2048)) & u32(1) {
				break
			}
		}
		if i == u32(300) {
			return i32(i32(Bw_error.bw_etime))
		}
	}
	wifi_bp_write(d, c.wrap + u32(1032), reset | u32(3))
	wifi_bp_read(d, c.wrap + u32(1032))
	return 0

	}
}

@[export: 'vinix_bw_core_core_reset']
pub fn wifi_core_reset(d &C.bw_device, c &C.bw_core, pre u32, reset u32, post u32) i32 {
	unsafe {
	e := wifi_core_disable(d, c, pre, reset)
	if e {
		return e
	}
	i := u32(0)
	for i = u32(0); i < u32(50); i++ {
		wifi_bp_write(d, c.wrap + u32(2048), u32(0))
		d.ops.delay_us(voidptr(d.cookie), u32(60))
		if !(wifi_bp_read(d, c.wrap + u32(2048)) & u32(1)) {
			break
		}
	}
	if i == u32(50) {
		return i32(i32(Bw_error.bw_etime))
	}
	wifi_bp_write(d, c.wrap + u32(1032), post | u32(1))
	wifi_bp_read(d, c.wrap + u32(1032))
	return 0

	}
}

@[export: 'vinix_bw_core_passive']
pub fn wifi_passive(d &C.bw_device) i32 {
	unsafe {
	c := wifi_core(d, 2119)
	e := wifi_core_reset(d, c, wifi_bp_read(d, c.wrap + u32(1032)) & u32(32), u32(32), u32(32))
	if e {
		return e
	}
	for i := u32(0); i < d.core_count; i++ {
		if u32(d.cores[i].id) == 2066 {
			e = wifi_core_disable(d,  &d.cores[0] + i , u32(12), u32(4))
			if e {
				return e
			}
		}
	}
	c = wifi_core(d, 2121)
	if wifi_bp_read(d, c.wrap + u32(2048)) & u32(1) {
		e = wifi_core_reset(d, c, u32(0), u32(0), u32(0))
		if e {
			return e
		}
	}
	return 0

	}
}

@[export: 'vinix_bw_core_pcie_off']
pub fn wifi_pcie_off(d &C.bw_device, old u32, newer u32) u32 {
	unsafe {
	return u32(8192) + (if i32(d.pcie_revision) >= 64 { newer } else { old })

	}
}

@[export: 'vinix_bw_core_bell']
pub fn wifi_bell(d &C.bw_device) {
	unsafe {
	wifi_wr(d, u32(Bw_space.bw_regs), wifi_pcie_off(d, u32(320), u32(2592)), u32(4), u32(1))

	}
}

@[export: 'vinix_bw_core_firmware_boot']
pub fn wifi_firmware_boot(d &C.bw_device, f &C.bw_firmware) i32 {
	unsafe {
	e := wifi_passive(d)
	if e {
		return e
	}
	link := wifi_rd(d, u32(Bw_space.bw_config), u32(188), u32(4))
	wifi_wr(d, u32(Bw_space.bw_config), u32(188), u32(4), link & ~3)
	wifi_bp_write(d, wifi_core(d, 2048).base + u32(128), u32(4))
	d.ops.delay_us(voidptr(d.cookie), u32(100000))
	wifi_wr(d, u32(Bw_space.bw_config), u32(188), u32(4), link & ~3)
	// no ASPM until suspend/resume exists

	e = wifi_passive(d)
	if e {
		return e
	}
	wifi_wr(d, u32(Bw_space.bw_regs), wifi_pcie_off(d, u32(76), u32(3124)), u32(4), u32(0))
	// polled; no MSI

	wifi_wr(d, u32(Bw_space.bw_regs), u32(8480), u32(4), u32(1248))
	bar2 := wifi_rd(d, u32(Bw_space.bw_regs), u32(8484), u32(4))
	wifi_wr(d, u32(Bw_space.bw_regs), u32(8484), u32(4), bar2)
	ram := wifi_core(d, 2121)
	banks := (wifi_bp_read(d, ram.base) >> 4) & u32(15)
	total := u32(0)

	for i := u32(0); i < banks; i++ {
		wifi_bp_write(d, ram.base + u32(16), i)
		total += ((wifi_bp_read(d, ram.base + u32(64)) & u32(127)) + u32(1)) * u32(8192)
	}
	if f.code_len < usize(116) || wifi_l32(voidptr(f.code + 108)) != u32(1397571922) {
		return i32(i32(Bw_error.bw_eproto))
	}
	d.ram_size = wifi_l32(voidptr(f.code + 112))
	if !total || d.ram_size > total || d.ram_size < u32(131072) || !wifi_range(d.ram_base, usize(d.ram_size), u32(0), d.tcm_size) || (d.ram_size & u32(3)) {
		return i32(i32(Bw_error.bw_eproto))
	}
	packed := C.bw_mem{}
	nvlen := usize(0)
	e = wifi_alloc_mem(d, usize(65536), &packed)
	if e {
		return e
	}
	e = bw_nvram_pack(f.nvram, f.nvram_len, packed.cpu, packed.len, &nvlen)
	if e {
		return e
	}
	if nvlen + usize(264) >= usize(d.ram_size) || f.code_len > usize(d.ram_size) - nvlen - usize(264) {
		return i32(i32(Bw_error.bw_enospc))
	}
	wifi_tcm_copy(d, d.ram_base, f.code, f.code_len)
	top := d.ram_base + d.ram_size
	nv := top - u32(nvlen)

	wifi_tcm_copy(d, nv, packed.cpu, nvlen)
	token := wifi_l32(voidptr(packed.cpu + nvlen - 4))
	wifi_wr(d, u32(Bw_space.bw_tcm), nv - u32(8), u32(4), u32(256))
	wifi_wr(d, u32(Bw_space.bw_tcm), nv - u32(4), u32(4), u32(4276994270))
	wifi_tcm_copy(d, nv - u32(264), f.seed, usize(256))
	wifi_wr(d, u32(Bw_space.bw_tcm), u32(0), u32(4), wifi_l32(voidptr(f.code)))
	e = wifi_core_reset(d, wifi_core(d, 2119), u32(32), u32(0), u32(0))
	if e {
		return e
	}
	for i := u32(0); i < u32(500); i++ {
		d.ops.delay_us(voidptr(d.cookie), u32(10000))
		shared_ := wifi_rd(d, u32(Bw_space.bw_tcm), top - u32(4), u32(4))
		if shared_ && shared_ != token {
			if (shared_ & u32(3)) || !wifi_ram_address(d, shared_, usize(116)) {
				return i32(i32(Bw_error.bw_eproto))
			}
			d.shared_ = shared_
			return 0
		}
	}
	return i32(i32(Bw_error.bw_etime))

	}
}

@[export: 'vinix_bw_core_index_read']
pub fn wifi_index_read(d &C.bw_device, r &C.bw_ring, writeindex i32) u16 {
	unsafe {
	a := if writeindex { r.wi } else { r.ri }
	if r.dma_indices {
		d.ops.sync(voidptr(d.cookie), voidptr(d.pool.cpu + a), usize(2), 0)
		return wifi_l16(voidptr(d.pool.cpu + a))
	}
	return u16(wifi_rd(d, u32(Bw_space.bw_tcm), a, u32(2)))

	}
}

@[export: 'vinix_bw_core_index_write']
pub fn wifi_index_write(d &C.bw_device, r &C.bw_ring, writeindex i32, v u16) {
	unsafe {
	a := if writeindex { r.wi } else { r.ri }
	if r.dma_indices {
		wifi_s16(voidptr(d.pool.cpu + a), v)
		d.ops.sync(voidptr(d.cookie), voidptr(d.pool.cpu + a), usize(2), 1)
	} else {
		wifi_wr(d, u32(Bw_space.bw_tcm), a, u32(2), u32(v))
	}

	}
}

@[export: 'vinix_bw_core_setup_ring']
pub fn wifi_setup_ring(d &C.bw_device, k u32, count u32, item u32, wi u32, ri u32, descriptor u32) i32 {
	unsafe {
	r :=  &d.rings[0] + k 
	r.count = u16(count)
	r.item = u16(item)
	r.wi = wi
	r.ri = ri
	r.dma_indices = u8(i32(d.index_size) != 0)
	e := wifi_alloc_mem(d, usize(count) * usize(item), &r.mem)
	if e {
		return e
	}
	wifi_index_write(d, r, 0, u16(0))
	wifi_index_write(d, r, 1, u16(0))
	if descriptor {
		wifi_wr(d, u32(Bw_space.bw_tcm), descriptor + u32(4), u32(2), count)
		wifi_wr(d, u32(Bw_space.bw_tcm), descriptor + u32(6), u32(2), item)
		wifi_wr(d, u32(Bw_space.bw_tcm), descriptor + u32(8), u32(4), u32(r.mem.dma))
		wifi_wr(d, u32(Bw_space.bw_tcm), descriptor + u32(12), u32(4), u32((r.mem.dma >> 32)))
	}
	return 0

	}
}

@[export: 'vinix_bw_core_submit']
pub fn wifi_submit(d &C.bw_device, k u32, msg &u8, n usize) i32 {
	unsafe {
	r :=  &d.rings[0] + k 
	if n > usize(r.item) || !r.count {
		return i32(i32(Bw_error.bw_einval))
	}
	ri := wifi_index_read(d, r, 0)
	if i32(ri) >= i32(r.count) {
		return wifi_fail(d, i32(i32(Bw_error.bw_eproto)))
	}
	next := u16(((i32(r.write) + 1) % i32(r.count)))
	if i32(next) == i32(ri) {
		return i32(i32(Bw_error.bw_enospc))
	}
	p := r.mem.cpu + (usize(r.write) * usize(r.item))
	C.memset(voidptr(p), 0, u64(r.item))
	C.memcpy(voidptr(p), voidptr(msg), n)
	d.ops.sync(voidptr(d.cookie), voidptr(p), usize(r.item), 1)
	r.write = next
	wifi_index_write(d, r, 1, next)
	wifi_bell(d)
	return 0

	}
}

@[export: 'vinix_bw_core_next_token']
pub fn wifi_next_token(d &C.bw_device) u32 {
	unsafe {
	t := d.next_token++
	if t == u32(65534) {
		mut __c2v_postfix_value_0 := d.next_token
		d.next_token++
		t = __c2v_postfix_value_0
	}
	if !t || !d.next_token {
		wifi_fail(d, i32(i32(Bw_error.bw_eproto)))
		return u32(0)
	}
	return t

	}
}

@[export: 'vinix_bw_core_post_one']
pub fn wifi_post_one(d &C.bw_device, i u32) i32 {
	unsafe {
	p :=  &d.rx[0] + i 
	m := [40]u8{}
	if p.owner {
		return 0
	}
	token := wifi_next_token(d)
	if !token {
		return i32(i32(Bw_error.bw_eproto))
	}
	m[0] = u8(if u32(p.kind) == 1 { 17 } else { (if u32(p.kind) == 2 { 11 } else { 13 }) })
	wifi_s32(voidptr( &m[0]  + 4), token)
	if u32(p.kind) == 1 {
		wifi_s16(voidptr( &m[0]  + 10), u16(p.mem.len))
		wifi_s64(voidptr( &m[0]  + 24), p.mem.dma)
	} else {
		wifi_s16(voidptr( &m[0]  + 8), u16(p.mem.len))
		wifi_s64(voidptr( &m[0]  + 16), p.mem.dma)
	}
	// Buffer is device-owned only after the descriptor has been published.

	d.ops.sync(voidptr(d.cookie), voidptr(p.mem.cpu), p.mem.len, 1)
	e := wifi_submit(d, u32(if u32(p.kind) == 1 { 1 } else { 0 }),  &m[0] , usize(if u32(p.kind) == 1 {
		32
	} else {
		40
	}))
	if !e {
		p.owner = u8(1)
		p.token = token
	}
	return e

	}
}

@[export: 'vinix_bw_core_replenish']
pub fn wifi_replenish(d &C.bw_device) i32 {
	unsafe {
	for i := u32(0); i < (512 + 2 * 8); i++ {
		if i32(d.rx[i].kind) && !d.rx[i].owner {
			e := wifi_post_one(d, i)
			if e == i32(Bw_error.bw_enospc) {
				return 0
			}
			if e {
				return e
			}
		}
	}
	return 0

	}
}

@[export: 'vinix_bw_core_rings_start']
pub fn wifi_rings_start(d &C.bw_device) i32 {
	unsafe {
	s := d.shared_
	d.flags = wifi_rd(d, u32(Bw_space.bw_tcm), s, u32(4))
	d.version = u8(d.flags)
	if i32(d.version) < 5 || i32(d.version) > 7 {
		return i32(i32(Bw_error.bw_enotsup))
	}
	d.rx_offset = wifi_rd(d, u32(Bw_space.bw_tcm), s + u32(36), u32(4))
	if d.rx_offset > u32(512) {
		return i32(i32(Bw_error.bw_eproto))
	}
	d.max_rx = u16(wifi_rd(d, u32(Bw_space.bw_tcm), s + u32(34), u32(2)))
	if !d.max_rx {
		d.max_rx = u16(255)
	}
	if u32(d.max_rx) > 512 {
		return i32(i32(Bw_error.bw_enospc))
	}
	d.h2d_mb = wifi_rd(d, u32(Bw_space.bw_tcm), s + u32(40), u32(4))
	d.d2h_mb = wifi_rd(d, u32(Bw_space.bw_tcm), s + u32(44), u32(4))
	d.ring_info = wifi_rd(d, u32(Bw_space.bw_tcm), s + u32(48), u32(4))
	if (d.ring_info & u32(3)) || !wifi_ram_address(d, d.ring_info, usize(60)) {
		return i32(i32(Bw_error.bw_eproto))
	}
	info := [60]u8{}
	for i := u32(0); i < u32(60); i += u32(4) {
		wifi_s32(voidptr( &info[0]  + i), wifi_rd(d, u32(Bw_space.bw_tcm), d.ring_info + i, u32(4)))
	}
	flows := u32(wifi_l16(voidptr( &info[0]  + 52)))
	d.submission_count = u16(if i32(d.version) >= 6 {
		i32(wifi_l16(voidptr( &info[0]  + 54)))
	} else {
		i32(u16(flows))
	})
	d.completion_count = u16(if i32(d.version) >= 6 {
		i32(wifi_l16(voidptr( &info[0]  + 56)))
	} else {
		3
	})
	if i32(d.submission_count) < 3 || i32(d.submission_count) > 1024 || i32(d.completion_count) < 3 || i32(d.completion_count) > 64 || !flows {
		return i32(i32(Bw_error.bw_eproto))
	}
	if i32(d.version) >= 6 && flows > u32(d.submission_count) - 2 {
		return i32(i32(Bw_error.bw_eproto))
	}
	descriptors := wifi_l32(voidptr( &info[0] ))
	if (descriptors & u32(3)) || !wifi_ram_address(d, descriptors, usize(80)) {
		return i32(i32(Bw_error.bw_eproto))
	}
	d.index_size = u8(if d.flags & u32(65536) {
		(if d.flags & u32(1048576) { 2 } else { 4 })
	} else {
		0
	})
	d.mb_via_ctl = u8(i32(d.version) >= 6 && !(d.flags & u32(33554432)))
	if !d.mb_via_ctl && ((d.h2d_mb & u32(3)) || (d.d2h_mb & u32(3)) || !wifi_ram_address(d, d.h2d_mb, usize(4)) || !wifi_ram_address(d, d.d2h_mb, usize(4))) {
		return i32(i32(Bw_error.bw_eproto))
	}
	stride := u32(if i32(d.index_size) { i32(d.index_size) } else { 4 })
	idx := [4]u32{}
	for i := u32(0); i < u32(4); i++ {
		count := u32(if i < u32(2) { i32(d.submission_count) } else { i32(d.completion_count) })
		if d.index_size {
			e := wifi_alloc_mem(d, usize(count) * usize(stride),  &d.indices[0] + i )
			if e {
				return e
			}
			idx[i] = u32((i64((isize(d.indices[i].cpu) - isize(d.pool.cpu)) / isize(sizeof(u8)))))
			wifi_wr(d, u32(Bw_space.bw_tcm), d.ring_info + u32(20) + u32(8) * i, u32(4), u32(d.indices[i].dma))
			wifi_wr(d, u32(Bw_space.bw_tcm), d.ring_info + u32(24) + u32(8) * i, u32(4), u32((d.indices[i].dma >> 32)))
		} else {
			idx[i] = wifi_l32(voidptr( &info[0]  + 4 + (u32(4) * i)))
			if (idx[i] & u32(3)) || !wifi_ram_address(d, idx[i], usize(count) * usize(stride)) {
				return i32(i32(Bw_error.bw_eproto))
			}
		}
	}
	counts := [u32(64), u32(1024), u32(64), u32(1024), u32(1024), u32(512)]!

	sizes := [u32(40), u32(32), u32(24), if i32(d.version) == 7 { 24 } else { 16 },
		if i32(d.version) == 7 { 40 } else { 32 }, u32(48)]!

	for k := u32(0); k < u32(6); k++ {
		i := if k < u32(2) { k } else { (if k == u32(5) { u32(2) } else { k - u32(2) }) }
		a := u32(if k < u32(2) || k == u32(5) { 0 } else { 2 })

		e := wifi_setup_ring(d, k, counts[k], sizes[k], idx[a] + i * stride, idx[a + u32(1)] + i * stride, if k < u32(5) {
			descriptors + u32(16) * k
		} else {
			u32(0)
		})
		if e {
			return e
		}
	}
	scratch := C.bw_mem{}
	updates := C.bw_mem{}

	e := wifi_alloc_mem(d, usize(8), &scratch)
	if e {
		return e
	}
	e = wifi_alloc_mem(d, usize(1024), &updates)
	if e || wifi_assign_error( &e , i32(wifi_alloc_mem(d, usize(8192), &d.request))) {
		return e
	}
	wifi_wr(d, u32(Bw_space.bw_tcm), s + u32(56), u32(4), u32(scratch.dma))
	wifi_wr(d, u32(Bw_space.bw_tcm), s + u32(60), u32(4), u32((scratch.dma >> 32)))
	wifi_wr(d, u32(Bw_space.bw_tcm), s + u32(52), u32(4), u32(8))
	wifi_wr(d, u32(Bw_space.bw_tcm), s + u32(68), u32(4), u32(updates.dma))
	wifi_wr(d, u32(Bw_space.bw_tcm), s + u32(72), u32(4), u32((updates.dma >> 32)))
	wifi_wr(d, u32(Bw_space.bw_tcm), s + u32(64), u32(4), u32(1024))
	for i := u32(0); i < (512 + 2 * 8); i++ {
		p :=  &d.rx[0] + i 
		p.kind = u8(if i < u32(d.max_rx) {
			1
		} else {
			(if i >= 512 { (if i < 512 + 8 { 2 } else { 3 }) } else { u32(0) })
		})
		if i32(p.kind) && wifi_assign_error( &e , i32(wifi_alloc_mem(d, usize(if u32(p.kind) == 1 {
			u32(2048)
		} else {
			8192
		}), &p.mem))) {
			return e
		}
	}
	for i := u32(0); i < 128; i++ {
		e = wifi_alloc_mem(d, usize(2048), &d.tx[i].mem)
		if e {
			return e
		}
	}
	if i32(d.version) >= 6 {
		cap := u32(d.version) | 4096
		if d.flags & u32(268435456) {
			cap |= u32(1024)
		}
		if d.flags & u32(2147483648) {
			cap |= u32(65536)
		}
		wifi_wr(d, u32(Bw_space.bw_tcm), s + u32(84), u32(4), cap)
		wifi_wr(d, u32(Bw_space.bw_tcm), s + u32(112), u32(4), u32(0))
	}
	if d.flags & u32(268435456) {
		wifi_wr(d, u32(Bw_space.bw_regs), wifi_pcie_off(d, u32(324), u32(2596)), u32(4), u32(1))
	}
	d.state = i32(Bw_state.bw_ready)
	return wifi_replenish(d)

	}
}

@[export: 'vinix_bw_core_find_packet']
pub fn wifi_find_packet(ps &C.bw_packet, count u32, token u32, kind u32) &C.bw_packet {
	unsafe {
	for i := u32(0); i < count; i++ {
		if i32(ps[i].owner) && ps[i].token == token && (!kind || u32(ps[i].kind) == kind) {
			return  ps + i 
		}
	}
	return  nil 

	}
}

@[export: 'vinix_bw_core_mailbox']
pub fn wifi_mailbox(d &C.bw_device, data u32) i32 {
	unsafe {
	if data & 268435456 {
		return wifi_fail(d, i32(i32(Bw_error.bw_eio)))
	}
	// Refuse deep sleep: there is no safe wake path in this polling driver.
	//     *Do not ACK a sleep request and then keep touching sleeping BARs.

	if data & 2 {
		return wifi_fail(d, i32(i32(Bw_error.bw_enotsup)))
	}
	return 0

	}
}

@[export: 'vinix_bw_core_same_network']
pub fn wifi_same_network(a &C.bw_network, ssid &u8, n usize, bssid &u8, secure i32) i32 {
	unsafe {
	if usize(a.ssid_len) != n || i32(a.secure) != i32(u8(secure)) {
		return 0
	}
	return if n {
		C.memcmp(a.ssid, voidptr(ssid), n) == 0
	} else {
		C.memcmp(a.bssid, voidptr(bssid), u64(6)) == 0
	}

	}
}

@[export: 'vinix_bw_core_scan_bss']
pub fn wifi_scan_bss(d &C.bw_device, p &u8, n usize) i32 {
	unsafe {
	// brcmf_bss_info_le version 109. Check the record's own length before
	//     *touching its fixed fields; information elements after byte 126 are not
	//     *needed by this deliberately small station UI.

	if n < usize(126) || wifi_l32(voidptr(p)) != u32(109) {
		return i32(i32(Bw_error.bw_eproto))
	}
	length := usize(wifi_l32(voidptr(p + 4)))
	ssid_len := usize(p[18])

	if length < usize(126) || length > n || ssid_len > usize(32) || !wifi_mac_ok(p + 8) {
		return i32(i32(Bw_error.bw_eproto))
	}
	secure := i32((i32(wifi_l16(voidptr(p + 16))) & 16) != 0)
	rssi := i16(wifi_l16(voidptr(p + 78)))
	channel := u16(if i32(p[88]) { i32(p[88]) } else { i32(u16((i32(wifi_l16(voidptr(p + 72))) & 255))) })
	if !channel || i32(channel) > 233 || i32(rssi) > 0 || i32(rssi) < -127 {
		return i32(i32(Bw_error.bw_eproto))
	}
	for i := u32(0); i < d.network_count; i++ {
		network :=  &d.networks[0] + i 
		if !wifi_same_network(network, p + 19, ssid_len, p + 8, secure) {
			continue
		}
		if i32(rssi) > i32(network.rssi) {
			network.rssi = rssi
			network.channel = channel
			C.memcpy(network.bssid, voidptr(p + 8), u64(6))
		}
		return 0
	}
	if d.network_count == 32 {
		return 0
	}
	network :=  &d.networks[0] + d.network_count++ 
	C.memset(voidptr(network), 0, sizeof(C.bw_network))
	network.ssid_len = u8(ssid_len)
	network.secure = u8(secure)
	network.channel = channel
	network.rssi = rssi
	C.memcpy(network.bssid, voidptr(p + 8), u64(6))
	C.memcpy(network.ssid, voidptr(p + 19), ssid_len)
	return 0

	}
}

@[export: 'vinix_bw_core_scan_event']
pub fn wifi_scan_event(d &C.bw_device, status u32, p &u8, n usize) i32 {
	unsafe {
	if !d.scan_pending {
		return 0
	}
	// a stale event from an aborted scan

	if status != u32(8) {
		d.scan_pending = u8(0)
		d.scan_error = if status {
			(if status <= 2147483647 { -i32(status) } else { i32(Bw_error.bw_eio) })
		} else {
			0
		}
		return 0
	}
	if n < usize(12) || i32(wifi_l16(voidptr(p + 8))) != i32(d.scan_sync) {
		return i32(i32(Bw_error.bw_eproto))
	}
	length := usize(wifi_l32(voidptr(p)))
	count := u32(wifi_l16(voidptr(p + 10)))
	if length < usize(12) || length > n || !count || count > 32 {
		return i32(i32(Bw_error.bw_eproto))
	}
	off := usize(12)
	for i := u32(0); i < count; i++ {
		if off > length || length - off < usize(8) {
			return i32(i32(Bw_error.bw_eproto))
		}
		record := usize(wifi_l32(voidptr(p + off + 4)))
		if !record || record > length - off {
			return i32(i32(Bw_error.bw_eproto))
		}
		e := wifi_scan_bss(d, p + off, record)
		if e {
			return e
		}
		off += record
	}
	return 0

	}
}

@[export: 'vinix_bw_core_event_message']
pub fn wifi_event_message(d &C.bw_device, p &u8, n usize) i32 {
	unsafe {
	mut __c2v_condition_19 := false
	mut __c2v_condition_20 := false
	__c2v_condition_20 = n < usize(72)
	__c2v_condition_19 = __c2v_condition_20
	if !__c2v_condition_19 {
		mut __c2v_condition_21 := false
		__c2v_condition_21 = i32(wifi_b16(voidptr(p + 12))) != 34924
		__c2v_condition_19 = __c2v_condition_21
	}
	if !__c2v_condition_19 {
		mut __c2v_condition_22 := false
		__c2v_condition_22 = i32(wifi_b16(voidptr(p + 14))) != 32769
		__c2v_condition_19 = __c2v_condition_22
	}
	if !__c2v_condition_19 {
		mut __c2v_condition_23 := false
		__c2v_condition_23 = i32(p[18]) != 0
		__c2v_condition_19 = __c2v_condition_23
	}
	if !__c2v_condition_19 {
		mut __c2v_condition_24 := false
		__c2v_condition_24 = C.memcmp(voidptr(p + 19), voidptr(c'\000\020\030'), u64(3))
		__c2v_condition_19 = __c2v_condition_24
	}
	if !__c2v_condition_19 {
		mut __c2v_condition_25 := false
		__c2v_condition_25 = i32(wifi_b16(voidptr(p + 22))) != 1
		__c2v_condition_19 = __c2v_condition_25
	}
	if !__c2v_condition_19 {
		mut __c2v_condition_26 := false
		__c2v_condition_26 = i32(wifi_b16(voidptr(p + 24))) != 2
		__c2v_condition_19 = __c2v_condition_26
	}
	if !__c2v_condition_19 {
		mut __c2v_condition_27 := false
		__c2v_condition_27 = i32(p[70]) != 0
		__c2v_condition_19 = __c2v_condition_27
	}
	if !__c2v_condition_19 {
		mut __c2v_condition_28 := false
		__c2v_condition_28 = i32(p[71]) != 0
		__c2v_condition_19 = __c2v_condition_28
	}
	if !__c2v_condition_19 {
		mut __c2v_condition_29 := false
		__c2v_condition_29 = usize(wifi_b32(voidptr(p + 44))) > n - usize(72)
		__c2v_condition_19 = __c2v_condition_29
	}
	if __c2v_condition_19 {
		return i32(i32(Bw_error.bw_eproto))
	}
	type_ := wifi_b32(voidptr(p + 28))
	status := wifi_b32(voidptr(p + 32))
	flags := u32(wifi_b16(voidptr(p + 26)))
	data_len := wifi_b32(voidptr(p + 44))

	if type_ == u32(69) {
		return wifi_scan_event(d, status, p + 72, usize(data_len))
	}
	if u32(d.state) != u32(i32(Bw_state.bw_joining)) && u32(d.state) != u32(i32(Bw_state.bw_link)) {
		return 0
	}
	if type_ == u32(0) {
		if status {
			return wifi_fail(d, i32(i32(Bw_error.bw_enolink)))
		}
		if !wifi_mac_ok(p + 48) {
			return i32(i32(Bw_error.bw_eproto))
		}
		C.memcpy(d.bssid, voidptr(p + 48), u64(6))
		d.associated = u8(1)
	} else if type_ == u32(46) {
		if status == u32(6) {
			d.keyed = u8(1)
		} else if status == u32(7) {
			return wifi_fail(d, i32(i32(Bw_error.bw_enolink)))
		}
	} else if type_ == u32(5) || type_ == u32(6) || type_ == u32(11) || type_ == u32(12) || (type_ == u32(16) && !(flags & u32(1))) {
		return wifi_fail(d, i32(i32(Bw_error.bw_enolink)))
	}
	if i32(d.associated) && i32(d.keyed) {
		d.state = i32(Bw_state.bw_link)
	}
	return 0

	}
}

@[export: 'vinix_bw_core_completion']
pub fn wifi_completion(d &C.bw_device, ring u32, m &u8, n usize) i32 {
	unsafe {
	type_ := u32(m[0])
	token := wifi_l32(voidptr(m + 4))
	p :=  &C.bw_packet(nil) 
	if i32(m[1]) != 0 && type_ != u32(36) {
		return i32(i32(Bw_error.bw_eproto))
	}
	if ring == u32(2) {
		if type_ == u32(1) || type_ == u32(2) {
			return if i32(wifi_l16(voidptr(m + 8))) { i32(Bw_error.bw_eio) } else { 0 }
		}
		if type_ == u32(10) {
			if token != 65534 || !d.request_busy || i32(wifi_l16(voidptr(m + 8))) {
				return i32(i32(Bw_error.bw_eproto))
			}
			d.request_busy = u8(0)
			return 0
		}
		if type_ == u32(4) {
			if !d.flow_pending || i32(wifi_l16(voidptr(m + 10))) != 2 || i32(wifi_l16(voidptr(m + 8))) {
				return i32(i32(Bw_error.bw_eproto))
			}
			d.flow_open = u8(1)
			d.flow_pending = u8(0)
			return 0
		}
		if type_ == u32(36) {
			return wifi_mailbox(d, wifi_l32(voidptr(m + 12)))
		}
		if type_ != u32(12) && type_ != u32(14) {
			return i32(i32(Bw_error.bw_eproto))
		}
		p = wifi_find_packet(&d.rx[0], (512 + 2 * 8), token, if type_ == u32(12) { 2 } else { 3 })
		if usize(p) == 0 {
			return i32(i32(Bw_error.bw_eproto))
		}
		d.ops.sync(voidptr(d.cookie), voidptr(p.mem.cpu), p.mem.len, 0)
		len := usize(wifi_l16(voidptr(m + 12)))
		off := usize(if type_ == u32(14) { d.rx_offset } else { u32(0) })

		if off > p.mem.len || len > p.mem.len - off {
			return i32(i32(Bw_error.bw_eproto))
		}
		e := i32(0)
		if type_ == u32(12) {
			if i32(d.reply_ready) || i32(wifi_l16(voidptr(m + 14))) != i32(d.transaction) || wifi_l32(voidptr(m + 16)) != d.reply_command {
				return i32(i32(Bw_error.bw_eproto))
			}
			C.memcpy(d.reply, voidptr(p.mem.cpu), len)
			d.reply_length = u16(len)
			d.reply_status = i16(wifi_l16(voidptr(m + 8)))
			d.reply_ready = u8(1)
		} else if !wifi_l16(voidptr(m + 8)) {
			e = wifi_event_message(d, p.mem.cpu + off, len)
		}
		p.owner = u8(0)
		return e
	}
	if ring == u32(3) {
		if type_ != u32(16) || n < usize(16) || i32(wifi_l16(voidptr(m + 10))) != 2 {
			return i32(i32(Bw_error.bw_eproto))
		}
		p = wifi_find_packet(&d.tx[0], 128, token, u32(0))
		if usize(p) == 0 {
			return i32(i32(Bw_error.bw_eproto))
		}
		d.ops.sync(voidptr(d.cookie), voidptr(p.mem.cpu), p.mem.len, 0)
		p.owner = u8(0)
		if !wifi_l16(voidptr(m + 8)) && !wifi_l16(voidptr(m + 14)) {
			d.tx_frames++
		}
		return 0
	}
	if ring != u32(4) || type_ != u32(18) || n < usize(32) {
		return i32(i32(Bw_error.bw_eproto))
	}
	p = wifi_find_packet(&d.rx[0], (512 + 2 * 8), token, 1)
	if usize(p) == 0 {
		return i32(i32(Bw_error.bw_eproto))
	}
	len := usize(wifi_l16(voidptr(m + 14)))
	off := usize(wifi_l16(voidptr(m + 16)))

	if !off {
		off = usize(d.rx_offset)
	}
	if off > p.mem.len || len > p.mem.len - off {
		return i32(i32(Bw_error.bw_eproto))
	}
	d.ops.sync(voidptr(d.cookie), voidptr(p.mem.cpu), p.mem.len, 0)
	// Only authenticated data, never vendor-event interpretation of RX data.

	if !wifi_l16(voidptr(m + 8)) && u32(d.state) == u32(i32(Bw_state.bw_link)) && len >= usize(14) && len <= usize(1514) && i32(wifi_b16(voidptr(p.mem.cpu + off + 12))) != 34924 {
		d.ops.receive(voidptr(d.cookie), &C.bw_const_byte(p.mem.cpu + off), len)
		d.rx_frames++
	}
	p.owner = u8(0)
	return 0

	}
}

@[export: 'bw_poll']
pub fn bw_poll(d &C.bw_device, budget u32) i32 {
	unsafe {
	if usize(d) == 0 {
		return i32(i32(Bw_error.bw_einval))
	}
	if u32(d.state) == u32(i32(Bw_state.bw_fault)) {
		return d.error
	}
	if u32(d.state) < u32(i32(Bw_state.bw_ready)) {
		return 0
	}
	if budget > u32(256) {
		budget = u32(256)
	}
	if !d.mb_via_ctl {
		m := wifi_rd(d, u32(Bw_space.bw_tcm), d.d2h_mb, u32(4))
		if m {
			wifi_wr(d, u32(Bw_space.bw_tcm), d.d2h_mb, u32(4), u32(0))
			e := wifi_mailbox(d, m)
			if e {
				return e
			}
		}
	}
	done := u32(0)
	for k := u32(2); k < u32(5) && done < budget; k++ {
		r :=  &d.rings[0] + k 
		wi := wifi_index_read(d, r, 1)
		if i32(wi) >= i32(r.count) {
			return wifi_fail(d, i32(i32(Bw_error.bw_eproto)))
		}
		for i32(r.read) != i32(wi) && done < budget {
			m := [40]u8{}
			p := r.mem.cpu + (usize(r.read) * usize(r.item))
			d.ops.sync(voidptr(d.cookie), voidptr(p), usize(r.item), 0)
			C.memcpy(voidptr( &m[0] ), voidptr(p), u64(r.item))
			e := wifi_completion(d, k,  &m[0] , usize(r.item))
			if e {
				d.bad_completions++
				return wifi_fail(d, e)
			}
			r.read = u16(((i32(r.read) + 1) % i32(r.count)))
			done++
		}
		wifi_index_write(d, r, 0, r.read)
	}
	now := d.ops.time_us(voidptr(d.cookie))
	if i32(d.scan_pending) && now >= d.scan_deadline {
		d.scan_pending = u8(0)
		d.scan_error = i32(Bw_error.bw_etime)
	}
	if (u32(d.state) == u32(i32(Bw_state.bw_joining)) && now >= d.join_deadline) || (i32(d.flow_pending) && now >= d.flow_deadline) {
		return wifi_fail(d, i32(i32(Bw_error.bw_etime)))
	}
	e := wifi_replenish(d)
	return if e { e } else { i32(done) }

	}
}

@[export: 'vinix_bw_core_command']
pub fn wifi_command(d &C.bw_device, cmd u32, in_ voidptr, inlen usize, out voidptr, cap usize, actual &usize) i32 {
	unsafe {
	mut __c2v_condition_30 := false
	mut __c2v_condition_31 := false
	__c2v_condition_31 = u32(d.state) < u32(i32(Bw_state.bw_ready))
	__c2v_condition_30 = __c2v_condition_31
	if !__c2v_condition_30 {
		mut __c2v_condition_32 := false
		__c2v_condition_32 = u32(d.state) == u32(i32(Bw_state.bw_fault))
		__c2v_condition_30 = __c2v_condition_32
	}
	if !__c2v_condition_30 {
		mut __c2v_condition_33 := false
		__c2v_condition_33 = inlen > usize(8192)
		__c2v_condition_30 = __c2v_condition_33
	}
	if !__c2v_condition_30 {
		mut __c2v_condition_34 := false
		__c2v_condition_34 = cap > usize(8192)
		__c2v_condition_30 = __c2v_condition_34
	}
	if !__c2v_condition_30 {
		mut __c2v_condition_35 := false
		__c2v_condition_35 = i32(d.request_busy)
		__c2v_condition_30 = __c2v_condition_35
	}
	if !__c2v_condition_30 {
		mut __c2v_condition_36 := false
		__c2v_condition_36 = ((usize(in_) == 0) && inlen)
		__c2v_condition_30 = __c2v_condition_36
	}
	if !__c2v_condition_30 {
		mut __c2v_condition_37 := false
		__c2v_condition_37 = ((usize(out) == 0) && cap)
		__c2v_condition_30 = __c2v_condition_37
	}
	if __c2v_condition_30 {
		return i32(i32(Bw_error.bw_einval))
	}
	if i32(d.transaction) == 65535 {
		return wifi_fail(d, i32(i32(Bw_error.bw_eproto)))
	}
	// never alias stale replies

	d.transaction++
	d.reply_command = cmd
	d.reply_ready = u8(0)
	d.reply_length = u16(0)
	C.memset(voidptr(d.request.cpu), 0, d.request.len)
	if inlen {
		C.memcpy(voidptr(d.request.cpu), voidptr(in_), inlen)
	}
	d.ops.sync(voidptr(d.cookie), voidptr(d.request.cpu), d.request.len, 1)
	m := [u8(9), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
		u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
		u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
		u8(0)]!

	wifi_s32(voidptr( &m[0]  + 4), u32(65534))
	wifi_s32(voidptr( &m[0]  + 8), cmd)
	wifi_s16(voidptr( &m[0]  + 12), d.transaction)
	wifi_s16(voidptr( &m[0]  + 14), u16(inlen))
	wifi_s16(voidptr( &m[0]  + 16), u16((if cap { cap } else { inlen })))
	wifi_s64(voidptr( &m[0]  + 24), d.request.dma)
	e := wifi_submit(d, u32(0),  &m[0] , sizeof([40]u8))
	if e {
		return e
	}
	d.request_busy = u8(1)
	for i := u32(0); i < u32(20000); i++ {
		e = bw_poll(d, u32(128))
		if e < 0 {
			return e
		}
		if i32(d.reply_ready) && !d.request_busy {
			count := usize(d.reply_length)
			if cap && count > cap {
				return wifi_fail(d, i32(i32(Bw_error.bw_eproto)))
			}
			if cap {
				C.memcpy(voidptr(out), d.reply, count)
			}
			if actual {
				 *actual = count 
			}
			e = if i32(d.reply_status) { i32(Bw_error.bw_eio) } else { 0 }
			wifi_erase(voidptr(d.request.cpu), d.request.len)
			d.ops.sync(voidptr(d.cookie), voidptr(d.request.cpu), d.request.len, 1)
			wifi_erase(d.reply, sizeof([8192]u8))
			d.reply_ready = u8(0)
			return e
		}
		d.ops.delay_us(voidptr(d.cookie), u32(100))
	}
	// The firmware could still DMA the input buffer. Quiesce, don't reuse it.

	return wifi_fail(d, i32(i32(Bw_error.bw_etime)))

	}
}

@[export: 'vinix_bw_core_var_set']
pub fn wifi_var_set(d &C.bw_device, name &char, data voidptr, n usize) i32 {
	unsafe {
	b := [8192]u8{}
	k := usize(0)
	for k < usize(64) && i32(name[k]) {
		k++
	}
	k++
	if k > usize(64) || n > sizeof([8192]u8) - k {
		return i32(i32(Bw_error.bw_einval))
	}
	C.memcpy(voidptr( &b[0] ), voidptr(name), k)
	if n {
		C.memcpy(voidptr( &b[0]  + k), voidptr(data), n)
	}
	e := wifi_command(d, 263, voidptr( &b[0] ), k + n, voidptr((voidptr(0))), usize(0), (voidptr(0)))
	wifi_erase(voidptr( &b[0] ), k + n)
	return e

	}
}

@[export: 'vinix_bw_core_var_int']
pub fn wifi_var_int(d &C.bw_device, name &char, val u32) i32 {
	unsafe {
	b := [4]u8{}
	wifi_s32(voidptr( &b[0] ), val)
	return wifi_var_set(d, name, voidptr( &b[0] ), usize(4))

	}
}

@[export: 'vinix_bw_core_cmd_int']
pub fn wifi_cmd_int(d &C.bw_device, cmd u32, val u32) i32 {
	unsafe {
	b := [4]u8{}
	wifi_s32(voidptr( &b[0] ), val)
	return wifi_command(d, cmd, voidptr( &b[0] ), usize(4), voidptr((voidptr(0))), usize(0), (voidptr(0)))

	}
}

@[export: 'vinix_bw_core_download_blob']
pub fn wifi_download_blob(d &C.bw_device, name &char, p &u8, n usize) i32 {
	unsafe {
	b := [1412]u8{}
	off := usize(0)
	if (usize(p) == 0) || !n || n > usize(1024 * 1024) {
		return i32(i32(Bw_error.bw_einval))
	}
	for off < n {
		take := n - off
		if take > usize(1400) {
			take = usize(1400)
		}
		C.memset(voidptr( &b[0] ), 0, u64(12))
		wifi_s16(voidptr( &b[0] ), u16((4096 | (if off == usize(0) { 2 } else { 0 }) | (if off + take == n {
			4
		} else {
			0
		}))))
		wifi_s16(voidptr( &b[0]  + 2), u16(2))
		wifi_s32(voidptr( &b[0]  + 4), u32(take))
		C.memcpy(voidptr( &b[0]  + 12), voidptr(p + off), take)
		e := wifi_var_set(d, name, voidptr( &b[0] ), take + usize(12))
		if e {
			return e
		}
		off += take
	}
	return 0

	}
}

@[export: 'bw_start']
pub fn bw_start(d &C.bw_device, f &C.bw_firmware) i32 {
	unsafe {
	mut __c2v_condition_38 := false
	mut __c2v_condition_39 := false
	__c2v_condition_39 = (usize(d) == 0)
	__c2v_condition_38 = __c2v_condition_39
	if !__c2v_condition_38 {
		mut __c2v_condition_40 := false
		__c2v_condition_40 = (usize(f) == 0)
		__c2v_condition_38 = __c2v_condition_40
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_41 := false
		__c2v_condition_41 = u32(d.state) != u32(i32(Bw_state.bw_chip))
		__c2v_condition_38 = __c2v_condition_41
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_42 := false
		__c2v_condition_42 = (usize(f.code) == 0)
		__c2v_condition_38 = __c2v_condition_42
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_43 := false
		__c2v_condition_43 = (usize(f.nvram) == 0)
		__c2v_condition_38 = __c2v_condition_43
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_44 := false
		__c2v_condition_44 = (usize(f.clm) == 0)
		__c2v_condition_38 = __c2v_condition_44
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_45 := false
		__c2v_condition_45 = (usize(f.txcap) == 0)
		__c2v_condition_38 = __c2v_condition_45
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_46 := false
		__c2v_condition_46 = (usize(f.calibration) == 0)
		__c2v_condition_38 = __c2v_condition_46
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_47 := false
		__c2v_condition_47 = (usize(f.seed) == 0)
		__c2v_condition_38 = __c2v_condition_47
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_48 := false
		__c2v_condition_48 = f.seed_len != usize(256)
		__c2v_condition_38 = __c2v_condition_48
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_49 := false
		__c2v_condition_49 = !wifi_mac_ok(&f.mac[0])
		__c2v_condition_38 = __c2v_condition_49
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_50 := false
		__c2v_condition_50 = i32(f.silicon_revision) != i32(d.revision)
		__c2v_condition_38 = __c2v_condition_50
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_51 := false
		__c2v_condition_51 = f.code_len > usize(4 * 1024 * 1024)
		__c2v_condition_38 = __c2v_condition_51
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_52 := false
		__c2v_condition_52 = !f.nvram_len
		__c2v_condition_38 = __c2v_condition_52
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_53 := false
		__c2v_condition_53 = f.nvram_len > usize(65536)
		__c2v_condition_38 = __c2v_condition_53
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_54 := false
		__c2v_condition_54 = !f.clm_len
		__c2v_condition_38 = __c2v_condition_54
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_55 := false
		__c2v_condition_55 = f.clm_len > usize(1024 * 1024)
		__c2v_condition_38 = __c2v_condition_55
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_56 := false
		__c2v_condition_56 = !f.txcap_len
		__c2v_condition_38 = __c2v_condition_56
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_57 := false
		__c2v_condition_57 = f.txcap_len > usize(1024 * 1024)
		__c2v_condition_38 = __c2v_condition_57
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_58 := false
		__c2v_condition_58 = !f.calibration_len
		__c2v_condition_38 = __c2v_condition_58
	}
	if !__c2v_condition_38 {
		mut __c2v_condition_59 := false
		__c2v_condition_59 = f.calibration_len > usize(1024 * 1024)
		__c2v_condition_38 = __c2v_condition_59
	}
	if __c2v_condition_38 {
		return i32(i32(Bw_error.bw_einval))
	}
	d.state = i32(Bw_state.bw_booting)
	e := wifi_firmware_boot(d, f)
	if e {
		return wifi_fail(d, e)
	}
	e = wifi_rings_start(d)
	if e {
		return wifi_fail(d, e)
	}
	C.memcpy(d.mac, f.mac, u64(6))
	e = wifi_var_set(d, c'cur_etheraddr', f.mac, usize(6))
	mut __c2v_condition_60 := false
	mut __c2v_condition_61 := false
	__c2v_condition_61 = e
	__c2v_condition_60 = __c2v_condition_61
	if !__c2v_condition_60 {
		mut __c2v_condition_62 := false
		__c2v_condition_62 = wifi_assign_error( &e , i32(wifi_download_blob(d, c'clmload', f.clm, f.clm_len)))
		__c2v_condition_60 = __c2v_condition_62
	}
	if !__c2v_condition_60 {
		mut __c2v_condition_63 := false
		__c2v_condition_63 = wifi_assign_error( &e , i32(wifi_download_blob(d, c'txcapload', f.txcap, f.txcap_len)))
		__c2v_condition_60 = __c2v_condition_63
	}
	if !__c2v_condition_60 {
		mut __c2v_condition_64 := false
		__c2v_condition_64 = wifi_assign_error( &e , i32(wifi_download_blob(d, c'calload', f.calibration, f.calibration_len)))
		__c2v_condition_60 = __c2v_condition_64
	}
	if !__c2v_condition_60 {
		mut __c2v_condition_65 := false
		__c2v_condition_65 = wifi_assign_error( &e , i32(wifi_var_int(d, c'mpc', u32(0))))
		__c2v_condition_60 = __c2v_condition_65
	}
	if !__c2v_condition_60 {
		mut __c2v_condition_66 := false
		__c2v_condition_66 = wifi_assign_error( &e , i32(wifi_cmd_int(d, u32(86), u32(0))))
		__c2v_condition_60 = __c2v_condition_66
	}
	if !__c2v_condition_60 {
		mut __c2v_condition_67 := false
		__c2v_condition_67 = wifi_assign_error( &e , i32(wifi_cmd_int(d, u32(20), u32(1))))
		__c2v_condition_60 = __c2v_condition_67
	}
	if __c2v_condition_60 {
		return wifi_fail(d, e)
	}
	events := [16]u8{}
	types := [u32(0), u32(5), u32(6), u32(11), u32(12), u32(16), u32(46)]!

	for i := u32(0); u64(i) < 7; i++ {
		events[types[i] / u32(8)] |= i32(u8((1 << (types[i] % u32(8)))))
	}
	events[69 / 8] |= i32(u8((1 << (69 % 8))))
	e = wifi_var_set(d, c'event_msgs', voidptr( &events[0] ), sizeof([16]u8))
	if e || wifi_assign_error( &e , i32(wifi_cmd_int(d, u32(2), u32(1)))) {
		return wifi_fail(d, e)
	}
	d.radio_on = u8(1)
	return 0

	}
}

@[export: 'bw_radio']
pub fn bw_radio(d &C.bw_device, enabled i32) i32 {
	unsafe {
	if (usize(d) == 0) || (enabled != 0 && enabled != 1) || u32(d.state) < u32(i32(Bw_state.bw_ready)) || u32(d.state) == u32(i32(Bw_state.bw_fault)) {
		return i32(i32(Bw_error.bw_einval))
	}
	if i32(d.radio_on) == i32(u8(enabled)) {
		return 0
	}
	if !enabled {
		// Ignore link-loss events caused by taking the radio down. The firmware
		//         *and rings stay alive, so WLC_UP can reverse this without a reboot.

		d.state = i32(Bw_state.bw_ready)
		d.scan_pending = u8(0)
		d.keyed = d.scan_pending
		d.associated = d.keyed
		d.radio_on = u8(0)
		e := wifi_cmd_int(d, u32(3), u32(1))
		return if e { wifi_fail(d, e) } else { 0 }
	}
	e := wifi_cmd_int(d, u32(2), u32(1))
	if e {
		return wifi_fail(d, e)
	}
	d.radio_on = u8(1)
	return 0

	}
}

@[export: 'bw_scan']
pub fn bw_scan(d &C.bw_device) i32 {
	unsafe {
	if (usize(d) == 0) || (u32(d.state) != u32(i32(Bw_state.bw_ready)) && u32(d.state) != u32(i32(Bw_state.bw_link))) || !d.radio_on || i32(d.scan_pending) {
		return i32(i32(Bw_error.bw_einval))
	}
	p := [72]u8{}
	d.scan_sync++
	if i32(d.scan_sync) == 0 {
		d.scan_sync++
	}
	wifi_s32(voidptr( &p[0] ), u32(1))
	wifi_s16(voidptr( &p[0]  + 4), u16(1))
	wifi_s16(voidptr( &p[0]  + 6), d.scan_sync)
	C.memset(voidptr( &p[0]  + 44), 255, u64(6))
	p[50] = u8(2)
	p[51] = u8(255)
	wifi_s32(voidptr( &p[0]  + 52), u32(4294967295))
	wifi_s32(voidptr( &p[0]  + 56), u32(4294967295))
	wifi_s32(voidptr( &p[0]  + 60), u32(4294967295))
	wifi_s32(voidptr( &p[0]  + 64), u32(4294967295))
	C.memset(d.networks, 0, sizeof([32]C.bw_network))
	d.network_count = u32(0)
	d.scan_error = 0
	d.scan_pending = u8(1)
	d.scan_deadline = d.ops.time_us(voidptr(d.cookie)) + u64(15000000)
	e := wifi_var_set(d, c'escan', voidptr( &p[0] ), sizeof([72]u8))
	wifi_erase(voidptr( &p[0] ), sizeof([72]u8))
	if e {
		d.scan_pending = u8(0)
		d.scan_error = e
	}
	return e

	}
}

@[export: 'bw_networks']
pub fn bw_networks(d &C.bw_device, out &u8, capacity usize) i32 {
	unsafe {
	if (usize(d) == 0) || (usize(out) == 0) || capacity < usize((16 + 32 * 48)) {
		return i32(i32(Bw_error.bw_einval))
	}
	C.memset(voidptr(out), 0, u64((16 + 32 * 48)))
	wifi_s32(voidptr(out), u32(1))
	wifi_s32(voidptr(out + 4), d.network_count)
	wifi_s32(voidptr(out + 8), u32(d.scan_pending))
	wifi_s32(voidptr(out + 12), u32(d.scan_error))
	for i := u32(0); i < d.network_count; i++ {
		network :=  &d.networks[0] + i 
		entry := out + 16 + (i * 48)
		entry[0] = network.ssid_len
		entry[1] = network.secure
		wifi_s16(voidptr(entry + 2), network.channel)
		wifi_s16(voidptr(entry + 4), u16(network.rssi))
		C.memcpy(voidptr(entry + 8), network.bssid, u64(6))
		C.memcpy(voidptr(entry + 16), network.ssid, u64(network.ssid_len))
	}
	return 0

	}
}

@[export: 'bw_join_wpa2']
pub fn bw_join_wpa2(d &C.bw_device, ssid &u8, sn usize, pass &u8, pn usize) i32 {
	unsafe {
	if (usize(d) == 0) || u32(d.state) != u32(i32(Bw_state.bw_ready)) || !d.radio_on || i32(d.scan_pending) || (usize(ssid) == 0) || !sn || sn > usize(32) || (usize(pass) == 0) || pn < usize(8) || pn > usize(63) {
		return i32(i32(Bw_error.bw_einval))
	}
	for i := usize(0); i < pn; i++ {
		if i32(pass[i]) < 32 || i32(pass[i]) > 126 {
			return i32(i32(Bw_error.bw_einval))
		}
	}
	// RSN IE: WPA2-PSK + CCMP only; never fall back to an open network.

	bw_join_wpa2_rsn := [u8(48), u8(20), u8(1), u8(0), u8(0), u8(15), u8(172), u8(4), u8(1),
			u8(0), u8(0), u8(15), u8(172), u8(4), u8(1), u8(0), u8(0), u8(15), u8(172), u8(2),
			u8(0), u8(0)]!

	e := i32(0)
	e = wifi_var_int(d, c'auth', u32(0))
	mut __c2v_condition_68 := false
	mut __c2v_condition_69 := false
	__c2v_condition_69 = e
	__c2v_condition_68 = __c2v_condition_69
	if !__c2v_condition_68 {
		mut __c2v_condition_70 := false
		__c2v_condition_70 = wifi_assign_error( &e , i32(wifi_var_int(d, c'wsec', u32(4))))
		__c2v_condition_68 = __c2v_condition_70
	}
	if !__c2v_condition_68 {
		mut __c2v_condition_71 := false
		__c2v_condition_71 = wifi_assign_error( &e , i32(wifi_var_int(d, c'wpa_auth', u32(128))))
		__c2v_condition_68 = __c2v_condition_71
	}
	if !__c2v_condition_68 {
		mut __c2v_condition_72 := false
		__c2v_condition_72 = wifi_assign_error( &e , i32(wifi_var_int(d, c'mfp', u32(0))))
		__c2v_condition_68 = __c2v_condition_72
	}
	if !__c2v_condition_68 {
		mut __c2v_condition_73 := false
		__c2v_condition_73 = wifi_assign_error( &e , i32(wifi_var_set(d, c'wpaie', voidptr( &bw_join_wpa2_rsn[0] ), sizeof([22]u8))))
		__c2v_condition_68 = __c2v_condition_73
	}
	if !__c2v_condition_68 {
		mut __c2v_condition_74 := false
		__c2v_condition_74 = wifi_assign_error( &e , i32(wifi_var_int(d, c'sup_wpa', u32(1))))
		__c2v_condition_68 = __c2v_condition_74
	}
	if __c2v_condition_68 {
		return wifi_fail(d, e)
	}
	pmk := [68]u8{}
	wifi_s16(voidptr( &pmk[0] ), u16(pn))
	wifi_s16(voidptr( &pmk[0]  + 2), u16(1))
	C.memcpy(voidptr( &pmk[0]  + 4), voidptr(pass), pn)
	e = wifi_command(d, u32(268), voidptr( &pmk[0] ), sizeof([68]u8), voidptr((voidptr(0))), usize(0), (voidptr(0)))
	wifi_erase(voidptr( &pmk[0] ), sizeof([68]u8))
	if e {
		return wifi_fail(d, e)
	}
	join := [36]u8{}
	wifi_s32(voidptr( &join[0] ), u32(sn))
	C.memcpy(voidptr( &join[0]  + 4), voidptr(ssid), sn)
	d.keyed = u8(0)
	d.associated = d.keyed
	d.state = i32(Bw_state.bw_joining)
	d.join_deadline = d.ops.time_us(voidptr(d.cookie)) + u64(30000000)
	e = wifi_command(d, u32(26), voidptr( &join[0] ), sizeof([36]u8), voidptr((voidptr(0))), usize(0), (voidptr(0)))
	return if e { wifi_fail(d, e) } else { 0 }

	}
}

@[export: 'bw_transmit']
pub fn bw_transmit(d &C.bw_device, p &u8, n usize) i32 {
	unsafe {
	if (usize(d) == 0) || (usize(p) == 0) || n < usize(14) || n > usize(1514) {
		return i32(i32(Bw_error.bw_einval))
	}
	if u32(d.state) != u32(i32(Bw_state.bw_link)) {
		return i32(i32(Bw_error.bw_enolink))
	}
	if C.memcmp(voidptr(p + 6), d.mac, u64(6)) {
		return i32(i32(Bw_error.bw_einval))
	}
	if !d.flow_open {
		if d.flow_pending {
			return i32(i32(Bw_error.bw_enospc))
		}
		c := [u8(3), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
			u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
			u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
			u8(0), u8(0), u8(0), u8(0)]!

		C.memcpy(voidptr( &c[0]  + 8), voidptr(p), u64(6))
		C.memcpy(voidptr( &c[0]  + 14), d.mac, u64(6))
		wifi_s16(voidptr( &c[0]  + 22), u16(2))
		wifi_s16(voidptr( &c[0]  + 28), u16(512))
		wifi_s16(voidptr( &c[0]  + 30), u16(48))
		wifi_s64(voidptr( &c[0]  + 32), d.rings[5].mem.dma)
		e := wifi_submit(d, u32(0),  &c[0] , sizeof([40]u8))
		if e {
			return e
		}
		d.flow_pending = u8(1)
		d.flow_deadline = d.ops.time_us(voidptr(d.cookie)) + u64(2000000)
		return i32(i32(Bw_error.bw_enospc))
	}
	t :=  &C.bw_packet(nil) 
	for i := u32(0); i < 128; i++ {
		if !d.tx[i].owner {
			t =  &d.tx[0] + i 
			break
		}
	}
	if usize(t) == 0 {
		return i32(i32(Bw_error.bw_enospc))
	}
	token := wifi_next_token(d)
	if !token {
		return i32(i32(Bw_error.bw_eproto))
	}
	C.memcpy(voidptr(t.mem.cpu), voidptr(p), n)
	d.ops.sync(voidptr(d.cookie), voidptr(t.mem.cpu), n, 1)
	m := [u8(15), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
		u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
		u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0),
		u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0), u8(0)]!

	wifi_s32(voidptr( &m[0]  + 4), token)
	C.memcpy(voidptr( &m[0]  + 8), voidptr(p), u64(14))
	m[22] = u8(1)
	m[23] = u8(1)
	wifi_s64(voidptr( &m[0]  + 32), t.mem.dma + u64(14))
	wifi_s16(voidptr( &m[0]  + 42), u16((n - usize(14))))
	e := wifi_submit(d, u32(5),  &m[0] , sizeof([48]u8))
	if !e {
		t.owner = u8(1)
		t.token = token
	}
	return e

	}
}

@[export: 'bw_disconnect']
pub fn bw_disconnect(d &C.bw_device) i32 {
	unsafe {
	if (usize(d) == 0) || u32(d.state) < u32(i32(Bw_state.bw_ready)) || u32(d.state) == u32(i32(Bw_state.bw_fault)) {
		return i32(i32(Bw_error.bw_einval))
	}
	e := wifi_command(d, u32(52), voidptr((voidptr(0))), usize(0), voidptr((voidptr(0))), usize(0), (voidptr(0)))
	bw_stop(d)
	return e

	}
}

@[export: 'bw_stop']
pub fn bw_stop(d &C.bw_device) {
	unsafe {
	if usize(d) == 0 {
		return
	}
	d.ops.stop_dma(voidptr(d.cookie))
	d.scan_pending = u8(0)
	d.radio_on = d.scan_pending
	d.keyed = d.radio_on
	d.associated = d.keyed
	d.state = i32(Bw_state.bw_fault)
	d.error = i32(Bw_error.bw_enolink)

	}
}

@[export: 'bw_state_name']
pub fn bw_state_name(s i32) &char {
	unsafe {
	return match i32(s) {
	0 { c'off' }
	1 { c'chip detected' }
	2 { c'firmware boot' }
	3 { c'firmware ready' }
	4 { c'authenticating' }
	5 { c'authenticated link' }
	6 { c'stopped' }
	else { c'invalid' }
	}

	}
}

@[export: 'vinix_bw_core_assign_error']
pub fn wifi_assign_error(p &i32, value i32) i32 {
	unsafe { *p = value; return value 
	}
}

@[export: 'vinix_bw_core_increment_lines']
pub fn wifi_increment_lines(p &u32, delta u32) u32 {
	unsafe { *p += delta; return *p 
	}
}

fn is_null(p voidptr) bool { return usize(p) == 0 }
