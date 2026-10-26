// SPDX-License-Identifier: GPL-2.0-or-later
// Judge actual stereo output captured by QEMU's WAV backend.
module audiotest

import math
import os

pub struct Recording {
pub:
	rate     int
	channels int
	// Signed interleaved left/right samples, without discarding a channel.
	samples []i16
}

pub struct Tone {
pub:
	frequency       f64
	seconds         f64 = 1
	amplitude       f64 = 12000
	duration_slack  f64 = 0.12
	amplitude_slack f64 = 0.20
}

pub struct Channel {
pub:
	frequency f64
	peak      int
	rms       f64
	mean      f64
}

pub struct Region {
pub:
	start_frame int
	end_frame   int
	left        Channel
	right       Channel
}

fn unsigned(data []u8, offset int, width int) u64 {
	mut value := u64(0)
	for index in 0 .. width { value |= u64(data[offset + index]) << (index * 8) }
	return value
}

pub fn read(path string) !Recording {
	info := os.stat(path)!
	if info.mode & 0o170000 != 0o100000 || info.size > 512 * 1024 * 1024 {
		return error('recording must be a regular WAV file of at most 512 MiB')
	}
	return decode(os.read_bytes(path)!)
}

// Qualification requires a finalized recording. Truncation and unset lengths
// cannot silently turn missing playback evidence into an accepted recording.
pub fn decode(data []u8) !Recording {
	if data.len < 12 || data.len > 512 * 1024 * 1024
		|| data[..4].bytestr() != 'RIFF' || data[8..12].bytestr() != 'WAVE'
		|| unsigned(data, 4, 4) + 8 != u64(data.len) {
		return error('requires a complete RIFF/WAVE recording')
	}
	mut at := 12
	mut format := false
	mut samples := []i16{}
	mut found := false
	for at < data.len {
		if data.len - at < 8 { return error('truncated WAV chunk header') }
		name := data[at..at + 4].bytestr()
		length := unsigned(data, at + 4, 4)
		at += 8
		if length > u64(data.len - at) || length + (length & 1) > u64(data.len - at) {
			return error('truncated WAV chunk')
		}
		end := at + int(length)
		if name == 'fmt ' {
			if format || found || length < 16 || unsigned(data, at, 2) != 1
				|| unsigned(data, at + 2, 2) != 2 || unsigned(data, at + 4, 4) != 48000
				|| unsigned(data, at + 8, 4) != 192000 || unsigned(data, at + 12, 2) != 4
				|| unsigned(data, at + 14, 2) != 16 {
				return error('requires one PCM S16LE stereo 48000Hz WAV format')
			}
			format = true
		} else if name == 'data' {
			if !format || found || length == 0 || length % 4 != 0 {
				return error('requires one nonempty complete stereo data chunk after its format')
			}
			samples = []i16{cap: int(length) / 2}
			for offset := at; offset < end; offset += 2 {
				samples << i16(u16(unsigned(data, offset, 2)))
			}
			found = true
		}
		at = end + int(length & 1)
	}
	if !found { return error('recording has no audio data') }
	return Recording{ rate: 48000, channels: 2, samples: samples }
}

pub fn (recording &Recording) seconds() f64 {
	return f64(recording.samples.len / 2) / recording.rate
}

fn (recording &Recording) valid() ! {
	if recording.rate != 48000 || recording.channels != 2 || recording.samples.len == 0
		|| recording.samples.len % 2 != 0 {
		return error('invalid stereo 48000Hz recording')
	}
}

fn magnitude(value i16) int {
	return if value < 0 { -int(value) } else { int(value) }
}

fn (recording &Recording) peak(start int, end int) int {
	mut peak := 0
	for sample in recording.samples[start * 2..end * 2] {
		value := magnitude(sample)
		if value > peak { peak = value }
	}
	return peak
}

fn (recording &Recording) channel(start int, end int, channel int) Channel {
	mut total := f64(0)
	mut squares := f64(0)
	mut peak := 0
	mut first := f64(0)
	mut last := f64(0)
	mut crossings := 0
	for frame in start .. end {
		value := int(recording.samples[frame * 2 + channel])
		total += value
		squares += f64(value) * value
		if math.abs(value) > peak { peak = math.abs(value) }
		if frame + 1 < end {
			next := int(recording.samples[(frame + 1) * 2 + channel])
			if value < 0 && next >= 0 {
				crossing := f64(frame - start) + f64(value) / (value - next)
				if crossings == 0 { first = crossing }
				last = crossing
				crossings++
			}
		}
	}
	return Channel{
		peak:      peak
		mean:      total / (end - start)
		rms:       math.sqrt(squares / (end - start))
		frequency: if crossings < 2 {
			f64(0)
		} else {
			(crossings - 1) * f64(recording.rate) / (last - first)
		}
	}
}

