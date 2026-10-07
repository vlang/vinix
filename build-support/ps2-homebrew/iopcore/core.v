// SPDX-License-Identifier: MIT
// Bare-metal R3000 controller/card worker on the emulated PS2 IOP.
@[has_globals; translated]
module iopcore

#include <native-abi.h>

struct C.ps2_volatile_word {
mut:
	value u32
}

struct C.ps2_volatile_byte {
mut:
	value u8
}

@[inline]
fn read32(address u32) u32 { return unsafe { (&C.ps2_volatile_word(usize(address))).value } }

@[inline]
fn write32(address u32, value u32) {
	unsafe { (&C.ps2_volatile_word(usize(address))).value = value }
}

@[inline]
fn read8(address u32) u8 { return unsafe { (&C.ps2_volatile_byte(usize(address))).value } }

@[inline]
fn write8(address u32, value u8) {
	unsafe { (&C.ps2_volatile_byte(usize(address))).value = value }
}

@[inline]
fn saved(index u32) u32 { return read32(0x800 + index * 4) }

@[inline]
fn save_word(index u32, value u32) { write32(0x800 + index * 4, value) }

struct Record {
mut:
	words [4]u32
}

__global (
	response [144]u8
	request  [64]u8
)

fn transact(port u32, length u32) {
	unsafe {
		write32(0x1f808268, 12)
		write32(0x1f808200, port | (length << 8) | (length << 18))
		write32(0x1f808204, 0)
		for i := u32(0); i < length; i++ { write8(0x1f808260, request[i]) }
		write32(0x1f808268, 1)
		for i := u32(0); i < 144; i++ { response[i] = read8(0x1f808264) }
		write32(0x1f808280, 3)
	}
}

fn card_address(command u32) {
	unsafe {
		request[0] = 0x81
		request[1] = u8(command)
		request[2] = 16
		request[3] = 0
		request[4] = 0
		request[5] = 0
		request[6] = 16
		request[7] = 0
		request[8] = 0
		transact(2, 9)
	}
}

fn read_word(offset u32) u32 {
	unsafe {
		return u32(response[offset]) | (u32(response[offset + 1]) << 8) |
			(u32(response[offset + 2]) << 16) | (u32(response[offset + 3]) << 24)
	}
}

fn load_card() {
	unsafe {
		card_address(0x23)
		request[0] = 0x81
		request[1] = 0x43
		request[2] = 16
		for i := u32(3); i < 22; i++ { request[i] = 0 }
		transact(2, 22)
		if read_word(4) == 0x44415056 && read_word(16) == (0x44415056 ^ read_word(8) ^ read_word(12)) {
			save_word(0, read_word(8))
			save_word(1, read_word(12))
		} else {
			save_word(1, 0)
			save_word(0, 0)
		}
	}
}

fn save_card() {
	unsafe {
		card_address(0x22)
		request[0] = 0x81
		request[1] = 0x42
		request[2] = 16
		mut record := Record{}
		record.words[0] = 0x44415056
		record.words[1] = saved(0)
		record.words[2] = saved(1)
		record.words[3] = u32(0x44415056) ^ saved(0) ^ saved(1)
		mut checksum := u32(0)
		for i := u32(0); i < 16; i++ {
			request[3 + i] = u8(record.words[i >> 2] >> ((i & 3) * 8))
			checksum ^= u32(request[3 + i])
		}
		request[19] = u8(checksum)
		request[20] = 0
		request[21] = 0
		transact(2, 22)
		request[0] = 0x81
		request[1] = 0x81
		request[2] = 0
		request[3] = 0
		transact(2, 4)
	}
}

@[export: 'iop_main'; noreturn]
pub fn run() {
	unsafe {
		load_card()
		write32(0x1d000010, 0xffff)
		mut last := u32(0)
		for {
			command := read32(0x1d000000)
			if command == last { continue }
			last = command
			if command & 0x80000000 != 0 { save_card() }
			request[0] = 1
			request[1] = 0x42
			for i := u32(2); i < 9; i++ { request[i] = 0 }
			transact(0, 9)
			write32(0x1d000010, (command & 0xffff0000) | u32(response[3]) | (u32(response[4]) << 8))
		}
	}
}
