// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
@[translated]
module core

#include "apple_smc.h"

// SPDX-License-Identifier: GPL-2.0-only

// No libc, allocation, MMIO, interrupts, or locks inside the protocol core.
// *The caller owns the opaque state, the mailbox, and serialization.
// *send: 1=sent, 0=failed. recv: 1=message, 0=empty, -1=failed.
// *clock returns a free-running, unsigned 64-bit counter at frequency Hz.
// *None of the callbacks may sleep waiting for an interrupt/event.
//

pub type Vinix_smc_send_fn = fn (voidptr, u64, u8) i32
pub type Vinix_smc_recv_fn = fn (voidptr, &u64, &u8) i32
pub type Vinix_smc_clock_fn = fn (voidptr) u64
pub type Vinix_smc_relax_fn = fn (voidptr)

// Copy `length` bytes at `offset` of the SMC's shared memory from (write 0) or
// to (write 1) `buffer`. 1=done, 0=failed. The shared memory is the firmware's
// own SRAM, which the caller maps: the core never touches an address.
pub type Vinix_smc_shmem_fn = fn (voidptr, i32, u32, &u8, u32) i32

// empty enum
pub const vinix_smc_io = -1
pub const vinix_smc_timeout = -2
pub const vinix_smc_protocol = -3
pub const vinix_smc_no_key = -4
pub const vinix_smc_unsupported = -5
pub const vinix_smc_range = -6
pub const vinix_smc_not_ready = -7
pub const vinix_smc_argument = -8

// The longest key value this client carries: an identity string.
pub const vinix_smc_max_value = 32

// Service asynchronous RTKit traffic; bounded by both count and time.

// Refresh at most once per second, including unsuccessful completed reads.

// No hardware access; errors and samples older than two seconds are rejected.

// Timestamp of the last completed sample; serialize access with refresh.

// Read-only battery telemetry. Bits 0/1/2 indicate voltage/current/power.
// *Values are mV, signed mA and signed mW, without estimating missing sensors.
//

// Produces "0\n" through "100\n", without a NUL terminator.

// Accessible at EL1 on the same ARM generic-timer setup Vinix already uses.

// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
// SPDX-License-Identifier: GPL-2.0-only

// Read-only M1 SMC client. Protocol references are recorded in docs/m1-battery.md.
// *This is deliberately a synchronous, SMC-only RTKit client: unlike AGX,
// *the SMC advertises firmware-owned SRAM, not host-allocated DMA buffers.
// *Do not share its mailbox with another RTKit instance.
//

// A second bound protects against a broken/stopped clock callback.

pub struct Smc_state {
pub mut:
	context         voidptr
	send            Vinix_smc_send_fn
	recv            Vinix_smc_recv_fn
	clock           Vinix_smc_clock_fn
	relax           Vinix_smc_relax_fn
	frequency       u64
	sram_base       u64
	sram_size       u64
	buffer_addr     [9]u64
	buffer_size     [9]u64
	endpoints       [8]u32
	capacity_key    u32
	sample_time     u64
	sample          i32
	sampled         i32
	ready           i32
	failed          i32
	next_id         u8
	capacity_length u8
	power_time      u64
	power_sampled   i32
	power_result    i32
	voltage         i32
	current         i32
	power           i32
	power_flags     u32
	shmem           Vinix_smc_shmem_fn
	shmem_addr      u64
	key_writes      u64
}

@[export: 'vinix_smc_state_size']
pub fn vinix_smc_state_size() uint {
	unsafe {
		return uint(sizeof(Smc_state))
	}
}

fn fail(s &Smc_state, error_ i32) i32 {
	unsafe {
		s.failed = error_
		s.ready = 0
		s.sampled = 0
		return error_
	}
}

fn in_sram(s &Smc_state, address u64, size u64) i32 {
	unsafe {
		// Subtraction, not address+size, avoids wrapping at UINT64_MAX.

		return i32(size && address >= s.sram_base && size <= s.sram_size && address - s.sram_base <= s.sram_size - size)
	}
}

