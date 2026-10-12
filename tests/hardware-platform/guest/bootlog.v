// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

fn scenario_bootlog(mut t Test) {
	mode := os.stat('/proc/bootlog') or {
		t.check(false, 'boot log missing')
		return
	}
	t.check(mode.mode & 0o444 == 0o444, 'kernel log is readable without a Settings action')
	fd := C.open(c'/proc/bootlog', C.O_RDONLY)
	if fd < 0 {
		t.check(false, 'open boot log')
		return
	}
	defer { C.close(fd) }
	mut chunk := []u8{len: 31}
	first := int(C.read(fd, chunk.data, usize(chunk.len)))
	if !t.check(first > 0, 'boot diagnostics were retained') { return }
	// A new diagnostic arrives while the reader is part-way through the
	// file. Its open snapshot must finish; a new open sees the new message.
	marker := 'sysrq: pid=1 '
	write_text('/proc/sysrq-trigger', 't') or {
		t.check(false, 'request task diagnostics: ${err}')
		return
	}
	mut content := chunk[..first].clone()
	for {
		count := int(C.read(fd, chunk.data, usize(chunk.len)))
		if count < 0 {
			t.check(false, 'chunked boot log read')
			return
		}
		if count == 0 { break }
		content << chunk[..count]
		t.check(content.len <= 256 * 1024, 'boot log has a bounded size')
		if content.len > 256 * 1024 { return }
	}
	t.check(!content.bytestr().contains(marker), 'open log keeps a consistent snapshot')
	latest := read_text('/proc/bootlog') or {
		t.check(false, 'reopen boot log: ${err}')
		return
	}
	t.check(latest.contains(marker), 'new log open sees new diagnostics')
	t.check(latest.contains('e1000: ready'), 'Ethernet driver startup is visible')
	for _ in 0 .. 32 {
		_ = read_text('/proc/bootlog') or {
			t.check(false, 'repeat log open: ${err}')
			return
		}
	}
}
