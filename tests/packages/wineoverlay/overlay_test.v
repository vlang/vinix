// SPDX-License-Identifier: GPL-2.0-or-later
module wineoverlay

import os

fn need(ok bool, message string) { if !ok { panic(message) } }
fn number(mut bytes []u8, start int, size int, value u64) {
	for index in start .. start + size - 1 { bytes[index] = `0` }
	bytes[start + size - 1] = 0
	mut n := value
	mut index := start + size - 2
	for n > 0 { bytes[index] = u8(`0`) + u8(n % 8); n /= 8; index-- }
}
fn header(size int, kind u8) []u8 {
	mut bytes := []u8{len: 512}
	for index, byte in './sbin/init' { bytes[index] = byte }
	for index, byte in 'ustar\x00' { bytes[257 + index] = byte }
	number(mut bytes, 124, 12, u64(size)); bytes[156] = kind
	for index in 148 .. 156 { bytes[index] = ` ` }
	mut sum := u64(0)
	for byte in bytes { sum += byte }
	number(mut bytes, 148, 8, sum)
	return bytes
}
fn fixture(path string, size int, duplicate bool, kind u8) ! {
	mut file := os.create(path)!
	defer { file.close() }
	padding := []u8{len: 512}
	defer { unsafe { padding.free() } }
	file.write(padding)!
	for _ in 0 .. if duplicate { 2 } else { 1 } {
		bytes := header(size, kind)
		file.write(bytes)!
		unsafe { bytes.free() }
		payload := []u8{len: size, init: u8(`A`)}
		file.write(payload)!
		unsafe { payload.free() }
	}
	file.write(padding)!; file.write(padding)!
}
fn test_fixed_extent_overlay_and_refusals() {
	$if !macos { return }
	root := os.join_path(os.temp_dir(), 'vinix-wine-overlay-' + os.getpid().str())
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	original := root + '/original'; target := root + '/copy'; guest := root + '/guest'
	fixture(original, 4096, false, `0`)!
	os.write_file(guest, 'new ELF bytes')!
	old := digest(original)!
	span := init_span(original, Span{512, 5632})!
	need(span.offset == 1024 && span.size == 4096, 'member bounds differ')
	clone_fresh(original, target)!
	patched := patch_init(original, target, guest, Span{512, 5632}, range_digest(original, 1024, 4096)!)!
	need(patched == span && digest(original)! == old, 'overlay changed original/member extent')
	verify_delta(original, target, guest, span)!
	mut file := os.open_file(target, 'r+')!
	file.seek(1, .start)!; file.write([u8(1)])!; file.close()
	mut refused := false
	verify_delta(original, target, guest, span) or { refused = true; unsafe { err.free() } }
	need(refused, 'outside-member mutation accepted')
	os.rm(target)!
	clone_fresh(original, target)!
	refused = false
	patch_init(original, target, guest, Span{512, 5632}, '0'.repeat(64)) or { refused = true; unsafe { err.free() } }
	need(refused && digest(target)! == old, 'wrong old payload pin changed target')
	oversized := 'B'.repeat(4097)
	os.write_file(guest, oversized)!
	refused = false
	patch_init(original, target, guest, Span{512, 5632}, range_digest(original, 1024, 4096)!) or { refused = true; unsafe { err.free() } }
	need(refused && digest(target)! == old, 'oversized guest changed target')
	os.write_file(guest, 'new ELF bytes')!
	patch_init(original, target, guest, Span{512, 5632}, range_digest(original, 1024, 4096)!)!
	file = os.open_file(target, 'r+')!
	file.seek(i64(span.offset + os.file_size(guest)), .start)!; file.write([u8(1)])!; file.close()
	refused = false
	verify_delta(original, target, guest, span) or { refused = true; unsafe { err.free() } }
	need(refused, 'nonzero padding accepted')
	file = os.open_file(target, 'r+')!
	file.seek(i64(span.offset + os.file_size(guest)), .start)!; file.write([u8(0)])!
	file.seek(i64(span.offset), .start)!; file.write([u8(`X`)])!; file.close()
	refused = false
	verify_delta(original, target, guest, span) or { refused = true; unsafe { err.free() } }
	need(refused && digest(original)! == old, 'changed guest accepted or original changed')
	fixture(root + '/duplicate', 4096, true, `0`)!
	refused = false
	init_span(root + '/duplicate', Span{512, 10240}) or { refused = true; unsafe { err.free() } }
	need(refused, 'duplicate init accepted')
	fixture(root + '/link', 0, false, `2`)!
	refused = false
	init_span(root + '/link', Span{512, 1536}) or { refused = true; unsafe { err.free() } }
	need(refused, 'linked init accepted')
	refused = false
	init_span(original, Span{512, 999999}) or { refused = true; unsafe { err.free() } }
	need(refused, 'invalid extent accepted')
	os.cp(original, root + '/bad-header')!
	file = os.open_file(root + '/bad-header', 'r+')!
	file.seek(512 + 100, .start)!; file.write([u8(1)])!; file.close()
	refused = false
	init_span(root + '/bad-header', Span{512, 5632}) or { refused = true; unsafe { err.free() } }
	need(refused, 'bad header checksum accepted')
	refused = false
	init_span(original, Span{512, 5120}) or { refused = true; unsafe { err.free() } }
	need(refused, 'missing end marker accepted')
	println('WINE OVERLAY PASS fixed member; original intact; delta and refusal checks')
}
