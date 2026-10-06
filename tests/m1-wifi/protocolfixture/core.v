// SPDX-License-Identifier: ISC
// Independent firmware/ring machine, retaining the original byte-level oracle.
@[has_globals; translated]
module protocolfixture

#include "protocol-native-abi.h"

type ReadFn = fn (voidptr, u32, u32, u32) u32
type WriteFn = fn (voidptr, u32, u32, u32, u32)
type TimeFn = fn (voidptr) u64
type DelayFn = fn (voidptr, u32)
type SyncFn = fn (voidptr, voidptr, usize, i32)
type StopFn = fn (voidptr)

@[typedef]
struct C.bw_const_byte {}

type ReceiveFn = fn (voidptr, &C.bw_const_byte, usize)

struct C.bw_ops {
mut:
	@read    ReadFn
	write    WriteFn
	time_us  TimeFn
	delay_us DelayFn
	sync     SyncFn
	stop_dma StopFn
	receive  ReceiveFn
}

struct C.bw_mem {
mut:
	cpu &u8
	dma u64
	len usize
}

struct C.bw_ring {
mut:
	item u16
}

struct C.bw_otp {
mut:
	@module [16]char
}

struct C.bw_device {
mut:
	state         i32
	revision      u8
	pcie_revision u8
	otp           C.bw_otp
	allocated     usize
	rings         [6]C.bw_ring
	request       C.bw_mem
	request_busy  u8
	associated    u8
	keyed         u8
	flow_open     u8
	radio_on      u8
	scan_pending  u8
	network_count u32
	tx_frames     u64
}

