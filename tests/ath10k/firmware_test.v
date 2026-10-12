// SPDX-License-Identifier: ISC
module ath10k

import os

fn fixture_ie(mut out []u8, id u32, bytes []u8) {
	for n in [id, u32(bytes.len)] {
		for shift in [0, 8, 16, 24] { out << u8(n >> shift) }
	}
	out << bytes
	for out.len & 3 != 0 { out << 0 }
}

fn fixture_firmware() []u8 {
	mut out := 'QCA-ATH10K\x00'.bytes()
	for out.len & 3 != 0 { out << 0 }
	fixture_ie(mut out, 3, [u8(1), 2, 3])
	fixture_ie(mut out, 4, [u8(4), 5])
	fixture_ie(mut out, 5, [u8(4), 0, 0, 0])
	fixture_ie(mut out, 6, [u8(3), 0, 0, 0])
	return out
}

fn test_api6_borrowed_images_and_unknown_metadata() {
	mut bytes := fixture_firmware()
	fixture_ie(mut bytes, 100, [u8(9), 8, 7])
	fw := parse_firmware(fixture_blob(bytes)) or { panic('valid API 6 refused') }
	assert fw.wmi == 4 && fw.htt == 3
	assert fw.program.len == 3 && unsafe { fw.program.data[2] } == 3
	assert fw.otp.len == 2 && unsafe { fw.otp.data[1] } == 5
	assert u64(fw.program.data) >= u64(bytes.data) && u64(fw.program.data) < u64(bytes.data) + u64(bytes.len)
}

fn test_truncation_duplicate_incompatible_and_swap_are_refused() {
	bytes := fixture_firmware()
	for size in 0 .. bytes.len {
		assert parse_firmware(fixture_blob(bytes[..size])) == none
	}
	mut duplicate := bytes.clone()
	fixture_ie(mut duplicate, 3, [u8(0)])
	assert parse_firmware(fixture_blob(duplicate)) == none
	mut swapped := bytes.clone()
	fixture_ie(mut swapped, 7, [u8(1)])
	assert parse_firmware(fixture_blob(swapped)) == none
	mut incompatible := bytes.clone()
	incompatible[incompatible.len - 4] = 4
	assert parse_firmware(fixture_blob(incompatible)) == none
	mut oversized := bytes.clone()
	for i in 16 .. 20 { oversized[i] = 0xff }
	assert parse_firmware(fixture_blob(oversized)) == none
}

fn test_exact_lenovo_board_selection_and_no_generic_calibration_fallback() {
	name := 'bus=pci,vendor=168c,device=0042,subsystem-vendor=17aa,subsystem-device=0901'
	mut entry := []u8{}
	fixture_ie(mut entry, 0, name.bytes())
	fixture_ie(mut entry, 1, []u8{len: 8124, init: 0x5a})
	mut bytes := 'QCA-ATH10K-BOARD\x00'.bytes()
	for bytes.len & 3 != 0 { bytes << 0 }
	fixture_ie(mut bytes, 0, entry)
	board := select_board(fixture_blob(bytes), name) or { panic('matching board refused') }
	assert board.len == 8124 && unsafe { board.data[0] } == 0x5a
	assert select_board(fixture_blob(bytes), 'bus=pci,vendor=168c,device=0042,subsystem-vendor=0000,subsystem-device=0000') == none
	for size in 0 .. bytes.len {
		assert select_board(fixture_blob(bytes[..size]), name) == none
	}
	fixture_ie(mut bytes, 0, entry)
	assert select_board(fixture_blob(bytes), name) == none
}

fn test_pinned_qca9377_firmware_and_board_images_when_supplied() {
	path := os.getenv('ATH10K_REFERENCE_DIR')
	if path == '' { return }
	bytes := os.read_bytes(path + '/firmware-6.bin') or { panic(err) }
	fw := parse_firmware(fixture_blob(bytes)) or { panic('real QCA9377 firmware refused') }
	assert fw.program.len == 727125 && fw.otp.len == 24193
	board_bytes := os.read_bytes(path + '/board-2.bin') or { panic(err) }
	name := 'bus=pci,vendor=168c,device=0042,subsystem-vendor=17aa,subsystem-device=0901'
	board := select_board(fixture_blob(board_bytes), name) or { panic('Lenovo 17aa:0901 board missing') }
	assert board.len == 8124
}
