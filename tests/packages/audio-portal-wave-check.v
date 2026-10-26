// SPDX-License-Identifier: GPL-2.0-or-later
// Production-safe positive and refusal controls for the real-output oracle.
module main

import crypto.sha256
import json2
import math
import os
import tests.packages.audiotest

struct Report {
	format    int    = 1
	result    string = 'PASS'
	controls  []string
	artifacts map[string]string
	regions   []audiotest.Region
}

fn le16(value int) []u8 { return [u8(value), u8(value >> 8)] }

fn le32(value int) []u8 { return [u8(value), u8(value >> 8), u8(value >> 16), u8(value >> 24)] }

fn tone(frequency int, frames int, left int, right int) []u8 {
	mut bytes := []u8{cap: frames * 4}
	for frame in 0 .. frames {
		wave := math.sin(2 * math.pi * frequency * frame / 48000)
		bytes << le16(int(wave * left))
		bytes << le16(int(wave * right))
	}
	return bytes
}

fn wav(pcm []u8) []u8 {
	mut bytes := 'RIFF'.bytes()
	bytes << le32(36 + pcm.len)
	bytes << 'WAVEfmt '.bytes()
	bytes << le32(16)
	bytes << le16(1)
	bytes << le16(2)
	bytes << le32(48000)
	bytes << le32(192000)
	bytes << le16(4)
	bytes << le16(16)
	bytes << 'data'.bytes()
	bytes << le32(pcm.len)
	bytes << pcm
	return bytes
}

fn sequence(frequencies []int, duration int, left int, right int, gap int) []u8 {
	mut pcm := []u8{len: 48000 * 4 * 6 / 5}
	for frequency in frequencies {
		pcm << tone(frequency, duration, left, right)
		pcm << []u8{len: gap * 4}
	}
	return wav(pcm)
}

fn save(work string, name string, bytes []u8, mut artifacts map[string]string) ! {
	os.write_file_array(work + '/' + name + '.wav', bytes)!
	artifacts[name + '.wav'] = sha256.sum(bytes).hex()
}

fn reject_decode(bytes []u8, reason string) ! {
	audiotest.decode(bytes) or {
		if !err.msg().contains(reason) { return error('unexpected parser refusal: ' + err.msg()) }
		return
	}
	return error('parser accepted invalid recording')
}

fn reject_tones(bytes []u8, tones []audiotest.Tone, reason string) ! {
	recording := audiotest.decode(bytes)!
	recording.check_sequence(tones) or {
		if !err.msg().contains(reason) { return error('unexpected waveform refusal: ' + err.msg()) }
		return
	}
	return error('oracle accepted invalid waveform')
}

