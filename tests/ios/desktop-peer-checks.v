// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.binary
import os
import probedesktop
import time

#include <unistd.h>
fn C.read(int, voidptr, usize) isize
fn C.write(int, voidptr, usize) isize

fn setup(_ string) ! {}

fn fixture_reply(fd int, payload []u8, mode string) {
	mut header := []u8{len: 128}
	binary.little_endian_put_u32(mut header, 0x56415050)
	header[4] = 10
	header[56] = 1
	binary.little_endian_put_u32_at(mut header, u32(payload.len), 124)
	if mode == 'bad-header' { header[0] = 0 }
	if mode == 'bad-state' { header[56] = 0 }
	if mode == 'oversize' { binary.little_endian_put_u32_at(mut header, 1048577, 124) }
	if mode == 'partial' {
		count := C.write(fd, header.data, 5)
		assert count == 5
		for { time.sleep(time.second) }
	}
	// Fragment the header deliberately; transfer must accumulate reads.
	for byte in header {
		count := C.write(fd, unsafe { &byte }, 1)
		assert count == 1
	}
	if payload.len != 0 {
		count := C.write(fd, payload.data, usize(payload.len))
		assert count == payload.len
	}
}

fn fixture(mode string) {
	request := os.getenv('VINIX_REQUEST_FD').int()
	response := os.getenv('VINIX_RESPONSE_FD').int()
	assert request >= 3 && response >= 3 && request != response
	assert os.getenv('VINIX_IOS_EXIT_ON_CLOSE') == '1'
	if mode == 'eof' { return }
	if mode == 'silent' { for { time.sleep(time.second) } }
	fixture_reply(response, if mode == 'nonempty-hello' { [u8(1)] } else { []u8{} }, mode)
	mut polls := 0
	for {
		mut header := []u8{len: 136}
		mut offset := 0
		for offset < header.len {
			count := C.read(request, unsafe { &header[offset] }, usize(header.len - offset))
			if count <= 0 { return }
			offset += int(count)
		}
		assert header[..5] == [u8(0x50), 0x50, 0x41, 0x56, 10]
		assert binary.little_endian_u32_at(header, 8) == 1024
		assert binary.little_endian_u32_at(header, 12) == 768
		assert binary.little_endian_u32_at(header, 132) == 0
		if mode == 'stall-build' { for { time.sleep(time.second) } }
		if header[5] == 1 {
			mut tree := []u8{len: 330}
			if mode == 'bad-tree' { tree << u8(1) }
			fixture_reply(response, tree, '')
		} else if header[5] == 4 {
			fixture_reply(response, [u8(if mode == 'bad-poll' { 2 } else if polls == 0 { 1 } else { 0 })], '')
			polls++
		} else if header[5] == 6 {
			fixture_reply(response, if mode == 'nonempty-close' { [u8(1)] } else { []u8{} }, '')
			return
		} else { panic('unexpected command') }
	}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--fixture' { fixture(os.args[2]); return }
	for mode in ['normal', 'bad-header', 'bad-state', 'oversize', 'partial', 'eof', 'silent',
		'bad-tree', 'stall-build', 'nonempty-hello', 'bad-poll', 'nonempty-close'] {
		start := time.sys_mono_now()
		result := probedesktop.run(os.executable(), ['--fixture', mode], setup, '',
			probedesktop.Config{reply_ms: 300, session_ms: 200}) or { panic(err) }
		assert time.sys_mono_now() - start < i64(5000000000)
		if mode == 'normal' {
			assert result.handshake && result.builds == 2 && result.polls >= 2
			assert result.closed && !result.forced && result.wait_status == 0
		} else {
			assert !result.closed && result.stop != 'session complete'
			if mode in ['silent', 'partial', 'stall-build'] {
				assert result.forced && result.wait_status & 127 == 9
				assert result.stop == 'desktop reply deadline'
			}
			if mode == 'bad-tree' { assert result.stop == 'trailing desktop tree bytes' }
			expected := match mode {
				'bad-header' { 'invalid desktop reply header' }
				'bad-state' { 'invalid desktop state' }
				'oversize' { 'desktop reply exceeds 1 MiB' }
				'eof' { 'desktop pipe closed' }
				'nonempty-hello' { 'nonempty desktop handshake' }
				'bad-poll' { 'invalid desktop poll reply' }
				'nonempty-close' { 'nonempty desktop close reply' }
				else { result.stop }
			}
			assert result.stop == expected
		}
		println('IOS-DESKTOP-PEER: ' + mode + ' PASS')
	}
	for length in [0, 273, 329] {
		probedesktop.validate_tree([]u8{len: length}) or { continue }
		panic('accepted short tree')
	}
	mut nested := []u8{len: 330}
	binary.little_endian_put_u32_at(mut nested, 1, 326)
	probedesktop.validate_tree(nested) or {
		println('IOS-DESKTOP-PEER: truncated trees PASS')
		if os.args.len == 2 {
			result := probedesktop.run(os.abs_path(os.args[1]), [], setup, '',
				probedesktop.Config{reply_ms: 5000, session_ms: 200}) or { panic(err) }
			assert result.handshake && result.nodes >= 1 && result.builds >= 1
			assert result.polls >= 1 && result.closed && !result.forced && result.wait_status == 0
			println('IOS-DESKTOP-PEER: UIKit window PASS')
		}
		println('IOS-DESKTOP-PEER: PASS')
		return
	}
	panic('accepted missing child')
}
