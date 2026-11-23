// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

#include <errno.h>

fn audio_stall_open(mut t Test, rate i32) int {
	fd := C.open(c'/dev/dsp', C.O_WRONLY)
	if !t.check(fd >= 0, 'open OSS output') { return -1 }
	mut actual := rate
	if !t.check(C.ioctl(fd, dsp_speed, &actual) == 0 && actual == rate, 'set OSS sample rate') {
		C.close(fd)
		return -1
	}
	return fd
}

fn audio_expect_timeout(mut t Test, result i64, number int, started i64, operation string) {
	elapsed := time.sys_mono_now() - started
	if t.check(result == -1 && number == C.ETIMEDOUT && elapsed >= 1_800_000_000
		&& elapsed < 8_000_000_000, '${operation}: expected bounded ETIMEDOUT, got ${result}, errno ${number}, ${elapsed} ns') {
		t.say('HWTEST STEP ${operation} timed out')
		t.say('HWTEST INFO ${operation} returned ETIMEDOUT after ${elapsed / 1_000_000} ms')
	}
}

fn scenario_hda_stall(mut t Test) {
	fd := audio_stall_open(mut t, 44100)
	if fd < 0 { return }
	// Overshoot the 1 MiB HDA queue so a blocking write has to wait.
	samples := []u8{len: (1 << 20) + 4096, init: 0x80}
	written := C.write(fd, samples.data, usize(samples.len))
	t.check(written == 1 << 20, 'stalled oversized write returned the exact queued prefix')
	write_started := time.sys_mono_now()
	refused := C.write(fd, samples.data, 4096)
	write_errno := C.errno
	audio_expect_timeout(mut t, refused, write_errno, write_started, 'stalled write')
	drain_started := time.sys_mono_now()
	drain := C.ioctl(fd, dsp_sync, voidptr(0))
	drain_errno := C.errno
	audio_expect_timeout(mut t, i64(drain), drain_errno, drain_started, 'stalled drain')
	close_started := time.sys_mono_now()
	t.check(C.close(fd) == 0 && time.sys_mono_now() - close_started < 8_000_000_000,
		'close reset stalled stream and released the owner')

	fresh := audio_stall_open(mut t, 48000)
	if fresh < 0 { return }
	defer { C.close(fresh) }
	t.check(C.write(fresh, samples.data, 4096) == 4096, 'fresh stream accepts a short buffer')
	// A sub-threshold write needs the drain to start playback.
	if t.check(C.ioctl(fresh, dsp_sync, voidptr(0)) == 0, 'fresh stream drains successfully') {
		t.say('HWTEST STEP fresh stream drained')
	}
}