fn check_channel(channel Channel, tone Tone, check_mean bool) ! {
	if math.abs(channel.frequency - tone.frequency) > tone.frequency * 0.02 {
		return error('recorded frequency ${channel.frequency}Hz differs from ${tone.frequency}Hz')
	}
	if math.abs(f64(channel.peak) - tone.amplitude) > tone.amplitude * tone.amplitude_slack
		|| math.abs(channel.rms - tone.amplitude / math.sqrt(2)) >
			tone.amplitude / math.sqrt(2) * tone.amplitude_slack
		|| (check_mean && math.abs(channel.mean) > tone.amplitude * 0.02) {
		return error('recorded amplitude peak=${channel.peak} rms=${channel.rms} mean=${channel.mean} differs from ${tone.amplitude}')
	}
}

// Locate all audible runs independently of the expected frequencies, then
// require their exact count/order. A dropout splits a run and cannot disappear.
pub fn (recording &Recording) check_sequence(expected []Tone) ![]Region {
	recording.valid()!
	if expected.len == 0 { return error('a tone sequence must not be empty') }
	for tone in expected {
		if !math.is_finite(tone.frequency) || !math.is_finite(tone.seconds)
			|| !math.is_finite(tone.amplitude) || !math.is_finite(tone.duration_slack)
			|| !math.is_finite(tone.amplitude_slack) || tone.frequency < 200 || tone.frequency > 10000 || tone.seconds < 0.10
			|| tone.amplitude < 1000 || tone.amplitude > 30000 || tone.duration_slack < 0
			|| tone.duration_slack > 0.25 || tone.amplitude_slack < 0 || tone.amplitude_slack > 0.30 {
			return error('invalid expected tone bounds')
		}
	}
	window := recording.rate / 50
	frames := recording.samples.len / 2
	mut spans := [][2]int{}
	mut start := -1
	for at := 0; at < frames; at += window {
		end := if at + window > frames { frames } else { at + window }
		peak := recording.peak(at, end)
		audible := peak > 256
		if !audible && peak > 64 {
			return error('background contains nonquiet output with peak ${peak}')
		}
		if audible && start < 0 { start = at }
		if !audible && start >= 0 {
			spans << [start, at]!
			start = -1
		}
	}
	if start >= 0 { spans << [start, frames]! }
	if spans.len != expected.len {
		return error('recorded ${spans.len} audible runs; expected ${expected.len}')
	}
	mut regions := []Region{}
	for index, span in spans {
		tone := expected[index]
		if math.abs(f64(span[1] - span[0]) / recording.rate - tone.seconds) > tone.duration_slack {
			return error('tone ${index} duration differs from ${tone.seconds}s')
		}
		// Exclude the two windows that can straddle the audible boundary.
		inside := span[0] + window
		end := span[1] - window
		if end <= inside { return error('tone has no complete interior window') }
		left := recording.channel(inside, end, 0)
		right := recording.channel(inside, end, 1)
		check_channel(left, tone, true) or { return error('tone ${index} left: ' + err.msg()) }
		check_channel(right, tone, true) or { return error('tone ${index} right: ' + err.msg()) }
		for at := inside; at + window <= end; at += window {
			for channel in 0 .. 2 {
				check_channel(recording.channel(at, at + window, channel), tone, false) or {
					return error('tone ${index} channel ${channel} window: ' + err.msg())
				}
			}
		}
		regions << Region{ start_frame: span[0], end_frame: span[1], left: left, right: right }
	}
	return regions
}

pub fn (recording &Recording) require_quiet(start_seconds f64, end_seconds f64, max_peak int) ! {
	recording.valid()!
	if !math.is_finite(start_seconds) || !math.is_finite(end_seconds)
		|| start_seconds < 0 || end_seconds <= start_seconds || end_seconds > recording.seconds()
		|| max_peak < 0 || max_peak > 256 {
		return error('invalid quiet interval or threshold')
	}
	start := int(math.ceil(start_seconds * recording.rate))
	end := int(math.floor(end_seconds * recording.rate))
	if end <= start { return error('quiet interval has no complete frames') }
	peak := recording.peak(start, end)
	if peak > max_peak { return error('quiet interval contains peak ${peak}, maximum ${max_peak}') }
}

// Keep a bounded guard around tone boundaries, while requiring an independently
// sized silent interval between real waveform landmarks.
pub fn (recording &Recording) require_gap(before Region, after Region, min_seconds f64, guard_seconds f64) ! {
	recording.valid()!
	if !math.is_finite(min_seconds) || !math.is_finite(guard_seconds) || min_seconds <= 0
		|| guard_seconds < 0 || guard_seconds > 0.10 || before.start_frame < 0
		|| before.end_frame <= before.start_frame || after.end_frame <= after.start_frame
		|| after.end_frame > recording.samples.len / 2 || before.end_frame >= after.start_frame {
		return error('invalid quiet gap bounds')
	}
	start := f64(before.end_frame) / recording.rate + guard_seconds
	end := f64(after.start_frame) / recording.rate - guard_seconds
	if end - start < min_seconds {
		return error('recorded quiet gap is shorter than ${min_seconds}s')
	}
	recording.require_quiet(start, end, 64)!
}
