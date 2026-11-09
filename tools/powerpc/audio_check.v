// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn audio_word(data []u8, at int) int { return int(data[at]) | int(data[at + 1]) << 8 }

fn validate_audio(data []u8) ! {
	if data.len < 44 || data[..4].bytestr() != 'RIFF' || data[8..12].bytestr() != 'WAVE'
		|| pcap_word(data, 4) != u32(data.len - 8) { return error('Invalid or unflushed WAV recording') }
	mut at := 12
	mut pcm := []u8{}
	mut format := false
	for at + 8 <= data.len {
		size := pcap_word(data, at + 4)
		if size > u32(data.len - at - 8) { return error('Truncated WAV chunk') }
		if data[at..at + 4].bytestr() == 'fmt ' {
			if size < 16 { return error('Truncated WAV format') }
			format = audio_word(data, at + 8) == 1 && audio_word(data, at + 10) == 2
				&& pcap_word(data, at + 12) == 48000 && audio_word(data, at + 22) == 16
		}
		if data[at..at + 4].bytestr() == 'data' { pcm = data[at + 8..at + 8 + int(size)] }
		at += 8 + int(size) + int(size & 1)
	}
	if !format || pcm.len % 4 != 0 { return error('Expected stereo 48000 Hz 16-bit PCM') }
	mut active := [2]int{}
	mut transitions := [2]int{}
	mut previous := [2]int{}
	mut previous_frame := [2]int{init: -2}
	mut run_length := [2]int{}
	mut exact_runs := [2]int{}
	for frame in 0 .. pcm.len / 4 {
		for channel in 0 .. 2 {
			value := int(i16(audio_word(pcm, frame * 4 + channel * 2)))
			if value == 0 { continue }
			magnitude := if value < 0 { -value } else { value }
			if magnitude < (if channel == 0 { 3000 } else { 1500 }) || magnitude > (if channel == 0 { 4500 } else { 2250 }) {
				return error('Unexpected PCM amplitude/channel order: ${channel}=${value}')
			}
			active[channel]++
			sign := if value > 0 { 1 } else { -1 }
			if previous_frame[channel] == frame - 1 {
				if sign != previous[channel] {
					transitions[channel]++
					if run_length[channel] == (if channel == 0 { 24 } else { 48 }) { exact_runs[channel]++ }
					run_length[channel] = 0
				}
			} else { run_length[channel] = 0 }
			run_length[channel]++
			previous[channel] = sign
			previous_frame[channel] = frame
		}
	}
	if active[0] != 96000 || active[1] != active[0]
		|| exact_runs[0] < 3996 || exact_runs[1] < 1996 {
		return error('Incomplete USB audio: frames ${active}, transitions ${transitions}, correctly timed runs ${exact_runs}')
	}
	println('PASS recorded USB audio: two seconds, stereo channel order, PCM endian, 1000/500 Hz timing')
}
