// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
// Target setup follows Linux v6.6 ath10k QCA9377 PCI/BMI initialization.
module ath10k

fn valid_target_pointer(address u32) bool {
	return address >= 0x400000 && address < 0x500000 && address & 3 == 0
}

pub fn (mut t Transport) reset_rom() bool {
	// PCI memory decoding is already on, bus mastering is still disabled.
	global := t.read(0x80008)
	if global == 0xffffffff { return false }
	t.write(0x80008, global | 1)
	t.delay(20000)
	t.write(0x80008, global & ~u32(1))
	t.delay(20000)
	t.write(0x80004, 1)
	if !t.wait(0x80000, 7, 3, 3000) || !t.wait(0x3a028, 3, 2, 3000) { return false }
	// QCA9377 needs a cold reset followed by the QCA6174 warm sequence.
	t.write(0x3a008, 0)
	t.write(0x3a014, 0x7fc00)
	t.delay(20000)
	for phase in 0 .. 2 {
		t.write(0x3a028, 0)
		t.write(0x800, t.read(0x800) | 0x40)
		t.initialise_engines()
		if !t.wait(0x3a028, 3, 2, 3000) { return false }
		if phase == 0 {
			t.write(0x850, t.read(0x850) & ~u32(4))
			t.write(0x800, t.read(0x800) | 1)
			t.delay(10000)
			t.write(0x800, t.read(0x800) & ~u32(1))
		}
	}
	return true
}

fn (mut t Transport) diag_read(address u32) ?u32 { return t.diagnostic(address, false, 0) }

fn (mut t Transport) diag_write(address u32, value u32) bool {
	t.diagnostic(address, true, value) or { return false }
	return true
}

pub fn (mut t Transport) configure_pcie_target() bool {
	// This runs after all CE descriptors are mapped and mastering is enabled.
	state := t.diag_read(0x4008f8) or { return false }
	if !valid_target_pointer(state) || state > 0x4fffc0 { return false }
	pipes := t.diag_read(state) or { return false }
	services := t.diag_read(state + 4) or { return false }
	if !valid_target_pointer(pipes) || pipes > 0x4fff00
		|| !valid_target_pointer(services) || services > 0x4fff00 {
		return false
	}
	directions := [u32(2), 1, 1, 2, 2, 2, 3]!
	counts := [u32(32), 32, 64, 32, 256, 32, 32]!
	sizes := [u32(256), 2048, 2048, 2048, 256, 2048, 4096]!
	for id in u32(0) .. 7 {
		values := [id, directions[id], counts[id], sizes[id], u32(0), 0]!
		for n in u32(0) .. 6 {
			if !t.diag_write(pipes + id * 24 + n * 4, values[n]) { return false }
		}
	}
	ids := [u32(0x104), 0x104, 0x102, 0x102, 0x101, 0x101, 0x103, 0x103, 0x100, 0x100, 1, 1, 0xfe00,
		0xfe00, 0x300, 0x300, 0]!
	for n in u32(0) .. 17 {
		direction := if n == 16 {
			u32(0)
		} else if n & 1 == 0 {
			u32(2)
		} else {
			u32(1)
		}
		pipe := if n < 10 {
			if n & 1 == 0 { u32(3) } else { u32(2) }
		} else if n < 14 {
			if n & 1 == 0 { u32(0) } else { u32(1) }
		} else if n == 14 {
			u32(4)
		} else if n == 15 {
			u32(1)
		} else {
			u32(0)
		}
		values := [ids[n], direction, pipe]!
		for word in u32(0) .. 3 {
			if !t.diag_write(services + n * 12 + word * 4, values[word]) { return false }
		}
	}
	flags := t.diag_read(state + 32) or { return false }
	if !t.diag_write(state + 32, flags & ~u32(1)) { return false }
	allocation := t.diag_read(0x400900) or { return false }
	if !t.diag_write(0x400900, allocation | 0x6d8a0009) { return false }
	options := t.diag_read(0x4008cc) or { return false }
	if !t.diag_write(0x4008cc, options | 0x10) { return false }
	t.write(0x3a000, t.read(0x3a000) | 0x2000)
	return true
}

fn (mut t Transport) soc_update(address u32, clear u32, set u32) bool {
	value := t.bmi_word(6, address, 0) or { return false }
	t.bmi_word(7, address, (value & ~clear) | set) or { return false }
	return true
}

// Hardware revision 1.1 requires the reference-clock-specific PLL sequence.
// These eight clock tuples are Qualcomm's qca6174_clk table, in efuse order.
fn (mut t Transport) pll() bool {
	efuse := t.bmi_word(6, 0xb2c, 0) or { return false }
	index := (efuse >> 8) & 7
	dividers := [u32(0xe), 0x24, 0x1d, 0x1b, 0x12, 0x12, 0x12, 0x1b]!
	fractions := [u32(0x2aaa8), 0x2aaa8, 0x15551, 0x4ec4, 0x34b49, 0x15551, 0x26665, 0x4ec4]!
	settle := [u32(2400), 960, 1200, 1300, 1870, 1920, 2000, 2600]!
	if !t.soc_update(0xaf4, 0x1fffff, fractions[index] | (1 << 18))
		|| !t.soc_update(0x1018, 0x7ff, settle[index] & 0x7ff)
		|| !t.soc_update(0x914, 7, 1) {
		return false
	}
	t.bmi_word(3, 0x404028, 1) or { return false }
	if !t.soc_update(0x1014, 0, dividers[index] | 0x40000) { return false }
	for phase in 0 .. 2 {
		start := t.now()
		for {
			status := t.bmi_word(6, 0x1244, 0) or { return false }
			if status & 0x20 == 0 { break }
			if t.now() - start >= u64(1000000000) { return false }
			t.delay(10)
		}
		if phase == 0 && !t.soc_update(0x1014, 0x10000, 0) { return false }
	}
	if !t.soc_update(0x820, 3, 1) || !t.soc_update(0x1014, 0x40000, 0) { return false }
	t.bmi_word(3, 0x404020, 1) or { return false }
	t.bmi_word(3, 0x404024, 176000000) or { return false }
	return true
}

pub fn (mut t Transport) boot(fw Firmware, board Blob) ?u32 {
	version := t.bmi_word(8, 0, 0) or { return none }
	if version != 0x05020000 && version != 0x05020001 { return none }
	if version == 0x05020001 && !t.pll() { return none }
	t.bmi_word(3, 0x400800, 2) or { return none }
	options := t.bmi_word(2, 0x400810, 0) or { return none }
	t.bmi_word(3, 0x400810, options | 0x2208) or { return none }
	t.bmi_word(3, 0x400844, 0) or { return none }
	t.bmi_word(3, 0x400904, 0) or { return none }
	t.bmi_word(3, 0x4008bc, 0x42) or { return none }
	board_address := t.bmi_word(2, 0x400854, 0) or { return none }
	if !valid_target_pointer(board_address) || board_address > 0x4fd000 || board.len != 8124 {
		return none
	}
	if !t.bmi_write(board_address, board) { return none }
	t.bmi_word(3, 0x400858, 1) or { return none }
	if !t.download(0x1234, fw.otp) { return none }
	result := t.bmi_word(4, 0x1234, 0) or { return none }
	ignore_otp := fw.features.len != 0 && unsafe { fw.features.data[0] } & 0x80 != 0
	if result != 0 && !ignore_otp { return none }
	if !t.download(0x1234, fw.program) { return none }
	mut done := [4]u8{}
	put32(unsafe { &done[0] }, 0, 1)
	t.bmi(Blob{ data: unsafe { &done[0] }, len: 4 }, 0) or { return none }
	return version
}
