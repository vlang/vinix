// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Where the address registers of a newly arrived device go.
//
// A function that arrives after boot has nothing in its base address
// registers: firmware assigned the ones it found and is gone. What firmware
// did leave, on a port it knew could receive a device, is the port's windows
// -- the ranges of memory and I/O addresses the port forwards to whatever is
// behind it. This file decides, from those windows and from the sizes the new
// registers ask for, which address each register gets.
//
// It is arithmetic only, with no bus behind it, so that it can be tested on
// its own (tests/pci-hotplug).
module pci

// A range of addresses a bridge forwards. One that forwards nothing has its
// end at or below its base, which is also how a bridge says so.
pub struct Window {
pub:
	base u64
	// One past the last address.
	end u64
}

pub fn (w Window) empty() bool {
	return w.end <= w.base
}

pub fn (w Window) holds(address u64, size u64) bool {
	return size != 0 && address >= w.base && address <= w.end && size <= w.end - address
}

pub struct Windows {
pub:
	// Memory below 4 GiB, for registers of either width.
	memory Window
	// Memory a device does not mind being read ahead of, which may lie above
	// 4 GiB.
	prefetchable Window
	io           Window
}

// What one base address register asks for, and what it was given.
pub struct Claim {
pub mut:
	// A power of two: the register's size is also its alignment.
	size         u64
	io           bool
	prefetchable bool
	// A 64-bit register, which can hold an address above 4 GiB.
	wide bool
	// Which function of the slot and which of its registers this is; carried
	// for the caller, not looked at here.
	function u8
	register u8

	// What the register holds when the claim is made; once place() has run
	// and `placed` is set, where it is to go.
	address u64
	placed  bool
}

// Six registers for each of a device's eight functions.
pub const max_claims = 48

const four_gib = u64(0x1_0000_0000)

pub struct Claims {
pub mut:
	list  [max_claims]Claim
	count int
}

pub fn (mut claims Claims) add(claim Claim) bool {
	if claims.count >= max_claims || claim.size == 0 || claim.size & (claim.size - 1) != 0 {
		return false
	}
	claims.list[claims.count] = claim
	claims.list[claims.count].placed = false
	claims.count++
	return true
}

// How far into each window the devices already behind the bridge reach: one
// past the highest address any of them has. New arrivals are placed after
// it, so that nothing in use is moved or overlapped.
pub struct Taken {
pub mut:
	memory       u64
	prefetchable u64
	io           u64
}

// Count an address range a present device has as taken.
pub fn (mut taken Taken) note(windows Windows, address u64, size u64, io bool) {
	end := address + size
	if io {
		if windows.io.holds(address, size) && end > taken.io {
			taken.io = end
		}
	} else if windows.prefetchable.holds(address, size) {
		if end > taken.prefetchable {
			taken.prefetchable = end
		}
	} else if windows.memory.holds(address, size) && end > taken.memory {
		taken.memory = end
	}
}

fn later(a u64, b u64) u64 {
	return if a > b { a } else { b }
}

// The next address at or after `cursor` that a register of this size can
// have, and whether the window has room for it at all.
fn fit(window Window, cursor u64, size u64) (u64, bool) {
	if window.empty() || cursor < window.base || cursor > window.end {
		return 0, false
	}
	aligned := (cursor + size - 1) & ~(size - 1)
	if aligned < cursor || aligned > window.end || size > window.end - aligned {
		return 0, false
	}
	return aligned, true
}