fn expired(s &Smc_state, start u64, ticks u64) i32 {
	unsafe {
		return i32(s.clock(voidptr(s.context)) - start >= ticks)
	}
}

fn command_ticks(s &Smc_state) u64 {
	unsafe {
		return s.frequency / u64(2) + i32(u64((s.frequency % u64(2) != u64(0))))
		// 500 ms
	}
}

fn send_msg(s &Smc_state, endpoint u8, word u64) i32 {
	unsafe {
		if s.send(voidptr(s.context), word, endpoint) != 1 {
			return fail(s, i32(vinix_smc_io))
		}
		return 0
	}
}

fn management(s &Smc_state, kind u32, payload u64) i32 {
	unsafe {
		return send_msg(s, u8(0), (u64(kind) << 52) | payload)
	}
}

fn start_endpoint(s &Smc_state, ep u32) i32 {
	unsafe {
		return management(s, u32(5), (u64(ep) << 32) | u64(2))
	}
}

fn message_type(word u64) u32 {
	unsafe {
		return u32(((word >> 52) & u64(255)))
	}
}

fn has_endpoint(s &Smc_state, ep u32) i32 {
	unsafe {
		return i32(!!(s.endpoints[ep / u32(32)] & (u32(1) << (ep % u32(32)))))
	}
}

fn accept_buffer(s &Smc_state, ep u32, word u64) i32 {
	unsafe {
		address := u64(0)
		size := u64(0)

		if ep == u32(8) {
			address = (word & ((u64(1) << 36) - u64(1))) << 12
			size = (word >> 36) & u64(1048575)
		} else {
			address = word & ((u64(1) << 44) - u64(1))
			size = ((word >> 44) & u64(255)) << 12
		}
		// Never hand a firmware request arbitrary RAM, nor touch an unvalidated
		//     *address. A zero address would require DMA allocation, which this M1
		//     *SRAM client intentionally does not implement.
		//

		if !address {
			return fail(s, i32(vinix_smc_unsupported))
		}
		if (address & u64(4095)) || !in_sram(s, address, size) {
			return fail(s, i32(vinix_smc_protocol))
		}
		if s.buffer_size[ep] {
			// A second crashlog buffer message announces a firmware crash.

			if ep == u32(1) || s.buffer_addr[ep] != address || s.buffer_size[ep] != size {
				return fail(s, i32(vinix_smc_io))
			}
			return 0
		}
		s.buffer_addr[ep] = address
		s.buffer_size[ep] = size
		// Firmware-provided buffers need no allocation reply. We do not read
		//     *their contents; syslog/IOReport notifications below still get ACKs.
		//

		return 0
	}
}

fn system_message(s &Smc_state, ep u8, word u64) i32 {
	unsafe {
		kind := message_type(word)
		match i32(ep) {
			0 {
				// A fresh HELLO at runtime is a reset, not a command completion.

				if kind == u32(1) {
					return fail(s, i32(vinix_smc_io))
				}
				if (kind == u32(7) || kind == u32(11)) && (word & u64(255)) != u64(32) {
					return fail(s, i32(vinix_smc_io))
				}
				return 0
			}
			1 {
				if kind == u32(1) {
					return accept_buffer(s, u32(ep), word)
				}
				return fail(s, i32(vinix_smc_io))
			}
			2 {
				if kind == u32(1) {
					return accept_buffer(s, u32(ep), word)
				}
				if kind == u32(5) {
					return send_msg(s, ep, word)
				}
				// Release the firmware's log slot.

				return 0
				// Includes syslog INIT, whose text we do not consume.
			}
			4 {
				if kind == u32(1) {
					return accept_buffer(s, u32(ep), word)
				}
				if kind == u32(8) || kind == u32(12) {
					return send_msg(s, ep, word)
				}
				return 0
			}
			8 {
				if (word >> 56) == u64(1) {
					return accept_buffer(s, u32(ep), word)
				}
				return 0
				// Do not enable or interpret unknown application endpoints.
			}
			else {
				return 0
			}
		}
		return 0
	}
}

