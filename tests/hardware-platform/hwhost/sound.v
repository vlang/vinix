// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the machine played.
//
// QEMU can write everything a sound card plays into a WAV file
// (`-audiodev wav`). A guest that plays a square wave of a height nothing
// else would produce leaves frames at exactly plus and minus that height in
// the file, and a scenario lists the heights it must find: a tone played
// after a sleep is in the file only if the card, its link and its codec all
// came back, which a write that merely returned does not show.
module hwhost

import os

// A recording a scenario's machine makes into the state directory, and the
// heights that must be in it.
pub struct Sound {
pub:
	file string
	// Each must be the height, plus or minus, of at least `frames` frames.
	levels []int
	frames int
}

pub struct Recording {
pub:
	channels int
	rate     int
	// The first channel of every frame, 16 bits signed.
	samples []i16
}

// How far a sample may be from a height and still count: resampling and
// volume leave the plateaus of a square wave where they were to within a
// few steps.
pub const level_tolerance = 64

fn wav_u16(data []u8, at int) int {
	return int(data[at]) | (int(data[at + 1]) << 8)
}

fn wav_u32(data []u8, at int) int {
	return wav_u16(data, at) | (wav_u16(data, at + 2) << 16)
}

// Takes a 16-bit PCM WAV file apart. A file whose writer was stopped before
// it could fill in the lengths is read to its end.
pub fn read_recording(data []u8) !Recording {
	if data.len < 12 || data[..4].bytestr() != 'RIFF' || data[8..12].bytestr() != 'WAVE' {
		return error('not a WAV file')
	}
	mut channels := 0
	mut rate := 0
	mut bits := 0
	mut at := 12
	for at + 8 <= data.len {
		name := data[at..at + 4].bytestr()
		mut length := wav_u32(data, at + 4)
		at += 8
		if length < 0 || length > data.len - at || (name == 'data' && length == 0) {
			length = data.len - at
		}
		if name == 'fmt ' {
			if length < 16 {
				return error('a format chunk of ${length} bytes')
			}
			if wav_u16(data, at) != 1 {
				return error('not plain PCM')
			}
			channels = wav_u16(data, at + 2)
			rate = wav_u32(data, at + 4)
			bits = wav_u16(data, at + 14)
		} else if name == 'data' {
			if channels < 1 || bits != 16 {
				return error('${bits}-bit sound with ${channels} channels is not what this reads')
			}
			frame := channels * 2
			mut samples := []i16{cap: length / frame}
			for offset := at; offset + frame <= at + length; offset += frame {
				samples << i16(u16(wav_u16(data, offset)))
			}
			return Recording{
				channels: channels
				rate:     rate
				samples:  samples
			}
		}
		at += length + (length & 1)
	}
	return error('no sound data in the file')
}

// How many frames are at `level`, plus or minus.
pub fn (r &Recording) frames_at(level int) int {
	mut count := 0
	for value in r.samples {
		height := if value < 0 { -int(value) } else { int(value) }
		if height >= level - level_tolerance && height <= level + level_tolerance {
			count++
		}
	}
	return count
}

// What is missing from a recording; '' if nothing.
pub fn judge_recording(recording &Recording, sound Sound) string {
	for level in sound.levels {
		found := recording.frames_at(level)
		if found < sound.frames {
			return '${found} frames at height ${level}, of at least ${sound.frames} that were to be played'
		}
	}
	return ''
}

pub fn check_sound(sound Sound, state string) ! {
	data := os.read_bytes(os.join_path(state, sound.file)) or {
		return error('${sound.file}: nothing was recorded')
	}
	recording := read_recording(data) or { return error('${sound.file}: ${err.msg()}') }
	problem := judge_recording(&recording, sound)
	if problem != '' {
		return error('${sound.file}: ${problem}')
	}
}
