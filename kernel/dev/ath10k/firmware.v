// SPDX-License-Identifier: ISC
// Copyright (c) 2026 Alexander Medvednikov
// Container formats from Linux ath10k (Qualcomm Atheros, ISC licensed).
module ath10k

// Views borrow a firmware loader image; they never own or copy its bytes.
pub struct Blob {
pub mut:
	data &u8 = unsafe { nil }
	len  u32
}

pub struct Firmware {
pub:
	program  Blob
	otp      Blob
	version  Blob
	features Blob
	wmi      u32
	htt      u32
}

fn (b Blob) word(offset u32) u32 {
	unsafe {
		return u32(b.data[offset]) | u32(b.data[offset + 1]) << 8 |
			u32(b.data[offset + 2]) << 16 | u32(b.data[offset + 3]) << 24
	}
}

fn (b Blob) view(offset u32, length u32) Blob {
	return Blob{ data: unsafe { b.data + offset }, len: length }
}

fn (b Blob) matches(text string) bool {
	if b.len != u32(text.len) { return false }
	for i in 0 .. text.len { if unsafe { b.data[i] } != text[i] { return false } }
	return true
}

fn (b Blob) magic(text string) bool {
	if b.data == unsafe { nil } || b.len < u32(text.len + 1) { return false }
	return b.view(0, u32(text.len)).matches(text) && unsafe { b.data[text.len] } == 0
}

// API 6 is required on QCA9377 to select the correct IRAM configuration.
// Reject duplicate fields, truncated/padded IEs, swapped/incompatible ABIs
// and code-swap firmware (which needs a separate DMA protocol).
pub fn parse_firmware(b Blob) ?Firmware {
	if !b.magic('QCA-ATH10K') { return none }
	mut position := u32(12)
	mut seen := u32(0)
	mut program := Blob{}
	mut otp := Blob{}
	mut version := Blob{}
	mut features := Blob{}
	mut wmi := u32(0)
	mut htt := u32(0)
	for position < b.len {
		if b.len - position < 8 { return none }
		id := b.word(position)
		size := b.word(position + 4)
		position += 8
		if size > b.len - position || size > ~u32(0) - 3 { return none }
		padded := (size + 3) & ~u32(3)
		if padded > b.len - position { return none }
		field := b.view(position, size)
		if id <= 7 {
			if seen & (u32(1) << id) != 0 { return none }
			seen |= u32(1) << id
		}
		match id {
			0 {
				if size == 0 || size > 128 { return none }
				version = field
			}
			1 {
				if size != 4 { return none }
			}
			2 {
				if size == 0 || size > 32 { return none }
				features = field
			}
			3 {
				if size == 0 || size > 4 * 1024 * 1024 { return none }
				program = field
			}
			4 {
				if size == 0 || size > 128 * 1024 { return none }
				otp = field
			}
			5 {
				if size != 4 { return none }
				wmi = field.word(0)
			}
			6 {
				if size != 4 { return none }
				htt = field.word(0)
			}
			7 { return none }
			else {}
		}
		position += padded
	}
	if program.len == 0 || otp.len == 0 || wmi != 4 || htt != 3 { return none }
	return Firmware{ program: program, otp: otp, version: version, features: features, wmi: wmi, htt: htt }
}

// A board entry comprises nested NAME/DATA IEs. Check the entire entry before
// returning data: even a matching name must not hide malformed trailing IEs.
fn board_entry(b Blob, name string) ?Blob {
	mut position := u32(0)
	mut matched := false
	mut found_name := false
	mut data := Blob{}
	for position < b.len {
		if b.len - position < 8 { return none }
		id := b.word(position)
		size := b.word(position + 4)
		position += 8
		if size > b.len - position || size > ~u32(0) - 3 { return none }
		padded := (size + 3) & ~u32(3)
		if padded > b.len - position { return none }
		field := b.view(position, size)
		match id {
			0 {
				if found_name { return none }
				found_name = true
				matched = field.matches(name)
			}
			1 {
				if data.len != 0 || size == 0 { return none }
				data = field
			}
			else {}
		}
		position += padded
	}
	if !matched || data.len != 8124 { return none }
	return data
}

pub fn select_board(b Blob, name string) ?Blob {
	if !b.magic('QCA-ATH10K-BOARD') || name.len == 0 || name.len > 128 { return none }
	mut position := u32(20)
	mut selected := Blob{}
	for position < b.len {
		if b.len - position < 8 { return none }
		id := b.word(position)
		size := b.word(position + 4)
		position += 8
		if size > b.len - position || size > ~u32(0) - 3 { return none }
		padded := (size + 3) & ~u32(3)
		if padded > b.len - position { return none }
		if id == 0 {
			if candidate := board_entry(b.view(position, size), name) {
				if selected.len != 0 { return none }
				selected = candidate
			}
		}
		position += padded
	}
	if selected.len == 0 { return none }
	return selected
}