// A timed-out request poisons the channel until a reboot. With only four
// *message-ID bits, simply retrying could eventually accept a late reply as
// *the result of a different request after ID wraparound.
//

fn transaction(s &Smc_state, cmd u32, key u32, length u32, strict i32, result &u64) i32 {
	unsafe {
		id := s.next_id
		request := (u64(key) << 32) | (u64(length) << 16) | (u64(id) << 12) | u64(cmd)
		s.next_id = u8(((i32(id) + 1) & 15))
		start := s.clock(voidptr(s.context))
		if send_msg(s, u8(32), request) < 0 {
			return s.failed
		}
		for i := u32(0); i < 1000000; i++ {
			if expired(s, start, command_ticks(s)) {
				return fail(s, i32(vinix_smc_timeout))
			}
			word := u64(0)
			ep := u8(0)
			got := s.recv(voidptr(s.context), &word, &ep)
			if got < 0 {
				return fail(s, i32(vinix_smc_io))
			}
			if !got {
				s.relax(voidptr(s.context))
				continue
			}
			if u32(ep) != 32 {
				status := system_message(s, ep, word)
				if status < 0 {
					return status
				}
				continue
			}
			if (word & u64(255)) == u64(24) {
				continue
			}
			if cmd == 23 {
				// This one reply is a raw address, NOT an SMC status/ID header.

				if !in_sram(s, word, 16384) {
					return fail(s, i32(vinix_smc_protocol))
				}
				*result = word
				return 0
			}
			if ((word >> 12) & u64(15)) != u64(id) {
				continue
			}
			status := u32((word & u64(255)))
			if status {
				return if status == u32(132) { vinix_smc_no_key } else { vinix_smc_io }
			}
			// Response SIZE is eight bits. Bits 31:24 are the firmware WSIZE
			//         *field and are not part of the returned payload length.
			//

			if cmd == 16 && ((word >> 16) & u64(255)) != u64(length) {
				// The legacy capacity and telemetry keys give up the channel
				// here. A key read on its own account is only refused: the
				// reply carried this request's ID, so nothing is out of step.
				if strict {
					return fail(s, i32(vinix_smc_protocol))
				}
				return vinix_smc_protocol
			}
			*result = word
			return 0
		}
		return fail(s, i32(vinix_smc_timeout))
	}
}