// Give every claim an address. The largest go first: each is aligned to its
// own size, so placing them in falling order leaves no gaps between them.
// A register that may be read ahead goes to the prefetchable window when
// there is one it can reach, and otherwise shares the plain one, which is
// always allowed; the reverse is not, so a plain register never goes to the
// prefetchable window. Returns how many claims were placed; the others are
// left with `placed` false, and their device works without them or not at
// all, which is for its driver to find out.
pub fn (mut claims Claims) place(windows Windows, taken Taken) int {
	mut order := [max_claims]u8{}
	for i in 0 .. claims.count {
		order[i] = u8(i)
	}
	// An insertion sort: the list is short, and equal sizes keep the order
	// they were found in, which keeps a device's registers together.
	for i := 1; i < claims.count; i++ {
		moving := order[i]
		mut j := i
		for j > 0 && claims.list[order[j - 1]].size < claims.list[moving].size {
			order[j] = order[j - 1]
			j--
		}
		order[j] = moving
	}
	mut memory_cursor := later(windows.memory.base, taken.memory)
	mut prefetchable_cursor := later(windows.prefetchable.base, taken.prefetchable)
	mut io_cursor := later(windows.io.base, taken.io)
	mut placed := 0
	for i in 0 .. claims.count {
		mut claim := &claims.list[order[i]]
		if claim.io {
			address, ok := fit(windows.io, io_cursor, claim.size)
			if ok {
				claim.address = address
				claim.placed = true
				io_cursor = address + claim.size
				placed++
			}
			continue
		}
		if claim.prefetchable {
			address, ok := fit(windows.prefetchable, prefetchable_cursor, claim.size)
			if ok && (claim.wide || address + claim.size <= four_gib) {
				claim.address = address
				claim.placed = true
				prefetchable_cursor = address + claim.size
				placed++
				continue
			}
		}
		address, ok := fit(windows.memory, memory_cursor, claim.size)
		if ok && (claim.wide || address + claim.size <= four_gib) {
			claim.address = address
			claim.placed = true
			memory_cursor = address + claim.size
			placed++
		}
	}
	return placed
}

// Whether every claim already has an address inside the window it belongs
// in, as it does when a device firmware configured is found a second time.
// Then nothing is moved: a driver may be using those addresses. A claim no
// window could ever take -- an I/O register behind a bridge that forwards no
// I/O -- does not count against that: placing it again would change nothing.
pub fn (claims &Claims) settled(windows Windows) bool {
	for i in 0 .. claims.count {
		claim := &claims.list[i]
		if claim.io {
			if !windows.io.empty() && !windows.io.holds(claim.address, claim.size) {
				return false
			}
			continue
		}
		if windows.memory.empty() && (!claim.prefetchable || windows.prefetchable.empty()) {
			continue
		}
		// An I/O window can start at address 0, and its first register is
		// then really there; memory at 0 is a register nobody has set.
		if claim.address == 0 {
			return false
		}
		in_plain := windows.memory.holds(claim.address, claim.size)
		in_prefetchable := claim.prefetchable && windows.prefetchable.holds(claim.address, claim.size)
		if !in_plain && !in_prefetchable {
			return false
		}
	}
	return true
}

// A bridge's windows as its registers give them. `memory` is the pair at
// 0x20, `prefetchable` the pair at 0x24 with its upper halves at 0x28 and
// 0x2c, `io` the pair of bytes at 0x1c with its upper halves at 0x30.
pub fn decode_windows(memory u32, prefetchable u32, prefetchable_base_upper u32, prefetchable_limit_upper u32, io u16, io_upper u32) Windows {
	memory_base := u64(memory & 0xfff0) << 16
	memory_limit := u64((memory >> 16) & 0xfff0) << 16
	mut prefetchable_base := u64(prefetchable & 0xfff0) << 16
	mut prefetchable_limit := u64((prefetchable >> 16) & 0xfff0) << 16
	if prefetchable & 0xf == 1 {
		prefetchable_base |= u64(prefetchable_base_upper) << 32
		prefetchable_limit |= u64(prefetchable_limit_upper) << 32
	}
	mut io_base := u64(io & 0xf0) << 8
	mut io_limit := u64((io >> 8) & 0xf0) << 8
	if io & 0xf == 1 {
		io_base |= u64(io_upper & 0xffff) << 16
		io_limit |= u64(io_upper >> 16) << 16
	}
	return Windows{
		memory:       if memory_limit < memory_base {
			Window{}
		} else {
			Window{memory_base, memory_limit + 0x10_0000}
		}
		prefetchable: if prefetchable_limit < prefetchable_base {
			Window{}
		} else {
			Window{prefetchable_base, prefetchable_limit + 0x10_0000}
		}
		io:           if io_limit < io_base {
			Window{}
		} else {
			Window{io_base, io_limit + 0x1000}
		}
	}
}
