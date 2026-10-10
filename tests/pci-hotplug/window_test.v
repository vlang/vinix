// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module pci

const mib = u64(0x10_0000)
const gib = u64(0x4000_0000)

// The windows QEMU's firmware gives an empty root port of a PC: 2 MiB of
// memory, 512 MiB of prefetchable memory above 4 GiB, no I/O.
fn pc_port() Windows {
	return decode_windows(0x8110_8100, 0x1ff1_0001, 0xc0, 0xc0, 0x00f0, 0)
}

fn memory_claim(size u64, function u8, register u8) Claim {
	return Claim{
		size:     size
		function: function
		register: register
	}
}

fn test_windows_are_read_as_firmware_wrote_them() {
	windows := pc_port()
	assert windows.memory.base == 0x8100_0000
	assert windows.memory.end == 0x8120_0000
	assert windows.prefetchable.base == 0xc0_0000_0000
	assert windows.prefetchable.end == 0xc0_2000_0000
	assert windows.io.empty()
	// The port of an AArch64 virtual machine with a card in it: memory, I/O
	// from 0, and a prefetchable window closed by a base above its limit.
	arm := decode_windows(0x1010_1000, 0x0001_fff1, 0xffffffff, 0, 0x0000, 0)
	assert arm.memory.base == 0x1000_0000
	assert arm.memory.end == 0x1020_0000
	assert arm.prefetchable.empty()
	assert arm.io.base == 0
	assert arm.io.end == 0x1000
	// Thirty-two-bit I/O takes its upper halves from the register at 0x30.
	wide_io := decode_windows(0xfff0_0000, 0x0000_fff0, 0, 0, 0x2121, 0x0002_0001)
	assert wide_io.io.base == 0x1_2000
	assert wide_io.io.end == 0x2_3000
	assert wide_io.memory.empty() == false
	assert decode_windows(0x0000_fff0, 0x0000_fff0, 0, 0, 0x00f0, 0).memory.empty()
}

fn test_a_window_holds_what_fits_and_nothing_else() {
	window := Window{0x1000, 0x2000}
	assert window.holds(0x1000, 0x1000)
	assert window.holds(0x1800, 0x800)
	assert !window.holds(0x1800, 0x801)
	assert !window.holds(0xfff, 2)
	assert !window.holds(0x2000, 1)
	assert !window.holds(0x1000, 0)
	assert Window{}.empty()
	assert !Window{}.holds(0, 1)
	// A size that would wrap the address is not held.
	assert !window.holds(0x1800, ~u64(0))
}

fn test_the_largest_register_goes_first_and_none_overlap() {
	mut claims := Claims{}
	assert claims.add(memory_claim(0x1000, 0, 1))
	assert claims.add(memory_claim(0x2_0000, 0, 0))
	assert claims.add(memory_claim(0x4000, 1, 0))
	assert claims.place(pc_port(), Taken{}) == 3
	assert claims.list[1].address == 0x8100_0000
	assert claims.list[2].address == 0x8102_0000
	assert claims.list[0].address == 0x8102_4000
	for i in 0 .. claims.count {
		a := claims.list[i]
		assert a.placed
		assert a.address % a.size == 0
		assert pc_port().memory.holds(a.address, a.size)
		for j in 0 .. i {
			b := claims.list[j]
			assert a.address + a.size <= b.address || b.address + b.size <= a.address
		}
	}
}

fn test_equal_sizes_keep_the_order_they_were_found_in() {
	mut claims := Claims{}
	for register in 0 .. 4 {
		claims.add(memory_claim(0x1000, 0, u8(register)))
	}
	assert claims.place(pc_port(), Taken{}) == 4
	for register in 0 .. 4 {
		assert claims.list[register].address == 0x8100_0000 + u64(register) * 0x1000
	}
}

fn test_prefetchable_registers_go_where_they_can_reach() {
	mut claims := Claims{}
	// Sixty-four bits wide: the window above 4 GiB.
	claims.add(Claim{ size: 16 * mib, prefetchable: true, wide: true })
	// Thirty-two bits wide: cannot be put above 4 GiB, so shares the plain
	// window.
	claims.add(Claim{ size: 0x1_0000, prefetchable: true })
	// Not prefetchable: never in the prefetchable window, wide or not.
	claims.add(Claim{ size: 0x1000, wide: true })
	assert claims.place(pc_port(), Taken{}) == 3
	assert claims.list[0].address == 0xc0_0000_0000
	assert claims.list[1].address == 0x8100_0000
	assert claims.list[2].address == 0x8101_0000
	// With no prefetchable window, all of them share the plain one.
	mut shared := Claims{}
	shared.add(Claim{ size: mib, prefetchable: true, wide: true })
	shared.add(Claim{ size: 0x1000 })
	plain := Windows{
		memory: Window{0x1000_0000, 0x1020_0000}
	}
	assert shared.place(plain, Taken{}) == 2
	assert shared.list[0].address == 0x1000_0000
	assert shared.list[1].address == 0x1010_0000
}