@[export: 'vinix_smc_boot']
pub fn vinix_smc_boot(state voidptr, context voidptr, send Vinix_smc_send_fn, recv Vinix_smc_recv_fn, clock Vinix_smc_clock_fn, relax Vinix_smc_relax_fn, frequency u64, sram_base u64, sram_size u64) i32 {
	unsafe {
		if uint(state) == 0 {
			return vinix_smc_protocol
		}
		s := &Smc_state(state)

		*s = Smc_state{}

		if (uint(send) == 0) || (uint(recv) == 0) || (uint(clock) == 0) || (uint(relax) == 0) || frequency == 0 || frequency > u64(-1) / 4 || sram_base == 0 || sram_size < 0x4000 || sram_size - 1 > u64(-1) - sram_base {
			return fail(s, i32(vinix_smc_protocol))
		}
		s.context = context
		s.send = send
		s.recv = recv
		s.clock = clock
		s.relax = relax
		s.frequency = frequency
		s.sram_base = sram_base
		s.sram_size = sram_size
		start := clock(voidptr(context))
		hello := i32(0)
		map_done := i32(0)
		ap_requested := i32(0)
		iop_on := i32(0)
		ap_on := i32(0)

		if management(s, u32(6), u64(544)) < 0 {
			return s.failed
		}
		for i := u32(0); i < 1000000; i++ {
			if expired(s, start, u64(2) * frequency) {
				return fail(s, i32(vinix_smc_timeout))
			}
			word := u64(0)
			ep := u8(0)
			got := recv(voidptr(context), &word, &ep)
			if got < 0 {
				return fail(s, i32(vinix_smc_io))
			}
			if !got {
				relax(voidptr(context))
				continue
			}
			if ep {
				if system_message(s, ep, word) < 0 {
					return s.failed
				}
				continue
			}
			kind := message_type(word)
			match kind {
				u32(1) {
					// case comp stmt
					min := u32((word & u64(65535)))
					max := u32(((word >> 16) & u64(65535)))
					if hello || min > max || min > u32(12) || max < u32(11) {
						return fail(s, i32(vinix_smc_unsupported))
					}
					version := if max < u32(12) { max } else { u32(12) }
					if management(s, u32(2), u64(version) | (u64(version) << 16)) < 0 {
						return s.failed
					}
					hello = 1
				}
				u32(8) {
					// case comp stmt
					group := u32(((word >> 32) & u64(63)))
					if !hello || map_done || group >= u32(8) {
						return fail(s, i32(vinix_smc_protocol))
					}
					s.endpoints[group] |= u32(word)
					reply := u64(group) << 32
					reply |= if word & (u64(1) << 51) != 0 { (u64(1) << 51) } else { u64(1) }
					if management(s, u32(8), reply) < 0 {
						return s.failed
					}
					if word & (u64(1) << 51) {
						map_done = 1
						// RTKit will not finish booting unless every standard system
						//                 *endpoint it advertises is started, including debug (3).
						//

						system_eps := [u32(1), u32(2), u32(3), u32(4), u32(8)]!

						for j := u32(0); u64(j) < 5; j++ {
							if has_endpoint(s, system_eps[j]) && start_endpoint(s, system_eps[j]) < 0 {
								return s.failed
							}
						}
					}
				}
				u32(7) {
					iop_on = (word & u64(255)) == u64(32)
				}
				u32(11) {
					if ap_requested {
						ap_on = (word & u64(255)) == u64(32)
					}
				}
				else {
				}
			}

			// AP power may only be requested after the IOP has acknowledged ON.
			//         *Real firmware does not guarantee that ACK arrives with EPMAP.
			//

			if map_done && iop_on && !ap_requested {
				if management(s, u32(11), u64(32)) < 0 {
					return s.failed
				}
				ap_requested = 1
			}
			if hello && map_done && iop_on && ap_on {
				if !has_endpoint(s, 32) {
					return fail(s, i32(vinix_smc_unsupported))
				}
				if start_endpoint(s, 32) < 0 {
					return s.failed
				}
				address := u64(0)
				status := transaction(s, 23, u32(0), u32(0), 1, &address)
				if status < 0 {
					return status
				}
				s.shmem_addr = address
				// The address is only remembered. What the legacy capacity and
				//             *telemetry keys return fits in the reply; the shared memory
				//             *is touched through the caller's vinix_smc_set_shmem() alone.
				//

				s.ready = 1
				return 0
			}
		}
		return fail(s, i32(vinix_smc_timeout))
	}
}

@[export: 'vinix_smc_poll']
pub fn vinix_smc_poll(state voidptr, budget u32) i32 {
	unsafe {
		s := &Smc_state(state)
		if (uint(s) == 0) || !s.ready {
			return if (uint(s) != 0) && s.failed { s.failed } else { vinix_smc_not_ready }
		}
		if budget > u32(64) {
			budget = u32(64)
		}
		start := s.clock(voidptr(s.context))
		for i := u32(0); i < budget; i++ {
			if expired(s, start, command_ticks(s)) {
				return 0
			}
			word := u64(0)
			ep := u8(0)
			got := s.recv(voidptr(s.context), &word, &ep)
			if got < 0 {
				return fail(s, i32(vinix_smc_io))
			}
			if !got {
				return 0
			}
			// There is no outstanding request while polling. Drain old replies
			//         *and unsolicited SMC notifications without mistaking them for data.
			//

			if u32(ep) != 32 && system_message(s, ep, word) < 0 {
				return s.failed
			}
		}
		return 0
	}
}

