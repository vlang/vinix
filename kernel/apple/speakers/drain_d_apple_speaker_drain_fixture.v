// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module speakers

import apple.speakers.spkcore
import errno

__global fault_on_drain_tail bool

fn fault_during_drain_tail(ns i64) {
	if fault_on_drain_tail && ns == drain_tail_ns {
		fault_on_drain_tail = false
		speaker_stream.lock()
		C.vinix_apple_speakers_fail()
		speaker_stream.unlock()
	}
}

fn drain_result() u64 {
	errno.set(errno.einval)
	speaker_stream.wait_until_empty() or { return errno.get() }
	return 0
}

pub fn test_drain_faults() {
	saved_errno := errno.get()
	defer {
		fault_on_drain_tail = false
		spkcore.end_drain_test()
		errno.set(saved_errno)
	}
	spkcore.begin_drain_test()
	if drain_result() != 0 || C.vinix_apple_speakers_configure(48000) != 1 || drain_result() != 0
		|| C.vinix_apple_speakers_active() != 0 {
		print('HWTEST FAIL apple-speaker-drain: healthy drain did not stop cleanly\n')
		return
	}
	print('apple-speakers drain test: healthy idle and empty playback drained\n')

	C.vinix_apple_speakers_fail()
	inactive_result := drain_result()
	if C.vinix_apple_speakers_active() == 0 && inactive_result == errno.eio
		&& spkcore.drain_test_shutdown_asserted() {
		print('apple-speakers drain test: inactive fault returned EIO\n')
	} else {
		C.kprintf(c'HWTEST FAIL apple-speaker-drain: inactive fault drain returned %llu\n',
			inactive_result)
	}

	spkcore.begin_drain_test()
	if C.vinix_apple_speakers_configure(44100) != 1 {
		print('HWTEST FAIL apple-speaker-drain: could not prepare tail fixture\n')
		return
	}
	fault_on_drain_tail = true
	tail_result := drain_result()
	if !fault_on_drain_tail && tail_result == errno.eio && spkcore.drain_test_shutdown_asserted()
		&& C.vinix_apple_speakers_configure(48000) == 0 && drain_result() == errno.eio {
		print('apple-speakers drain test: tail fault returned EIO and shutdown stayed latched\n')
	} else {
		C.kprintf(c'HWTEST FAIL apple-speaker-drain: tail fault drain returned %llu\n', tail_result)
	}
}