fn test_what_does_not_fit_is_left_unplaced_and_the_rest_is_placed() {
	mut claims := Claims{}
	// Larger than the whole window, then two that fit, then I/O with no I/O
	// window to go to.
	claims.add(memory_claim(4 * mib, 0, 0))
	claims.add(memory_claim(mib, 0, 1))
	claims.add(memory_claim(mib, 0, 2))
	claims.add(memory_claim(mib, 0, 3))
	claims.add(Claim{ size: 0x40, io: true, register: 4 })
	assert claims.place(pc_port(), Taken{}) == 2
	assert !claims.list[0].placed
	assert claims.list[1].placed && claims.list[1].address == 0x8100_0000
	assert claims.list[2].placed && claims.list[2].address == 0x8110_0000
	assert !claims.list[3].placed
	assert !claims.list[4].placed
}

fn test_io_is_placed_in_an_io_window_even_from_address_zero() {
	windows := Windows{
		memory: Window{0x1000_0000, 0x1020_0000}
		io:     Window{0, 0x1000}
	}
	mut claims := Claims{}
	claims.add(Claim{ size: 0x40, io: true })
	claims.add(Claim{ size: 0x100, io: true })
	assert claims.place(windows, Taken{}) == 2
	// The larger first: at 0, which is a real address in this window.
	assert claims.list[1].placed && claims.list[1].address == 0
	assert claims.list[0].placed && claims.list[0].address == 0x100
}

fn test_arrivals_go_after_what_is_already_there() {
	windows := pc_port()
	mut taken := Taken{}
	// A sibling function with 128 KiB at the start of the window, another
	// with 16 MiB of prefetchable memory, and one outside every window,
	// which counts for nothing.
	taken.note(windows, 0x8100_0000, 0x2_0000, false)
	taken.note(windows, 0xc0_0000_0000, 16 * mib, false)
	taken.note(windows, 0x9000_0000, 0x1000, false)
	taken.note(windows, 0x1000, 0x40, true)
	assert taken.memory == 0x8102_0000
	assert taken.prefetchable == 0xc0_0100_0000
	assert taken.io == 0
	mut claims := Claims{}
	claims.add(memory_claim(0x4_0000, 2, 0))
	claims.add(Claim{ size: mib, prefetchable: true, wide: true })
	assert claims.place(windows, taken) == 2
	// Aligned to its own size, past the sibling.
	assert claims.list[0].address == 0x8104_0000
	assert claims.list[1].address == 0xc0_0100_0000
	// A window already full takes nothing more.
	mut full := Taken{}
	full.note(windows, 0x8100_0000, 2 * mib, false)
	mut late := Claims{}
	late.add(memory_claim(0x1000, 0, 0))
	assert late.place(windows, full) == 0
}

fn test_a_device_found_again_is_left_where_it_is() {
	windows := pc_port()
	mut claims := Claims{}
	claims.add(Claim{ size: 0x2_0000, address: 0x8100_0000 })
	claims.add(Claim{ size: 16 * mib, prefetchable: true, wide: true, address: 0xc0_0000_0000 })
	// An I/O register this port could never have given an address.
	claims.add(Claim{ size: 0x40, io: true })
	assert claims.settled(windows)
	// Memory at address 0 is a register nobody has set.
	mut fresh := Claims{}
	fresh.add(Claim{ size: 0x2_0000 })
	assert !fresh.settled(windows)
	// An address outside what the port forwards is not settled either.
	mut astray := Claims{}
	astray.add(Claim{ size: 0x2_0000, address: 0x9000_0000 })
	assert !astray.settled(windows)
	// Nor is a plain register found in the prefetchable window.
	mut misplaced := Claims{}
	misplaced.add(Claim{ size: mib, wide: true, address: 0xc0_0000_0000 })
	assert !misplaced.settled(windows)
	// Behind a bridge that forwards nothing at all there is nothing to do.
	mut nowhere := Claims{}
	nowhere.add(Claim{ size: 0x1000 })
	nowhere.add(Claim{ size: 0x40, io: true })
	assert nowhere.settled(Windows{})
	// With an I/O window, an I/O register has to be inside it.
	with_io := Windows{
		memory: windows.memory
		io:     Window{0x1000, 0x2000}
	}
	mut ports := Claims{}
	ports.add(Claim{ size: 0x40, io: true })
	assert !ports.settled(with_io)
	mut placed_ports := Claims{}
	placed_ports.add(Claim{ size: 0x40, io: true, address: 0x1040 })
	assert placed_ports.settled(with_io)
}

fn test_claims_that_cannot_be_registers_are_refused() {
	mut claims := Claims{}
	assert !claims.add(Claim{ size: 0 })
	assert !claims.add(Claim{ size: 0x3000 })
	for i in 0 .. max_claims {
		assert claims.add(memory_claim(0x1000, u8(i / 6), u8(i % 6)))
	}
	assert !claims.add(memory_claim(0x1000, 0, 0))
	assert claims.count == max_claims
	// A claim arrives unplaced whatever its maker said.
	mut one := Claims{}
	one.add(Claim{ size: 0x1000, placed: true, address: 0x5000 })
	assert !one.list[0].placed
	assert one.list[0].address == 0x5000
}

fn test_a_narrow_register_never_lands_above_four_gib() {
	// A plain window that is not below 4 GiB cannot exist on real hardware;
	// if firmware's registers ever describe one, a 32-bit register must
	// still not be given an address it cannot hold.
	high := Windows{
		memory: Window{4 * gib, 4 * gib + 2 * mib}
	}
	mut claims := Claims{}
	claims.add(Claim{ size: 0x1000 })
	claims.add(Claim{ size: 0x1000, wide: true })
	assert claims.place(high, Taken{}) == 1
	assert !claims.list[0].placed
	assert claims.list[1].placed
}
