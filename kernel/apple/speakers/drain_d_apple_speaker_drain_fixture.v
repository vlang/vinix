// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module speakers

import apple.speakers.spkcore
import errno
import katomic

__global (
	fault_on_drain_tail bool
	fault_on_write_wait bool
	check_write_lock bool
)

fn fault_during_speaker_wait(ns i64) {
	if fault_on_drain_tail && ns == drain_tail_ns {
		fault_on_drain_tail = false
	} else if fault_on_write_wait && ns == running_period_ns {
		fault_on_write_wait = false
	} else {
		return
	}
	speaker_stream.lock()
	C.vinix_apple_speakers_fail()
	speaker_stream.unlock()
}

fn fault_if_write_unlocked(mut s SpeakerStream) {
	if !check_write_lock {
		return
	}
	check_write_lock = false
	// Model a service iteration that takes the lock after reserve. It can
	// run here only if the write released the lock before copying.
	if katomic.cas(mut s.mutex, u64(0), u64(1)) {
		C.vinix_apple_speakers_fail()
		s.unlock()
		print('HWTEST FAIL apple-speaker-write: protection interleaved with a reserved copy\n')
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

pub fn test_write_fault() {
	saved_errno := errno.get()
	defer {
		check_write_lock = false
		fault_on_write_wait = false
		spkcore.end_drain_test()
		errno.set(saved_errno)
	}
	spkcore.begin_write_test()
	input := [i16(12), -24, 36, -48, 60, -72, 84, -96, 108, -120, 132, -144]!
	buffer := unsafe { &input[0] }
	check_write_lock = true
	fault_on_write_wait = true
	written := speaker_stream.sync_write(buffer, 0, 24) or { -i64(errno.get()) }
	if check_write_lock || fault_on_write_wait || written != 16
		|| !spkcore.write_test_prefix_matches(buffer) {
		C.kprintf(c'HWTEST FAIL apple-speaker-write: faulted write returned %lld\n', written)
		return
	}
	print('apple-speakers write test: exactly one ring committed before fault\n')
	errno.set(errno.einval)
	refused := speaker_stream.sync_write(buffer, 0, 4) or { -i64(errno.get()) }
	if refused != -i64(errno.eio) || !spkcore.drain_test_shutdown_asserted() {
		C.kprintf(c'HWTEST FAIL apple-speaker-write: latched fault write returned %lld\n', refused)
		return
	}
	print('apple-speakers write test: later write returned EIO with shutdown latched\n')
}
