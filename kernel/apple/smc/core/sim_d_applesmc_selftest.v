// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
//
// An SMC that is not there: the coprocessor's side of the mailbox, a table
// of keys, the shared memory, and the ways one goes wrong.
//
// No emulator has Apple's System Management Controller, so nothing above the
// mailbox registers could otherwise run anywhere but on a Mac booted
// natively. This answers the same mailbox words. It is built into the kernel
// only with -d applesmc_selftest, where it takes the place of the mailbox
// and of the SRAM mapping (smc/selftest_d_applesmc_selftest.v), and into the
// host tests of tests/apple_smc/core.
//
// What it does is this repository's reading of two things, and no more
// than that:
//
//   - the RTKit start-up the existing client was written against (HELLO,
//     the endpoint map, the two power states, a buffer announced for each
//     system endpoint), as tests/apple_smc/fixture models it;
//   - the SMC endpoint's commands as Linux's drivers/mfd/macsmc.c sends
//     them: READ_KEY 0x10, WRITE_KEY 0x11, GET_KEY_BY_INDEX 0x12,
//     GET_KEY_INFO 0x13 and GET_SRAM_ADDR 0x17, with a value of up to four
//     bytes in the reply and everything else in the shared memory.
//
// Result 0x84 for a key that is not there is what the real controller
// answers. The other results it gives (0x82 for a command it does not know,
// 0x85 and 0x86 for a key that may not be read or written, 0x87 for a wrong
// size) are placeholders: all the client needs of them is that they are not
// zero.
//
// The keys start out as a laptop on its charger; see laptop(). Their types,
// sizes and byte orders are the ones read from a real SMC (docs/m1-battery.md
// has the list), except where a test deliberately makes one different.
//
// Like core.v, this imports nothing.
module core

pub const sim_sram_base = u64(0x23fe00000)
pub const sim_sram_size = u64(0x100000)
const sim_shmem_offset = u64(0x80000)

pub const sim_key_slots = 48
const sim_queue_slots = 32
// The longest value a key can have, and so all of the shared memory that is
// ever used.
pub const sim_shmem_bytes = 256

pub const sim_no_key = u8(0x84)
const sim_bad_command = u8(0x82)
const sim_not_readable = u8(0x85)
const sim_not_writable = u8(0x86)
const sim_bad_size = u8(0x87)

// Types not in keys.v: the client has no use for their names.
pub const sim_type_ui8 = u32(0x75693820) // "ui8 "
pub const sim_type_ui16 = u32(0x75693136) // "ui16"
pub const sim_type_ui32 = u32(0x75693332) // "ui32"
pub const sim_type_flag = u32(0x666c6167) // "flag"
pub const sim_type_hex = u32(0x6865785f) // "hex_"
pub const sim_type_text = u32(0x6368382a) // "ch8*"

struct SimMessage {
mut:
	word     u64
	endpoint u8
}

pub struct SimKey {
pub mut:
	used  bool
	key   u32
	kind  u32
	size  u8
	flags u8
	value [32]u8
	// An answer to give in place of the value, to the next read only.
	once       bool
	once_value [32]u8
	reads      u64
	writes     u64
}

pub struct Sim {
pub mut:
	keys  [sim_key_slots]SimKey
	shmem [sim_shmem_bytes]u8
	// The firmware never answers a key command again.
	silent bool
	// A value written is acknowledged and not kept.
	ignore_writes bool
	// The reply to a read of this key names one byte fewer than was asked.
	short_reply u32
	// Whether the remaining charge is stored the old way round; laptop()
	// sets it together with the size of BCF0.
	remaining_big_endian bool

	// What it was asked.
	commands u64
	reads    u64
	writes   u64
	infos    u64
	unknown  u64
	// What the client did that it must not: a key command before the
	// endpoint was started, a message for an endpoint that has none, a
	// reply left unread until the queue was full.
	violations u64
	// The key last written, and the first byte it was given.
	last_written u32
	last_byte    u8
mut:
	queue [sim_queue_slots]SimMessage
	head  u32
	tail  u32
	// The endpoint the keys are behind has been started.
	started bool
}