fn run(work string) ! {
	if os.exists(work) || os.is_link(work) { return error('requires a new output directory') }
	os.mkdir_all(work)!
	mut artifacts := map[string]string{}
	mut controls := []string{}
	tones := [audiotest.Tone{ frequency: 440 }, audiotest.Tone{ frequency: 660 },
		audiotest.Tone{ frequency: 880 }]
	good := sequence([440, 660, 880], 48000, 12000, 12000, 57600)
	save(work, 'positive', good, mut artifacts)!
	recording := audiotest.read(work + '/positive.wav')!
	regions := recording.check_sequence(tones)!
	if recording.channels != 2 || recording.rate != 48000 || regions.len != 3 {
		return error('positive WAV decoding or region count differs')
	}
	recording.require_quiet(0, 1, 64)!
	for index in 1 .. regions.len {
		recording.require_gap(regions[index - 1], regions[index], 1, 0.04)!
	}
	recording.require_quiet(f64(regions.last().end_frame) / recording.rate + 0.04, recording.seconds(), 64)!
	controls << 'complete-stereo-three-tones-and-quiet-gaps'
	mut malformed := good.clone()
	malformed[4] = 0
	reject_decode(malformed, 'complete RIFF/WAVE')!
	controls << 'incorrect-riff-size-refused'
	reject_decode(good[..good.len - 1], 'complete RIFF/WAVE')!
	controls << 'truncated-recording-refused'
	for offset, value in {
		20: u8(3)
		22: u8(1)
		24: u8(1)
		28: u8(1)
		32: u8(2)
		34: u8(8)
	} {
		mut changed := good.clone()
		changed[offset] = value
		reject_decode(changed, 'PCM S16LE stereo 48000Hz')!
	}
	controls << 'format-channels-rate-byte-rate-alignment-bits-refused'
	mut huge_chunk := good.clone()
	for offset in 40 .. 44 { huge_chunk[offset] = 255 }
	reject_decode(huge_chunk, 'truncated WAV chunk')!
	controls << 'oversized-data-chunk-refused'
	mut unset_length := good.clone()
	for offset in 40 .. 44 { unset_length[offset] = 0 }
	reject_decode(unset_length, 'nonempty complete stereo data')!
	controls << 'unfinalized-data-length-refused'
	for name, bytes in {
		'silent-right':    sequence([440, 660, 880], 48000, 12000, 0, 57600)
		'silent-left':     sequence([440, 660, 880], 48000, 0, 12000, 57600)
		'wrong-frequency': sequence([440, 700, 880], 48000, 12000, 12000, 57600)
		'wrong-order':     sequence([880, 660, 440], 48000, 12000, 12000, 57600)
	} {
		save(work, name, bytes, mut artifacts)!
		reject_tones(bytes, tones, 'frequency')!
		controls << name + '-refused'
	}
	for amplitude in [5000, 22000] {
		bytes := sequence([440, 660, 880], 48000, amplitude, amplitude, 57600)
		save(work, 'wrong-amplitude-' + amplitude.str(), bytes, mut artifacts)!
		reject_tones(bytes, tones, 'amplitude')!
		controls << 'amplitude-' + amplitude.str() + '-refused'
	}
	short := sequence([440, 660, 880], 24000, 12000, 12000, 57600)
	reject_tones(short, tones, 'duration')!
	controls << 'short-tones-refused'
	extra := sequence([440, 660, 880, 440], 48000, 12000, 12000, 57600)
	reject_tones(extra, tones, 'audible runs')!
	controls << 'extra-tone-refused'
	mut dropout := good.clone()
	for offset in 44 + (57600 + 19200) * 4 .. 44 + (57600 + 24000) * 4 { dropout[offset] = 0 }
	reject_tones(dropout, tones, 'audible runs')!
	controls << 'interior-dropout-refused'
	mut burst := good.clone()
	wrong := tone(660, 960, 12000, 12000)
	for index, byte in wrong { burst[44 + (57600 + 19200) * 4 + index] = byte }
	reject_tones(burst, tones, 'frequency')!
	controls << 'single-window-wrong-frequency-refused'
	mut background := good.clone()
	for frame in 9600 .. 14400 {
		background[44 + frame * 4] = 80
		background[44 + frame * 4 + 2] = 80
	}
	reject_tones(background, tones, 'background contains nonquiet output')!
	controls << 'low-amplitude-background-refused'
	mut contaminated := good.clone()
	// A quiet interval before the first tone must fail independently of tone markers.
	for offset in 44 + 9600 * 4 .. 44 + 14400 * 4 { contaminated[offset] = 80 }
	noisy := audiotest.decode(contaminated)!
	noisy.require_quiet(0, 1, 64) or {
		if !err.msg().contains('quiet interval contains peak') { return err }
		controls << 'contaminated-quiet-interval-refused'
	}
	if controls.last() != 'contaminated-quiet-interval-refused' {
		return error('quiet interval accepted noise')
	}
	// The entire recording must contain enough real silence between landmarks.
	too_short := audiotest.decode(sequence([440, 660, 880], 48000, 12000, 12000, 9600))!
	short_regions := too_short.check_sequence(tones)!
	too_short.require_gap(short_regions[0], short_regions[1], 1, 0.04) or {
		if !err.msg().contains('shorter than') { return err }
		controls << 'insufficient-quiet-gap-refused'
	}
	if controls.last() != 'insufficient-quiet-gap-refused' {
		return error('short quiet gap accepted')
	}
	os.write_file(work + '/result.json', json2.encode(Report{ controls: controls, artifacts: artifacts, regions: regions }) + '\n')!
	println('AUDIO PORTAL WAVE ORACLE PASS controls=' + controls.len.str())
}

fn main() {
	if os.args.len != 2 || !os.args[1].starts_with('--out=') || os.args[1].all_after_first('=') == '' {
		eprintln('use --out=NEW_EXTERNAL_DIRECTORY')
		exit(1)
	}
	run(os.abs_path(os.args[1].all_after_first('='))) or {
		eprintln(err)
		exit(1)
	}
}