@[export: 'vinix_smc_refresh']
pub fn vinix_smc_refresh(state voidptr) i32 {
	unsafe {
		s := &Smc_state(state)
		if (uint(s) == 0) || !s.ready {
			return if (uint(s) != 0) && s.failed { s.failed } else { vinix_smc_not_ready }
		}
		now := s.clock(voidptr(s.context))
		if s.sampled && now - s.sample_time < s.frequency {
			return s.sample
		}
		result := vinix_smc_poll(voidptr(s), u32(64))
		if result < 0 {
			return result
		}
		word := u64(0)
		key := s.capacity_key
		length := u32(s.capacity_length)
		if !key {
			// Current Apple firmware exposes charge percentage as BUIC/u8.
			//         *BRSC/ui16 remains a read-only fallback for older firmware.
			//

			key = 1112885571
			length = u32(1)
		}
		result = transaction(s, 16, key, length, 1, &word)
		if result == vinix_smc_no_key && !s.capacity_key {
			key = 1112691523
			length = u32(2)
			result = transaction(s, 16, key, length, 1, &word)
		}
		if result == 0 {
			s.capacity_key = key
			s.capacity_length = u8(length)
			mask := u32(if length == u32(1) { 255 } else { 65535 })
			capacity := u32(((word >> 32) & u64(mask)))
			result = if capacity <= u32(100) { i32(capacity) } else { vinix_smc_range }
		}
		if !s.failed {
			s.sample = result
			s.sample_time = s.clock(voidptr(s.context))
			s.sampled = 1
		}
		return result
	}
}

@[export: 'vinix_smc_cached_capacity']
pub fn vinix_smc_cached_capacity(state voidptr) i32 {
	unsafe {
		s := &Smc_state(state)
		if (uint(s) == 0) || !s.ready {
			return if (uint(s) != 0) && s.failed { s.failed } else { vinix_smc_not_ready }
		}
		if !s.sampled {
			return vinix_smc_not_ready
		}
		if s.clock(voidptr(s.context)) - s.sample_time >= u64(2) * s.frequency {
			return vinix_smc_timeout
		}
		return s.sample
	}
}

// Key units and signedness follow upstream macsmc-power.c. Transactions only
// *read keys; missing sensors are represented by absent validity bits.
//

@[export: 'vinix_smc_refresh_power']
pub fn vinix_smc_refresh_power(state voidptr, flags &u32, voltage &i32, current &i32, power &i32) i32 {
	unsafe {
		s := &Smc_state(state)
		if (uint(s) == 0) || !s.ready {
			return if (uint(s) != 0) && s.failed { s.failed } else { vinix_smc_not_ready }
		}
		if !s.power_sampled || s.clock(voidptr(s.context)) - s.power_time >= s.frequency {
			keys := [u32(0x42304156), u32(0x42304143), u32(0x42304150)]!

			s.power_flags = u32(0)
			s.power_result = vinix_smc_no_key
			for i := u32(0); i < u32(3); i++ {
				word := u64(0)
				result := transaction(s, 16, keys[i], u32(if i == u32(2) {
					4
				} else {
					2
				}), 1, &word)
				if s.failed {
					return result
				}
				if result != 0 {
					continue
				}
				value := u32((word >> 32))
				if i == u32(0) {
					s.voltage = i32(u16(value))
				}
				if i == u32(1) {
					s.current = i32(i16(value))
				}
				if i == u32(2) {
					s.power = i32(value)
				}
				s.power_flags |= u32(1) << i
				s.power_result = 0
			}
			s.power_time = s.clock(voidptr(s.context))
			s.power_sampled = 1
		}
		*flags = s.power_flags
		*voltage = s.voltage
		*current = s.current
		*power = s.power
		return s.power_result
	}
}

@[export: 'vinix_smc_power_time']
pub fn vinix_smc_power_time(state voidptr) u64 {
	unsafe {
		s := &Smc_state(state)
		return if s { s.power_time } else { u64(0) }
	}
}

fn power_field(out &u8, key &char, value i32) u32 {
	unsafe {
		mut used := u32(0)
		mut count := u32(0)
		mut cursor := key

		for *cursor != 0 {
			out[used] = u8(*cursor)
			used++
			cursor++
		}
		mut magnitude := if value < 0 { u32(-i64(value)) } else { u32(value) }
		if value < 0 {
			out[used] = `-`
			used++
		}
		mut digits := [10]u8{}
		for {
			digits[count] = u8(u32(`0`) + magnitude % 10)
			count++
			magnitude /= 10
			if magnitude == 0 { break }
		}
		for count != 0 {
			count--
			out[used] = digits[count]
			used++
		}
		out[used] = `\n`
		used++

		return used
	}
}