fn (mut s Sim) push(endpoint u8, word u64) {
	if s.tail - s.head >= sim_queue_slots {
		s.violations++
		return
	}
	s.queue[s.tail % sim_queue_slots] = SimMessage{
		word:     word
		endpoint: endpoint
	}
	s.tail++
}

fn sim_management(kind u64, payload u64) u64 {
	return (kind << 52) | payload
}

// Where a key is in the table, or -1.
pub fn (s &Sim) find(key u32) int {
	for i in 0 .. sim_key_slots {
		if s.keys[i].used && s.keys[i].key == key {
			return i
		}
	}
	return -1
}

// Make a key, or make an existing one anew, with a number as its value,
// lowest byte first.
pub fn (mut s Sim) put(key u32, kind u32, flags u8, size int, value u64) bool {
	mut bytes := [8]u8{}
	for i in 0 .. 8 {
		bytes[i] = u8(value >> u32(8 * i))
	}
	return s.put_bytes(key, kind, flags, &bytes[0], size, size)
}

// The same with `given` bytes at `bytes`; what is left of `size` is zero.
pub fn (mut s Sim) put_bytes(key u32, kind u32, flags u8, bytes &u8, given int, size int) bool {
	if size < 1 || size > 32 || given > size {
		return false
	}
	mut index := s.find(key)
	if index < 0 {
		for i in 0 .. sim_key_slots {
			if !s.keys[i].used {
				index = i
				break
			}
		}
	}
	if index < 0 {
		return false
	}
	mut slot := &s.keys[index]
	slot.used = true
	slot.key = key
	slot.kind = kind
	slot.size = u8(size)
	slot.flags = flags
	slot.once = false
	for i in 0 .. 32 {
		slot.value[i] = 0
	}
	for i in 0 .. given {
		slot.value[i] = unsafe { bytes[i] }
	}
	return true
}

// Change the value of a key that is there, keeping what it is.
pub fn (mut s Sim) update(key u32, value u64) bool {
	index := s.find(key)
	if index < 0 {
		return false
	}
	mut slot := &s.keys[index]
	for i in 0 .. int(slot.size) {
		slot.value[i] = 0
	}
	for i in 0 .. int(slot.size) {
		if i < 8 {
			slot.value[i] = u8(value >> u32(8 * i))
		}
	}
	return true
}

// Change it to the `given` bytes at `bytes`.
pub fn (mut s Sim) update_bytes(key u32, bytes &u8, given int) bool {
	index := s.find(key)
	if index < 0 || given != int(s.keys[index].size) {
		return false
	}
	mut slot := &s.keys[index]
	for i in 0 .. given {
		slot.value[i] = unsafe { bytes[i] }
	}
	return true
}

// Answer the next read of a key, and only that one, with these bytes.
pub fn (mut s Sim) once_bytes(key u32, bytes &u8, given int) bool {
	index := s.find(key)
	if index < 0 || given != int(s.keys[index].size) {
		return false
	}
	mut slot := &s.keys[index]
	for i in 0 .. given {
		slot.once_value[i] = unsafe { bytes[i] }
	}
	slot.once = true
	return true
}

pub fn (mut s Sim) once(key u32, value u64) bool {
	mut bytes := [8]u8{}
	for i in 0 .. 8 {
		bytes[i] = u8(value >> u32(8 * i))
	}
	index := s.find(key)
	if index < 0 || s.keys[index].size > 8 {
		return false
	}
	return s.once_bytes(key, &bytes[0], int(s.keys[index].size))
}

pub fn (mut s Sim) remove(key u32) bool {
	index := s.find(key)
	if index < 0 {
		return false
	}
	s.keys[index].used = false
	return true
}

// A key's value as a number, lowest byte first; 0 for one that is not there.
pub fn (s &Sim) value_of(key u32) u64 {
	index := s.find(key)
	if index < 0 {
		return 0
	}
	size := if s.keys[index].size > 8 { 8 } else { int(s.keys[index].size) }
	return little_endian(&s.keys[index].value[0], size)
}

// ── The mailbox ─────────────────────────────────────────────────────────────

// A word from the client. False when the mailbox would not take it.
pub fn (mut s Sim) send(word u64, endpoint u8) bool {
	if endpoint == 0 {
		s.manage(word)
		return true
	}
	if endpoint == 32 {
		s.command(word)
		return true
	}
	// Acknowledgements on the log and report endpoints need no answer.
	if endpoint != 2 && endpoint != 4 {
		s.violations++
	}
	return true
}

