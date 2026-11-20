// SPDX-License-Identifier: GPL-2.0-or-later
// A bounded, allocation-free history of kernel output. Desktop graphics mode
// suppresses the console, but must not make driver diagnostics disappear.
@[has_globals]
module kprint

import lib

const bootlog_bytes = 256 * 1024

struct BootLog {
mut:
	data   [bootlog_bytes]u8
	start  int
	length int
	// Every byte ever appended, so readers can name positions across wraps.
	written u64
}

pub const bootlog_capacity = bootlog_bytes

__global bootlog BootLog

// Caller holds kprint_lock, also used by snapshot(). No allocation or print
// is allowed on this path, including during the earliest boot messages.
fn (mut log BootLog) append(message voidptr, length u64) {
	for i := u64(0); i < length; i++ {
		log.data[(log.start + log.length) % bootlog_bytes] = unsafe { (&u8(message))[i] }
		if log.length < bootlog_bytes {
			log.length++
		} else {
			log.start = (log.start + 1) % bootlog_bytes
		}
	}
	log.written += length
}

// Owned text, freed by procfs when the open file closes. Allocate before
// taking the print lock so allocation diagnostics cannot recurse into it.
pub fn bootlog_snapshot() string {
	mut text := lib.new_text(bootlog_bytes + 1)
	kprint_lock.acquire()
	for i in 0 .. bootlog.length {
		text.add_byte(bootlog.data[(bootlog.start + i) % bootlog_bytes])
	}
	kprint_lock.release()
	return lib.finish_text(text)
}

// Copy the retained log into `buffer`, bootlog_capacity bytes, under the print
// lock: its length, and the position of its first byte among every byte ever
// logged. syslog(2) reads through this.
pub fn bootlog_capture(buffer voidptr) (int, u64) {
	mut out := unsafe { &u8(buffer) }
	kprint_lock.acquire()
	for i in 0 .. bootlog.length {
		unsafe {
			out[i] = bootlog.data[(bootlog.start + i) % bootlog_bytes]
		}
	}
	length := bootlog.length
	base := bootlog.written - u64(bootlog.length)
	kprint_lock.release()
	return length, base
}