@[export: 'vinix_smc_format_power']
pub fn vinix_smc_format_power(flags u32, voltage i32, current i32, power i32, output &u8) i32 {
	unsafe {
		used := u32(0)
		if flags & u32(1) {
			used += power_field(output + used, c'voltage_mv: ', voltage)
		}
		if flags & u32(2) {
			used += power_field(output + used, c'current_ma: ', current)
		}
		if flags & u32(4) {
			used += power_field(output + used, c'power_mw: ', power)
		}
		return i32(used)
	}
}

// Keys by name, for the power supply, sensor and fan drivers above this
// core. Everything here is asked for by the caller: nothing below is sent at
// boot or by vinix_smc_poll(), vinix_smc_refresh() or
// vinix_smc_refresh_power(), which send GET_SRAM_ADDR and READ_KEY only.
//
// The commands and where their data travels follow Linux's drivers/mfd/macsmc.c
// (apple_smc_rw_locked, apple_smc_get_key_info): a value of up to four bytes
// comes back in the reply, low byte first; a longer one, a key's description
// and every value written go through the shared memory whose address
// GET_SRAM_ADDR returned.

fn usable(s &Smc_state) i32 {
	unsafe {
		if (uint(s) == 0) || !s.ready {
			return if (uint(s) != 0) && s.failed { s.failed } else { vinix_smc_not_ready }
		}
		return 0
	}
}

// Give the core the caller's way into the shared memory. Without one, values
// longer than four bytes, key descriptions and writes are refused unsent.
@[export: 'vinix_smc_set_shmem']
pub fn vinix_smc_set_shmem(state voidptr, shmem Vinix_smc_shmem_fn) i32 {
	unsafe {
		s := &Smc_state(state)
		status := usable(s)
		if status < 0 {
			return status
		}
		s.shmem = shmem
		return 0
	}
}

// Where the firmware said its shared memory is: inside the SRAM the caller
// named at boot, and checked to be. Zero before a successful boot.
@[export: 'vinix_smc_shmem_address']
pub fn vinix_smc_shmem_address(state voidptr) u64 {
	unsafe {
		s := &Smc_state(state)
		return if (uint(s) != 0) && s.ready { s.shmem_addr } else { u64(0) }
	}
}

// Why the channel was given up, or 0 while it is in use.
@[export: 'vinix_smc_failure']
pub fn vinix_smc_failure(state voidptr) i32 {
	unsafe {
		s := &Smc_state(state)
		return if uint(s) != 0 { s.failed } else { vinix_smc_not_ready }
	}
}

// How many values this client has asked the SMC to store.
@[export: 'vinix_smc_key_writes']
pub fn vinix_smc_key_writes(state voidptr) u64 {
	unsafe {
		s := &Smc_state(state)
		return if uint(s) != 0 { s.key_writes } else { u64(0) }
	}
}

// GET_KEY_INFO: a key's size in bytes, its four-character type and its
// attribute bits. VINIX_SMC_NO_KEY when the SMC has no such key.
@[export: 'vinix_smc_key_info']
pub fn vinix_smc_key_info(state voidptr, key u32, size &u8, kind &u32, flags &u8) i32 {
	unsafe {
		s := &Smc_state(state)
		status := usable(s)
		if status < 0 {
			return status
		}
		if uint(s.shmem) == 0 {
			return vinix_smc_unsupported
		}
		word := u64(0)
		result := transaction(s, 19, key, u32(0), 0, &word)
		if result < 0 {
			return result
		}
		mut info := [6]u8{}
		if s.shmem(voidptr(s.context), 0, u32(0), &info[0], u32(6)) != 1 {
			return vinix_smc_io
		}
		if uint(size) != 0 {
			*size = info[0]
		}
		if uint(kind) != 0 {
			*kind = (u32(info[1]) << 24) | (u32(info[2]) << 16) | (u32(info[3]) << 8) | u32(info[4])
		}
		if uint(flags) != 0 {
			*flags = info[5]
		}
		return 0
	}
}