// The next word for the client, if there is one.
pub fn (mut s Sim) receive() (bool, u64, u8) {
	if s.head == s.tail {
		return false, u64(0), u8(0)
	}
	message := s.queue[s.head % sim_queue_slots]
	s.head++
	return true, message.word, message.endpoint
}

// Something the firmware says unasked: a notification on the key endpoint.
pub fn (mut s Sim) notify(data u32) {
	s.push(32, (u64(data) << 32) | 0x18)
}

fn (mut s Sim) manage(word u64) {
	kind := (word >> 52) & 0xff
	match kind {
		6 {
			// Wake up: HELLO, with the versions spoken.
			s.push(0, sim_management(1, u64(11) | (u64(12) << 16)))
		}
		2 {
			// The endpoints there are: the system ones, and number 32, last.
			s.push(0, sim_management(8, 0x11e))
			s.push(0, sim_management(8, (u64(1) << 51) | (u64(1) << 32) | 1))
			s.push(0, sim_management(7, 0x220))
		}
		8 {}
		5 {
			started := u8((word >> 32) & 0xff)
			if started == 32 {
				s.started = true
			} else if started == 8 {
				address := sim_sram_base + u64(started) * 0x4000
				s.push(started, (u64(1) << 56) | (u64(4096) << 36) | (address >> 12))
			} else if started == 1 || started == 2 || started == 4 {
				address := sim_sram_base + u64(started) * 0x4000
				s.push(started, sim_management(1, (u64(1) << 44) | address))
			}
		}
		11 {
			s.push(0, sim_management(11, 0x20))
		}
		else {
			s.violations++
		}
	}
}

fn (mut s Sim) reply(id u64, status u8, size u64, data u32) {
	s.push(32, (u64(data) << 32) | (size << 16) | (id << 12) | u64(status))
}

fn (mut s Sim) command(word u64) {
	if !s.started {
		s.violations++
		return
	}
	command := word & 0xff
	id := (word >> 12) & 0xf
	size := (word >> 16) & 0xff
	argument := u32(word >> 32)
	s.commands++
	if command == 0x17 {
		// The one reply that is an address and nothing else.
		s.push(32, sim_sram_base + sim_shmem_offset)
		return
	}
	if s.silent {
		return
	}
	match command {
		0x10 {
			s.reads++
			index := s.find(argument)
			if index < 0 {
				s.reply(id, sim_no_key, 0, 0)
				return
			}
			mut slot := &s.keys[index]
			if slot.flags & flag_readable == 0 {
				s.reply(id, sim_not_readable, 0, 0)
				return
			}
			if size != u64(slot.size) {
				s.reply(id, sim_bad_size, 0, 0)
				return
			}
			slot.reads++
			source := if slot.once { &slot.once_value[0] } else { &slot.value[0] }
			slot.once = false
			mut data := u32(0)
			if size <= 4 {
				data = u32(little_endian(source, int(size)))
			} else {
				for i in 0 .. int(size) {
					s.shmem[i] = unsafe { source[i] }
				}
			}
			said := if s.short_reply == argument { size - 1 } else { size }
			s.reply(id, 0, said, data)
		}
		0x11 {
			s.writes++
			index := s.find(argument)
			if index < 0 {
				s.reply(id, sim_no_key, 0, 0)
				return
			}
			mut slot := &s.keys[index]
			if slot.flags & flag_writable == 0 {
				s.reply(id, sim_not_writable, 0, 0)
				return
			}
			if size != u64(slot.size) {
				s.reply(id, sim_bad_size, 0, 0)
				return
			}
			slot.writes++
			s.last_written = argument
			s.last_byte = s.shmem[0]
			if !s.ignore_writes {
				for i in 0 .. int(size) {
					slot.value[i] = s.shmem[i]
				}
			}
			s.reply(id, 0, size, 0)
		}
		0x12 {
			mut seen := u32(0)
			for i in 0 .. sim_key_slots {
				if !s.keys[i].used {
					continue
				}
				if seen == argument {
					// The key as its four characters in memory order.
					key := s.keys[i].key
					swapped := (key >> 24) | ((key >> 8) & 0xff00) | ((key << 8) & 0xff0000) | (key << 24)
					s.reply(id, 0, 4, swapped)
					return
				}
				seen++
			}
			s.reply(id, sim_no_key, 0, 0)
		}
		0x13 {
			s.infos++
			index := s.find(argument)
			if index < 0 {
				s.reply(id, sim_no_key, 0, 0)
				return
			}
			slot := &s.keys[index]
			s.shmem[0] = slot.size
			s.shmem[1] = u8(slot.kind >> 24)
			s.shmem[2] = u8(slot.kind >> 16)
			s.shmem[3] = u8(slot.kind >> 8)
			s.shmem[4] = u8(slot.kind)
			s.shmem[5] = slot.flags
			s.reply(id, 0, 6, 0)
		}
		else {
			s.unknown++
			s.reply(id, sim_bad_command, 0, 0)
		}
	}
}

