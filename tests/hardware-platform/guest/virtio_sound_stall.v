// SPDX-License-Identifier: GPL-2.0-or-later
module main

import time

fn virtio_stall_open(mut t Test, rate i32) int {
	fd := audio_stall_open(mut t, rate)
	if fd < 0 { return -1 }
	mut format := format_s16_le
	mut channels := i32(2)
	if !t.check(C.ioctl(fd, dsp_setfmt, &format) == 0 && format == format_s16_le
		&& C.ioctl(fd, dsp_channels, &channels) == 0 && channels == 2, 'set VirtIO S16LE stereo') {
		C.close(fd)
		return -1
	}
	return fd
}

fn scenario_virtio_sound_stall(mut t Test) {
	samples := []u8{len: 32 * 1024}
	for _ in 0 .. 2 {
		fd := virtio_stall_open(mut t, 44100)
		if fd < 0 { return }
		// Eight 512-frame stereo periods fit before the stalled queue fills.
		written := C.write(fd, samples.data, usize(samples.len))
		t.check(written == 16 * 1024, 'VirtIO stalled write preserved the queued prefix')
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
			'close released ownership after the stalled VirtIO STOP')

		fresh := virtio_stall_open(mut t, 48000)
		if fresh < 0 { return }
		t.check(C.write(fresh, samples.data, usize(samples.len)) == samples.len,
			'fresh VirtIO stream plays through more than one ring of periods')
		if t.check(C.ioctl(fresh, dsp_sync, voidptr(0)) == 0, 'fresh VirtIO stream drained') {
			t.say('HWTEST STEP fresh stream drained')
		}
		t.check(C.close(fresh) == 0, 'fresh VirtIO stream closed')
	}
}