// READ_KEY of `length` bytes, which must be the key's own size, into `output`
// in the order the SMC holds them. A key that is not there, an answer of
// another size and a refusal are errors of this one read; only a reply that
// never comes gives up the channel.
@[export: 'vinix_smc_read_key']
pub fn vinix_smc_read_key(state voidptr, key u32, length u32, output &u8) i32 {
	unsafe {
		s := &Smc_state(state)
		status := usable(s)
		if status < 0 {
			return status
		}
		if uint(output) == 0 || length == u32(0) || length > u32(vinix_smc_max_value) {
			return vinix_smc_argument
		}
		if length > u32(4) && uint(s.shmem) == 0 {
			return vinix_smc_unsupported
		}
		word := u64(0)
		result := transaction(s, 16, key, length, 0, &word)
		if result < 0 {
			return result
		}
		if length <= u32(4) {
			value := u32((word >> 32))
			for i := u32(0); i < length; i++ {
				output[i] = u8((value >> (u32(8) * i)))
			}
			return 0
		}
		if s.shmem(voidptr(s.context), 0, u32(0), output, length) != 1 {
			return vinix_smc_io
		}
		return 0
	}
}

// WRITE_KEY: store `length` bytes at `data` in a key. The bytes go into the
// shared memory first and the command names their count, as Linux has it.
// Nothing in this core calls this; see the top of this section.
@[export: 'vinix_smc_write_key']
pub fn vinix_smc_write_key(state voidptr, key u32, length u32, data &u8) i32 {
	unsafe {
		s := &Smc_state(state)
		status := usable(s)
		if status < 0 {
			return status
		}
		if uint(data) == 0 || length == u32(0) || length > u32(vinix_smc_max_value) {
			return vinix_smc_argument
		}
		if uint(s.shmem) == 0 {
			return vinix_smc_unsupported
		}
		if s.shmem(voidptr(s.context), 1, u32(0), data, length) != 1 {
			return vinix_smc_io
		}
		s.key_writes++
		word := u64(0)
		return transaction(s, 17, key, length, 0, &word)
	}
}

@[export: 'vinix_smc_sample_time']
pub fn vinix_smc_sample_time(state voidptr) u64 {
	unsafe {
		s := &Smc_state(state)
		return if (uint(s) != 0) && s.sampled { s.sample_time } else { u64(0) }
	}
}

@[export: 'vinix_smc_format_capacity']
pub fn vinix_smc_format_capacity(percent i32, output &u8) i32 {
	unsafe {
		if (uint(output) == 0) || percent < 0 || percent > 100 {
			return vinix_smc_range
		}
		length := i32(0)
		if percent == 100 {
			output[length++] = u8(`1`)
		}
		if percent >= 10 {
			output[length++] = u8((i32(`0`) + (percent / 10) % 10))
		}
		output[length++] = u8((i32(`0`) + percent % 10))
		output[length++] = u8(`\n`)
		return length
	}
}

@[export: 'vinix_smc_error']
pub fn vinix_smc_error(result i32) &char {
	unsafe {
		match result {
			vinix_smc_io {
				return c'mailbox/firmware I/O error'
			}
			vinix_smc_timeout {
				return c'SMC timeout (no retry after an in-flight timeout)'
			}
			vinix_smc_protocol {
				return c'invalid SMC/RTKit message or SRAM range'
			}
			vinix_smc_no_key {
				return c'BUIC/BRSC keys unavailable'
			}
			vinix_smc_unsupported {
				return c'unsupported RTKit version, endpoint, or DMA request'
			}
			vinix_smc_range {
				return c'battery percentage outside 0..100'
			}
			vinix_smc_not_ready {
				return c'battery sample unavailable'
			}
			vinix_smc_argument {
				return c'key length or buffer not acceptable'
			}
			else {
				return c'ok'
			}
		}
		return nil
	}
}