// The client reads or writes the shared memory. False outside it.
pub fn (mut s Sim) shared(write bool, offset u32, buffer &u8, length u32) bool {
	if offset > sim_shmem_bytes || length > sim_shmem_bytes - offset {
		return false
	}
	for i in 0 .. int(length) {
		if write {
			s.shmem[int(offset) + i] = unsafe { buffer[i] }
		} else {
			unsafe {
				buffer[i] = s.shmem[int(offset) + i]
			}
		}
	}
	return true
}

// ── The machine it starts out as ────────────────────────────────────────────

const sim_read = flag_readable
const sim_read_write = flag_readable | flag_writable

// Floats used below, as their 32 bits.
pub const sim_flt_38_5 = u32(0x421a0000)
pub const sim_flt_31_25 = u32(0x41fa0000)
pub const sim_flt_47 = u32(0x423c0000)
pub const sim_flt_2400 = u32(0x45160000)
pub const sim_flt_1350 = u32(0x44a8c000)
pub const sim_flt_5349 = u32(0x45a72800)

// The remaining charge as this firmware stores it.
fn (s &Sim) stored_remaining(mah u64) u64 {
	return if s.remaining_big_endian { swap16(mah) } else { mah }
}

// A laptop on its charger, at 62 percent of the 4200 mAh its battery still
// holds of the 4380 it was made with, taking 1.5 A. The remaining charge it
// counts, 2590 mAh, is not to the digit that share of the full charge, here
// or at any later moment: a real gauge's never is, and a test has to be able
// to tell which of the two it was shown.
//
// `fan` gives it one fan, as a MacBook Pro has and a MacBook Air has not;
// `limit` gives it the CHWA key; `old_order` makes its firmware the kind
// whose BCF0 is four bytes and whose remaining charge is big-endian.
pub fn (mut s Sim) laptop(fan bool, limit bool, old_order bool) {
	s.remaining_big_endian = old_order
	s.put(key_b0fc, sim_type_ui16, sim_read, 2, 4200)
	s.put(key_b0dc, sim_type_ui16, sim_read, 2, 4380)
	s.put(key_b0ct, sim_type_ui16, sim_read, 2, 77)
	s.put(key_bitv, sim_type_ui16, sim_read, 2, 9000)
	flag_type := if old_order { sim_type_ui32 } else { sim_type_ui8 }
	flag_size := if old_order { 4 } else { 1 }
	s.put(key_bcf0, flag_type, sim_read, flag_size, 0)
	model := 'bq40z651'
	s.put_bytes(key_bmdn, sim_type_text, sim_read, model.str, model.len, 32)
	serial := 'F5D0VINIX0SIM0001'
	s.put_bytes(key_bmsn, sim_type_text, sim_read, serial.str, serial.len, 21)
	s.put(0x42554943, sim_type_ui8, sim_read, 1, 62) // BUIC
	s.put(0x42304156, sim_type_ui16, sim_read, 2, 12300) // B0AV
	s.put(0x42304143, 0x73693136, sim_read, 2, 1500) // B0AC, si16
	s.put(0x42304150, 0x73693332, sim_read, 4, 18450) // B0AP, si32
	s.put(key_b0rm, sim_type_ui16, sim_read, 2, s.stored_remaining(2590))
	s.put(key_b0te, sim_type_ui16, sim_read, 2, 0xffff)
	s.put(key_b0tf, sim_type_ui16, sim_read, 2, 65)
	s.put(key_bsfc, sim_type_flag, sim_read, 1, 0)
	s.put(key_ch0r, sim_type_hex, sim_read, 4, 0)
	s.put(key_chce, sim_type_ui8, sim_read, 1, 1)
	s.put(key_chcc, sim_type_ui8, sim_read, 1, 1)
	s.put(key_chnc, sim_type_hex, sim_read, 8, 0)
	s.put(key_chsc, sim_type_ui8, sim_read, 1, 1)
	s.put(key_chis, sim_type_ui32, sim_read, 4, 1)
	if limit {
		s.put(key_chwa, sim_type_flag, sim_read_write, 1, 0)
	}
	s.put(key_th0x, type_flt, sim_read, 4, u64(sim_flt_38_5))
	s.put(key_tb0t, type_flt, sim_read, 4, u64(sim_flt_31_25))
	// One of them in the other type the client reads: 44 degrees.
	s.put(key_tchp, type_ioft, sim_read, 8, u64(44) << 16)
	s.put(key_tw0p, type_flt, sim_read, 4, u64(sim_flt_47))
	fans := if fan { u64(1) } else { u64(0) }
	s.put(key_fnum, sim_type_ui8, sim_read, 1, fans)
	if fan {
		s.put(key_f0ac, type_flt, sim_read, 4, u64(sim_flt_2400))
		s.put(key_f0mn, type_flt, sim_read, 4, u64(sim_flt_1350))
		s.put(key_f0mx, type_flt, sim_read, 4, u64(sim_flt_5349))
	}
}