struct C.bw_firmware {
mut:
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

fn C.assert(bool)
fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.posix_memalign(&voidptr, usize, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memchr(voidptr, i32, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) usize
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.bw_init(&C.bw_device, &C.bw_ops, voidptr, voidptr, u64, usize, u32, u32) i32
fn C.bw_probe(&C.bw_device) i32
fn C.bw_start(&C.bw_device, &C.bw_firmware) i32
fn C.bw_join_wpa2(&C.bw_device, &u8, usize, &u8, usize) i32
fn C.bw_poll(&C.bw_device, u32) i32
fn C.bw_transmit(&C.bw_device, &u8, usize) i32
fn C.bw_scan(&C.bw_device) i32
fn C.bw_radio(&C.bw_device, i32) i32
fn C.bw_networks(&C.bw_device, &u8, usize) i32
fn C.bw_nvram_pack(&u8, usize, &u8, usize, &usize) i32
fn C.bw_otp_parse(&u8, usize, &C.bw_otp) i32
fn C.wifi_protocol_read(voidptr, u32, u32, u32) u32
fn C.wifi_protocol_write(voidptr, u32, u32, u32, u32)
fn C.wifi_protocol_time(voidptr) u64
fn C.wifi_protocol_delay(voidptr, u32)
fn C.wifi_protocol_sync(voidptr, voidptr, usize, i32)
fn C.wifi_protocol_stop(voidptr)
fn C.wifi_protocol_receive(voidptr, &C.bw_const_byte, usize)

@[c_extern]
__global (
	C.BW_POOL_MIN      u32
	C.BW_CONFIG        u32
	C.BW_TCM           u32
	C.BW_REGS          u32
	C.BW_CTL_SIZE      u32
	C.BW_NETWORKS_SIZE u32
	C.BW_READY         i32
	C.BW_CHIP          i32
	C.BW_FAULT         i32
	C.BW_LINK          i32
	C.BW_JOINING       i32
	C.BW_EINVAL        i32
	C.BW_ENOSPC        i32
	C.BW_EIO           i32
	C.BW_ETIME         i32
	C.BW_EPROTO        i32
	C.BW_ENOTSUP       i32
	C.BW_ENOLINK       i32
)

struct Posted {
mut:
	token  u32
	dma    u64
	length usize
}

struct Fake {
mut:
	bp                     &u8
	tcm                    &u8
	pool                   &u8
	cfg                    [1024]u32
	regs                   [3072]u32
	device                 &C.bw_device
	ctl                    [1024]Posted
	event                  [1024]Posted
	rx                     [2048]Posted
	ctl_n                  u32
	event_n                u32
	rx_n                   u32
	shared                 u32
	info                   u32
	desc                   u32
	consumed               [3]u16
	produced               [3]u16
	indices                [4]u64
	flow_dma               u64
	flow_count             u16
	time                   u64
	stopped                u32
	received               u32
	syncs                  u32
	commands               u32
	tx                     u32
	keys                   u32
	radio_up               u32
	radio_down             u32
	scans                  u32
	model                  i32
	boot_timeout           i32
	no_reply               i32
	no_ack                 i32
	unsupported_supplicant i32
	withhold_key           i32
	bad_shared             i32
	malformed_scan         i32
	version                i32
}

__global protocol_tests = u32(0)

@[cinit]
__global protocol_ops = C.bw_ops{ @read: C.wifi_protocol_read, write: C.wifi_protocol_write, time_us: C.wifi_protocol_time, delay_us: C.wifi_protocol_delay, sync: C.wifi_protocol_sync, stop_dma: C.wifi_protocol_stop, receive: C.wifi_protocol_receive }

fn le16(value voidptr) u16 {
	unsafe {
		p := &u8(value)
		return u16(u32(p[0]) | (u32(p[1]) << 8))
	}
}

fn le32(value voidptr) u32 {
	unsafe {
		p := &u8(value)
		return u32(p[0]) | (u32(p[1]) << 8) | (u32(p[2]) << 16) | (u32(p[3]) << 24)
	}
}

fn le64(value voidptr) u64 {
	unsafe { return u64(le32(value)) | (u64(le32(&u8(value) + 4)) << 32)
	 }
}

fn w16(value voidptr, word u16) {
	unsafe {
		p := &u8(value)
		p[0] = u8(word)
		p[1] = u8(word >> 8)
	}
}

fn w32(value voidptr, word u32) {
	unsafe {
		p := &u8(value)
		for i := u32(0); i < 4; i++ { p[i] = u8(word >> (i * 8)) }
	}
}

fn be16(value voidptr, word u16) {
	unsafe {
		p := &u8(value)
		p[0] = u8(word >> 8)
		p[1] = u8(word)
	}
}

fn be32(value voidptr, word u32) {
	unsafe {
		p := &u8(value)
		for i := u32(0); i < 4; i++ { p[i] = u8(word >> (24 - i * 8)) }
	}
}

fn dma(fake &Fake, address u64, length usize) &u8 {
	unsafe {
		C.assert(address >= 0x10000000 && address - 0x10000000 <= u32(C.BW_POOL_MIN) && length <= u32(C.BW_POOL_MIN) - (address - 0x10000000))
		return fake.pool + usize(address - 0x10000000)
	}
}

fn finish(fake &Fake, ring u32, message &u8, length usize) {
	unsafe {
		descriptor := fake.tcm + fake.desc + (ring + 2) * 16
		count := le16(descriptor + 4)
		size := le16(descriptor + 6)
		C.assert(count != 0 && size >= length)
		address := le64(descriptor + 8)
		position := fake.produced[ring]
		C.assert(u16((u32(position) + 1) % count) != le16(dma(fake, fake.indices[3] + ring * 2, 2)))
		C.memset(dma(fake, address + u64(position) * size, size), 0, size)
		C.memcpy(dma(fake, address + u64(position) * size, size), message, length)
		fake.produced[ring] = u16((u32(position) + 1) % count)
		w16(dma(fake, fake.indices[2] + ring * 2, 2), fake.produced[ring])
	}
}

fn send_event_data(fake &Fake, kind u32, status u32, flags u16, data &u8, length usize) {
	unsafe {
		C.assert(fake.event_n != 0 && length <= 8192 - 72)
		fake.event_n--
		posted := fake.event[fake.event_n]
		packet := dma(fake, posted.dma, 72 + length)
		C.memset(packet, 0, 72 + length)
		be16(packet + 12, 0x886c)
		be16(packet + 14, 0x8001)
		be16(packet + 16, u16(54 + length))
		packet[18] = 0
		C.memcpy(packet + 19, c'\x00\x10\x18', 3)
		be16(packet + 22, 1)
		be16(packet + 24, 2)
		be16(packet + 26, flags)
		be32(packet + 28, kind)
		be32(packet + 32, status)
		be32(packet + 44, u32(length))
		C.memcpy(packet + 48, c'\x02\xaa\xbb\xcc\xdd\xee', 6)
		if length != 0 { C.memcpy(packet + 72, data, length) }
		mut completion := [24]u8{}
		completion[0] = 0x0e
		w32(&completion[4], posted.token)
		w16(&completion[12], u16(72 + length))
		finish(fake, 0, &completion[0], 24)
	}
}

fn send_event(fake &Fake, kind u32, status u32, flags u16) {
	send_event_data(fake, kind, status, flags, unsafe { nil }, 0)
}

fn send_scan_bss(fake &Fake, sync u16, ssid &char, rssi i32, channel u32, secure i32, address u32) {
	unsafe {
		mut data := [140]u8{}
		bss := &data[12]
		length := C.strlen(ssid)
		C.assert(length <= 32)
		w32(&data[0], sizeof(data))
		w32(&data[4], 1)
		w16(&data[8], sync)
		w16(&data[10], 1)
		w32(bss, 109)
		w32(bss + 4, 128)
		bss[8] = 2
		bss[13] = u8(address)
		w16(bss + 16, if secure != 0 { u16(0x10) } else { u16(0) })
		bss[18] = u8(length)
		C.memcpy(bss + 19, ssid, length)
		w16(bss + 72, u16(channel))
		w16(bss + 78, u16(rssi))
		bss[88] = u8(channel)
		if fake.malformed_scan != 0 { w32(bss + 4, 1024) }
		send_event_data(fake, 69, 8, 0, &data[0], sizeof(data))
	}
}

fn handle_control(fake &Fake, message &u8) {
	unsafe {
		kind := u32(message[0])
		if kind == 0x0b || kind == 0x0d {
			posted := Posted{ token: le32(message + 4), dma: le64(message + 16), length: le16(message + 8) }
			C.assert(posted.length == 8192)
			C.assert(fake.ctl_n < 1024 && fake.event_n < 1024)
			if kind == 0x0b {
				fake.ctl[fake.ctl_n] = posted
				fake.ctl_n++
			} else {
				fake.event[fake.event_n] = posted
				fake.event_n++
			}
			return
		}
		if kind == 3 {
			C.assert(le16(message + 22) == 2 && le16(message + 30) == 48)
			fake.flow_dma = le64(message + 32)
			fake.flow_count = le16(message + 28)
			mut completion := [24]u8{}
			completion[0] = 4
			w16(&completion[10], 2)
			finish(fake, 0, &completion[0], 24)
			return
		}
		C.assert(kind == 9)
		fake.commands++
		command := le32(message + 8)
		length := usize(le16(message + 14))
		input := dma(fake, le64(message + 24), length)
		mut status := i16(0)
		if command == 263 {
			C.assert(length != 0 && C.memchr(input, 0, length) != nil)
			if C.strcmp(&char(input), c'sup_wpa') == 0 && fake.unsupported_supplicant != 0 {
				status = -23
			}
		}
		if command == 2 { fake.radio_up++ }
		if command == 3 { fake.radio_down++ }
		if command == 268 {
			C.assert(length == 68 && le16(input) == 12 && le16(input + 2) == 1)
			C.assert(C.memcmp(input + 4, c'correct-pass', 12) == 0)
			fake.keys++
		}
		if fake.no_ack == 0 {
			mut ack := [24]u8{}
			ack[0] = 0x0a
			w32(&ack[4], le32(message + 4))
			finish(fake, 0, &ack[0], 24)
		}
		if fake.no_reply == 0 {
			C.assert(fake.ctl_n != 0)
			fake.ctl_n--
			posted := fake.ctl[fake.ctl_n]
			mut completion := [24]u8{}
			completion[0] = 0x0c
			w32(&completion[4], posted.token)
			w16(&completion[8], u16(status))
			w16(&completion[14], le16(message + 12))
			w32(&completion[16], command)
			finish(fake, 0, &completion[0], 24)
		}
		if command == 26 {
			C.assert(fake.keys != 0)
			C.assert(le32(input) == 4 && C.memcmp(input + 4, c'test', 4) == 0)
			send_event(fake, 0, 0, 0)
			if fake.withhold_key == 0 { send_event(fake, 46, 6, 0) }
		}
		if command == 263 && C.strcmp(&char(input), c'escan') == 0 {
			q := input + 6
			C.assert(length == 78 && le32(q) == 1 && le16(q + 4) == 1 && q[50] == 2 && q[51] == 0xff)
			fake.scans++
			send_scan_bss(fake, le16(q + 6), c'Vinix', -55, 36, 1, 1)
			if fake.malformed_scan == 0 {
				send_scan_bss(fake, le16(q + 6), c'Vinix', -42, 44, 1, 2)
				send_scan_bss(fake, le16(q + 6), c'Guest', -67, 6, 0, 3)
				send_event(fake, 69, 0, 0)
			}
		}
	}
}

fn pump(fake &Fake) {
	unsafe {
		if fake.model == 0 || fake.desc == 0 || le64(fake.tcm + fake.info + 20) == 0 { return }
		for i := u32(0); i < 4; i++ { fake.indices[i] = le64(fake.tcm + fake.info + 20 + i * 8) }
		for ring := u32(0); ring < 3; ring++ {
			write_index := le16(dma(fake, fake.indices[0] + ring * 2, 2))
			count := if ring == 2 {
				fake.flow_count
			} else {
				le16(fake.tcm + fake.desc + ring * 16 + 4)
			}
			size := if ring == 2 { u16(48) } else { le16(fake.tcm + fake.desc + ring * 16 + 6) }
			address := if ring == 2 {
				fake.flow_dma
			} else {
				le64(fake.tcm + fake.desc + ring * 16 + 8)
			}
			if count == 0 { continue }
			for fake.consumed[ring] != write_index {
				mut message := [48]u8{}
				C.memcpy(&message[0], dma(fake, address + u64(fake.consumed[ring]) * size, size), size)
				fake.consumed[ring] = u16((u32(fake.consumed[ring]) + 1) % count)
				w16(dma(fake, fake.indices[1] + ring * 2, 2), fake.consumed[ring])
				if ring == 0 {
					handle_control(fake, &message[0])
				} else if ring == 1 {
					C.assert(message[0] == 0x11 && fake.rx_n < 2048)
					fake.rx[fake.rx_n] = Posted{ token: le32(&message[4]), dma: le64(&message[24]), length: le16(&message[10]) }
					fake.rx_n++
				} else {
					C.assert(message[0] == 0x0f && message[22] == 1 && message[23] == 1)
					dma(fake, le64(&message[32]), le16(&message[42]))
					fake.tx++
					mut completion := [24]u8{}
					completion[0] = 0x10
					w32(&completion[4], le32(&message[4]))
					w16(&completion[10], 2)
					finish(fake, 1, &completion[0], 16)
				}
			}
		}
	}
}

fn boot_firmware(fake &Fake) {
	unsafe {
		if fake.boot_timeout != 0 { return }
		fake.shared = 0x362000
		fake.info = 0x362200
		fake.desc = 0x363000
		w32(fake.tcm + 0x452000 - 4, if fake.bad_shared != 0 {
			u32(0xfffffffc)
		} else {
			fake.shared
		})
		w32(fake.tcm + fake.shared, 0x10110000 | u32(fake.version))
		w16(fake.tcm + fake.shared + 0x22, 255)
		w32(fake.tcm + fake.shared + 0x30, fake.info)
		w32(fake.tcm + fake.info, fake.desc)
		w16(fake.tcm + fake.info + 52, 14)
		w16(fake.tcm + fake.info + 54, 16)
		w16(fake.tcm + fake.info + 56, 3)
	}
}

@[export:'wifi_protocol_read']
pub fn read_bus(cookie voidptr, space u32, offset u32, width u32) u32 {
	unsafe {
		fake := &Fake(cookie)
		mut pointer := &u8(nil)
		if space == u32(C.BW_CONFIG) {
			C.assert(offset + width <= 4096)
			pointer = &u8(&fake.cfg[0]) + offset
		} else if space == u32(C.BW_TCM) {
			C.assert(offset + width <= 0x800000)
			pointer = fake.tcm + offset
		} else {
			C.assert(offset + width <= 0x3000)
			pointer = if offset < 4096 {
				fake.bp + (fake.cfg[0x80 / 4] - 0x18000000) + offset
			} else {
				&u8(&fake.regs[0]) + offset
			}
		}
		return if width == 1 {
			u32(pointer[0])
		} else if width == 2 {
			u32(le16(pointer))
		} else {
			le32(pointer)
		}
	}
}

@[export:'wifi_protocol_write']
pub fn write_bus(cookie voidptr, space u32, offset u32, width u32, value u32) {
	unsafe {
		fake := &Fake(cookie)
		mut pointer := &u8(nil)
		if space == u32(C.BW_CONFIG) {
			C.assert(offset + width <= 4096)
			pointer = &u8(&fake.cfg[0]) + offset
		} else if space == u32(C.BW_TCM) {
			C.assert(offset + width <= 0x800000)
			pointer = fake.tcm + offset
		} else {
			C.assert(offset + width <= 0x3000)
			pointer = if offset < 4096 {
				fake.bp + (fake.cfg[0x80 / 4] - 0x18000000) + offset
			} else {
				&u8(&fake.regs[0]) + offset
			}
		}
		if width == 1 {
			*pointer = u8(value)
		} else if width == 2 {
			w16(pointer, u16(value))
		} else {
			w32(pointer, value)
		}
		if space == u32(C.BW_REGS) && offset == 0x408 && fake.cfg[0x80 / 4] == 0x18102000 && value == 1 {
			boot_firmware(fake)
		}
		if space == u32(C.BW_REGS) && offset == 0x2a20 && value == 1 { pump(fake) }
	}
}

@[export:'wifi_protocol_time']
pub fn time_bus(cookie voidptr) u64 {
	unsafe { return (&Fake(cookie)).time
	 }
}

@[export:'wifi_protocol_delay']
pub fn delay_bus(cookie voidptr, us u32) {
	unsafe { (&Fake(cookie)).time += us }
}

@[export:'wifi_protocol_sync']
pub fn sync_bus(cookie voidptr, pointer voidptr, length usize, to_device i32) {
	unsafe {
		fake := &Fake(cookie)
		C.assert(usize(pointer) >= usize(fake.pool) && usize(pointer) <= usize(fake.pool) + u32(C.BW_POOL_MIN) && length <= usize(fake.pool) + u32(C.BW_POOL_MIN) - usize(pointer))
		C.assert(to_device == 0 || to_device == 1)
		fake.syncs++
	}
}

@[export:'wifi_protocol_stop']
pub fn stop_bus(cookie voidptr) {
	unsafe { (&Fake(cookie)).stopped++ }
}

@[export:'wifi_protocol_receive']
pub fn receive_bus(cookie voidptr, bytes &C.bw_const_byte, length usize) {
	unsafe {
		fake := &Fake(cookie)
		packet := &u8(bytes)
		C.assert(length == 60 && packet[12] == 8 && packet[13] == 0)
		fake.received++
	}
}

fn fixture() &Fake {
	unsafe {
		fake := &Fake(C.calloc(1, sizeof(Fake)))
		C.assert(fake != nil)
		fake.bp = &u8(C.calloc(1, 0x1000000))
		fake.tcm = &u8(C.calloc(1, 0x800000))
		C.assert(C.posix_memalign(&voidptr(&fake.pool), 16384, u32(C.BW_POOL_MIN)) == 0)
		C.memset(fake.pool, 0, u32(C.BW_POOL_MIN))
		fake.device = &C.bw_device(C.calloc(1, sizeof(C.bw_device)))
		C.assert(fake.bp != nil && fake.tcm != nil && fake.device != nil)
		fake.model = 1
		fake.version = 7
		w32(&fake.cfg[0], 0x442514e4)
		w32(fake.bp, 0x10034378)
		w32(fake.bp + 0xfc, 0x1800f000)
		ids := [u32(0x800), u32(0x83c), u32(0x847), u32(0x849), u32(0x812), u32(0x840)]!
		mut position := u32(0)
		for i := u32(0); i < 6; i++ {
			erom := fake.bp + 0xf000
			position += 0
			w32(erom + 4 * position, (ids[i] << 8) | 1)
			position++
			w32(erom + 4 * position, ((if i == 1 { u32(64) } else { u32(1) }) << 24) | (u32(1) << 19) | 1)
			position++
			w32(erom + 4 * position, 0x18000000 + i * 4096 + 5)
			position++
			w32(erom + 4 * position, 0x18100000 + i * 4096 + 0x85)
			position++
		}
		w32(fake.bp + 0xf000 + 4 * position, 15)
		w32(fake.bp + 0x3000, u32(2) << 4)
		w32(fake.bp + 0x3040, 63)
		otp := fake.bp + 0x5000 + 0x1120
		C.memset(otp, 255, 0x2e0)
		text := &char(c's=b1 M=module V=vendor m=rev')
		text_size := C.strlen(text) + 1
		otp[0] = 0x15
		otp[1] = u8(4 + text_size)
		w32(otp + 2, 8)
		C.memcpy(otp + 6, text, text_size)
		otp[6 + text_size] = 255
		C.assert(C.bw_init(fake.device, &protocol_ops, fake, fake.pool, 0x10000000, u32(C.BW_POOL_MIN), 0x3000, 0x800000) == 0)
		return fake
	}
}

fn destroy(fake &Fake) {
	unsafe {
		C.free(fake.bp)
		C.free(fake.tcm)
		C.free(fake.pool)
		C.free(fake.device)
		C.free(fake)
	}
}

fn start(fake &Fake) i32 {
	unsafe {
		mut code := [128]u8{}
		mut seed := [256]u8{}
		for i := u32(0); i < 256; i++ { seed[i] = u8(i) }
		w32(&code[0], 0x352080)
		w32(&code[0x6c], 0x534d4152)
		w32(&code[0x70], 0x100000)
		nvram := &char(c'boardrev=0x123\nmacaddr=02:11:22:33:44:55\n')
		blob := [u8(1), u8(2), u8(3), u8(4)]!
		mut firmware := C.bw_firmware{ nvram: &u8(nvram), code_len: sizeof(code), nvram_len: C.strlen(nvram), clm_len: sizeof(blob), txcap_len: sizeof(blob), calibration_len: sizeof(blob), seed_len: sizeof(seed), silicon_revision: 3, mac: [
			u8(2),
			u8(0x11),
			u8(0x22),
			u8(0x33),
			u8(0x44),
			u8(0x55),
		]! }
		// Copy pointer bits so V keeps the original synchronous firmware buffers on stack.
		code_address := usize(&code[0])
		seed_address := usize(&seed[0])
		blob_address := usize(&blob[0])
		C.memcpy(&firmware.code, &code_address, sizeof(code_address))
		C.memcpy(&firmware.seed, &seed_address, sizeof(seed_address))
		C.memcpy(&firmware.clm, &blob_address, sizeof(blob_address))
		C.memcpy(&firmware.txcap, &blob_address, sizeof(blob_address))
		C.memcpy(&firmware.calibration, &blob_address, sizeof(blob_address))
		error := C.bw_probe(fake.device)
		return if error != 0 { error } else { C.bw_start(fake.device, &firmware) }
	}
}

fn join(fake &Fake) {
	unsafe { C.assert(C.bw_join_wpa2(fake.device, &u8(c'test'), 4, &u8(c'correct-pass'), 12) == 0) }
}

fn frame(packet &u8) {
	unsafe {
		C.memset(packet, 0, 60)
		C.memset(packet, 255, 6)
		C.memcpy(packet + 6, c'\x02\x11\x22\x33\x44\x55', 6)
		packet[12] = 8
	}
}

fn inject_rx(fake &Fake, bad_offset i32) {
	unsafe {
		C.assert(fake.rx_n != 0)
		fake.rx_n--
		posted := fake.rx[fake.rx_n]
		frame(dma(fake, posted.dma, 60))
		mut message := [40]u8{}
		message[0] = 0x12
		w32(&message[4], posted.token)
		w16(&message[14], 60)
		w16(&message[16], if bad_offset != 0 { u16(2040) } else { u16(0) })
		finish(fake, 2, &message[0], 32)
	}
}
