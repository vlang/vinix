// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module hwhost

import os

fn le16(value int) []u8 {
	return [u8(value), u8(value >> 8)]
}

fn le32(value int) []u8 {
	return [u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)]
}

// A stereo 16-bit WAV file of the frames given, each as (left, right).
fn wav(frames [][]int, declared_length int) []u8 {
	mut samples := []u8{}
	for frame in frames {
		samples << le16(frame[0])
		samples << le16(frame[1])
	}
	length := if declared_length < 0 { samples.len } else { declared_length }
	mut data := 'RIFF'.bytes()
	data << le32(36 + length)
	data << 'WAVE'.bytes()
	data << 'fmt '.bytes()
	data << le32(16)
	data << le16(1)
	data << le16(2)
	data << le32(48000)
	data << le32(48000 * 4)
	data << le16(4)
	data << le16(16)
	data << 'data'.bytes()
	data << le32(length)
	data << samples
	return data
}

fn square(level int, frames int) [][]int {
	mut out := [][]int{}
	for i in 0 .. frames {
		value := if (i / 240) % 2 == 0 { level } else { -level }
		out << [value, value]
	}
	return out
}

fn test_heights_are_counted_on_both_sides_of_zero() {
	mut frames := square(6000, 1000)
	frames << square(12000, 500)
	frames << [[0, 0], [0, 0], [3, -3]]
	recording := read_recording(wav(frames, -1))!
	assert recording.channels == 2
	assert recording.rate == 48000
	assert recording.samples.len == 1503
	assert recording.frames_at(6000) == 1000
	assert recording.frames_at(12000) == 500
	assert recording.frames_at(18000) == 0
	// Silence is not a height anything is played at.
	assert recording.frames_at(6000 + level_tolerance + 1) == 0
}

fn test_a_height_a_few_steps_off_still_counts() {
	recording := read_recording(wav([[6000 + level_tolerance, 0], [-(6000 - level_tolerance), 0],
		[6000 + level_tolerance + 1, 0]], -1))!
	assert recording.frames_at(6000) == 2
}

fn test_a_recording_is_judged_by_every_height() {
	mut frames := square(6000, 400)
	frames << square(12000, 90)
	recording := read_recording(wav(frames, -1))!
	assert judge_recording(&recording, Sound{ levels: [6000], frames: 300 }) == ''
	problem := judge_recording(&recording, Sound{ levels: [6000, 12000], frames: 100 })
	assert problem == '90 frames at height 12000, of at least 100 that were to be played'
	assert judge_recording(&recording, Sound{ levels: [18000], frames: 1 }).starts_with('0 frames at height 18000')
}

fn test_a_file_whose_lengths_were_never_filled_in_is_read_to_its_end() {
	// QEMU writes the lengths when it closes the file; one stopped first
	// leaves them at zero.
	recording := read_recording(wav(square(9000, 64), 0))!
	assert recording.samples.len == 64
	assert recording.frames_at(9000) == 64
	// A length past the end of the file is cut to it.
	long := read_recording(wav(square(9000, 10), 4000))!
	assert long.samples.len == 10
}

fn test_what_is_not_a_recording_is_refused() {
	if _ := read_recording('RIFX'.bytes()) {
		assert false, 'four bytes were taken for a WAV file'
	}
	if _ := read_recording('RIFF\x00\x00\x00\x00WAVE'.bytes()) {
		assert false, 'a file with no chunks was taken for a recording'
	}
	mut eight_bit := wav(square(100, 4), -1)
	eight_bit[34] = 8
	if _ := read_recording(eight_bit) {
		assert false, 'eight-bit sound was read as sixteen'
	}
	mut compressed := wav(square(100, 4), -1)
	compressed[20] = 3
	if _ := read_recording(compressed) {
		assert false, 'a format that is not PCM was read'
	}
}

fn test_a_recording_is_judged_from_its_file() {
	state := os.join_path(os.temp_dir(), 'vinix-hwtest-sound-${os.getpid()}')
	os.mkdir_all(state)!
	defer {
		os.rmdir_all(state) or {}
	}
	os.write_file_array(os.join_path(state, 'sound.wav'), wav(square(6000, 500), -1))!
	check_sound(Sound{ file: 'sound.wav', levels: [6000], frames: 400 }, state)!
	check_sound(Sound{ file: 'sound.wav', levels: [6000], frames: 600 }, state) or {
		assert err.msg().starts_with('sound.wav: 500 frames at height 6000')
	}
	check_sound(Sound{ file: 'never.wav', levels: [1], frames: 1 }, state) or {
		assert err.msg() == 'never.wav: nothing was recorded'
		return
	}
	assert false, 'a recording that was never made passed'
}