// The moments of a battery's day a test moves it through.
pub enum SimScene {
	charging
	unplugged
	low
	critical
	full
}

fn (mut s Sim) set_current(milliamperes i64, milliwatts i64) {
	s.update(0x42304143, u64(milliamperes) & 0xffff)
	s.update(0x42304150, u64(milliwatts) & 0xffffffff)
}

fn (mut s Sim) set_charger(there bool) {
	on := if there { u64(1) } else { u64(0) }
	s.update(key_chce, on)
	s.update(key_chcc, on)
	s.update(key_chis, on)
	// Bit 4: no charger's power, because none is connected.
	reasons := if there { u64(0) } else { u64(0x10) }
	s.update(key_ch0r, reasons)
}

fn (mut s Sim) set_level(percent u64, mah u64) {
	s.update(0x42554943, percent)
	s.update(key_b0rm, s.stored_remaining(mah))
}

pub fn (mut s Sim) scene(scene SimScene) {
	match scene {
		.charging {
			s.set_charger(true)
			s.set_level(62, 2590)
			s.set_current(1500, 18450)
			s.update(0x42304156, 12300)
			s.update(key_bsfc, 0)
			s.update(key_chnc, 0)
			s.update(key_b0te, 0xffff)
			s.update(key_b0tf, 65)
		}
		.unplugged {
			s.set_charger(false)
			s.set_level(60, 2533)
			s.set_current(-1200, -14000)
			s.update(0x42304156, 11700)
			s.update(key_bsfc, 0)
			s.update(key_chnc, 0)
			s.update(key_b0te, 130)
			s.update(key_b0tf, 0xffff)
		}
		.low {
			s.set_charger(false)
			s.set_level(8, 345)
			s.set_current(-1200, -13000)
			s.update(0x42304156, 10900)
			s.update(key_bsfc, 0)
			s.update(key_b0te, 17)
			s.update(key_b0tf, 0xffff)
		}
		.critical {
			s.set_charger(false)
			s.set_level(2, 91)
			s.set_current(-1200, -12000)
			s.update(0x42304156, 9900)
			s.update(key_bsfc, 0)
			s.update(key_b0te, 4)
			s.update(key_b0tf, 0xffff)
		}
		.full {
			s.set_charger(true)
			s.set_level(100, 4200)
			s.set_current(0, 0)
			s.update(0x42304156, 12900)
			s.update(key_bsfc, 1)
			s.update(key_chnc, 1)
			s.update(key_b0te, 0xffff)
			s.update(key_b0tf, 0xffff)
		}
	}
}
