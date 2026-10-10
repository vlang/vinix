// SPDX-License-Identifier: GPL-2.0-or-later
module bootcapture

// The complete transcript is streamed to disk. Keep only enough boundary
// bytes to detect a marker split across two pipe reads, without repeated
// copies of a growing development-kernel serial trace.
pub struct Capture {
pub mut:
	done   bool
	failed bool
mut:
	bytes [512]u8
	used  int
}

fn boot_done(text string) bool {
	return text.contains('PLAN DONE\n') || text.contains('PLAN DONE\r')
}

fn boot_failed(text string) bool {
	return text.contains('PLAN FAIL') || text.contains('KERNEL PANIC')
		|| text.contains('FATAL EXCEPTION')
}

pub fn (mut capture Capture) observe(chunk string) {
	capture.done = capture.done || boot_done(chunk)
	capture.failed = capture.failed || boot_failed(chunk)
	prefix := if chunk.len < 256 { chunk.len } else { 256 }
	for i in 0 .. prefix {
		capture.bytes[capture.used + i] = chunk[i]
	}
	length := capture.used + prefix
	boundary := unsafe { tos(&capture.bytes[0], length) }
	capture.done = capture.done || boot_done(boundary)
	capture.failed = capture.failed || boot_failed(boundary)
	if chunk.len >= 256 {
		for i in 0 .. 256 {
			capture.bytes[i] = chunk[chunk.len - 256 + i]
		}
		capture.used = 256
	} else {
		capture.used = if length < 256 { length } else { 256 }
		start := length - capture.used
		for i in 0 .. capture.used {
			capture.bytes[i] = capture.bytes[start + i]
		}
	}
}
