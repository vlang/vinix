// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals; translated]
module platformfixture

#include "platform-native-abi.h"
struct C.bw_m1_plan {
mut:
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

struct C.bw_ops {
mut:
	stop_dma fn (voidptr)
}

struct C.bw_device {
mut:
	state i32
	error i32
	ops   C.bw_ops
}

struct C.bw_m1_state {
mut:
	p              C.bw_m1_plan
	dev            C.bw_device
	endpoint       u64
	bar0_len       u32
	prepared       i32
	endpoint_valid i32
}

fn C.assert(bool)
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.free(voidptr)
fn C.posix_memalign(&voidptr, usize, usize) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.vinix_m1_core_state() voidptr
fn C.vinix_m1_core_dart_prepare() i32
fn C.vinix_m1_core_bar_size(u32, &u64) i32
fn C.vinix_m1_core_stop_dma(voidptr)
fn C.vinix_m1_core_bus_read(voidptr, u32, u32, u32) u32
fn C.vinix_m1_core_bus_write(voidptr, u32, u32, u32, u32)
fn C.brcm_m1_prepare(&C.bw_m1_plan) i32
fn C.brcm_m1_stop()

@[c_extern]
__global (
	C.BW_POOL_MIN u32
	C.BW_EINVAL   i32
	C.BW_ENOTSUP  i32
	C.BW_ETIME    i32
	C.BW_FAULT    i32
	C.BW_REGS     u32
)

struct Register {
mut:
	address u64
	value   u32
}

__global (
	registers        [256]Register
	register_count   u32
	register_reads   u32
	register_writes  u32
	sync_calls       u32
	elapsed          u64
	probe_bar        u64
	probe_size       u64
	probe_bar2       u64
	probe_size2      u64
	timeout_register u64
	platform_seed    [256]u8
)

@[cinit]
__global platform_calibration = [u8(1), u8(2), u8(3), u8(4)]!

fn reg_get(address u64) u32 {
	unsafe {
		for i := u32(0); i < register_count; i++ {
			if registers[i].address == address { return registers[i].value }
		}
		return 0
	}
}

fn reg_set(address u64, value u32) {
	unsafe {
		for i := u32(0); i < register_count; i++ {
			if registers[i].address == address {
				registers[i].value = value
				return
			}
		}
		C.assert(register_count < 256)
		registers[register_count] = Register{ address: address, value: value }
		register_count++
	}
}

@[export:'vinix_mmio_read8']
pub fn mmio_read8(pointer voidptr) u8 {
	register_reads++
	address := u64(pointer)
	return u8(reg_get(address & ~u64(3)) >> ((address & 3) * 8))
}

@[export:'vinix_mmio_read16']
pub fn mmio_read16(pointer voidptr) u16 {
	register_reads++
	address := u64(pointer)
	return u16(reg_get(address & ~u64(3)) >> ((address & 2) * 8))
}

@[export:'vinix_mmio_read32']
pub fn mmio_read32(pointer voidptr) u32 {
	register_reads++
	address := u64(pointer)
	value := reg_get(address)
	if address == timeout_register { return value | 4 }
	if probe_bar != 0 && address == probe_bar && value == 0xffffffff {
		return u32(~(probe_size - 1)) | 4
	}
	if probe_bar2 != 0 && address == probe_bar2 && value == 0xffffffff {
		return u32(~(probe_size2 - 1)) | 4
	}
	return value
}

@[export:'vinix_mmio_write8']
pub fn mmio_write8(pointer voidptr, value u8) {
	register_writes++
	address := u64(pointer)
	shift := u32((address & 3) * 8)
	reg_set(address & ~u64(3), (reg_get(address & ~u64(3)) & ~(u32(255) << shift)) | (u32(value) << shift))
}

@[export:'vinix_mmio_write16']
pub fn mmio_write16(pointer voidptr, value u16) {
	register_writes++
	address := u64(pointer)
	shift := u32((address & 2) * 8)
	reg_set(address & ~u64(3), (reg_get(address & ~u64(3)) & ~(u32(65535) << shift)) | (u32(value) << shift))
}

@[export:'vinix_mmio_write32']
pub fn mmio_write32(pointer voidptr, value u32) {
	register_writes++
	reg_set(u64(pointer), value)
}

@[export:'vinix_m1_test_clock_us']
pub fn clock_us() u64 { return elapsed }

@[export:'vinix_m1_test_delay']
pub fn delay(us u32) { elapsed += us }

@[export:'vinix_m1_test_barrier']
pub fn barrier() {}

@[export:'vinix_m1_test_cache_sync']
pub fn cache_sync(pointer voidptr, length usize, to_device i32) {
	C.assert(usize(pointer) != 0 && length != 0 && to_device >= 0 && to_device <= 1)
	sync_calls++
}

fn host() &C.bw_m1_state { return unsafe { &C.bw_m1_state(C.vinix_m1_core_state()) } }

fn plan() C.bw_m1_plan {
	unsafe {
		mut p := C.bw_m1_plan{ config: 0x100000, config_size: 0x200000, rc: 0x300000, port: 0x400000, phy: 0x500000, gpio: 0x600000, dart: 0x700000, window: 0x100000000, window_bus: 0x80000000, window_size: 0x4000000, pool_cpu: 0x800000, pool_physical: 0x800000, tables_cpu: 0xc00000, tables_physical: 0xc00000, sid: 1, gpio_active_low: 1, calibration: &platform_calibration[0], seed: &platform_seed[0], calibration_len: sizeof(platform_calibration), seed_len: sizeof(platform_seed) }
		p.mac[0] = 2
		C.memcpy(&p.antenna[0], c'HRPN', 5)
		return p
	}
}

fn reset() {
	unsafe {
		C.memset(host(), 0, sizeof(C.bw_m1_state))
		C.memset(&registers[0], 0, sizeof(registers))
		register_count = 0
		register_reads = 0
		register_writes = 0
		sync_calls = 0
		elapsed = 0
		probe_bar = 0
		probe_size = 0
		probe_bar2 = 0
		probe_size2 = 0
		timeout_register = 0
	}
}

fn reject(p &C.bw_m1_plan) {
	reset()
	C.assert(C.brcm_m1_prepare(p) == i32(C.BW_EINVAL))
	C.assert(register_reads == 0 && register_writes == 0)
}
