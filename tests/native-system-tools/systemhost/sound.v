// SPDX-License-Identifier: GPL-2.0-or-later
module systemhost

import guesthost
import hosttest
import math
import os

pub struct Wav {
pub:
	rate     int
	channels int
	samples  []int
}

fn wav_unsigned(data []u8, at int, width int) u32 {
	mut value := u32(0)
	for index in 0 .. width {
		if at + index < data.len { value |= u32(data[at + index]) << (index * 8) }
	}
	return value
}

pub fn read_wav(data []u8) !Wav {
	if data.len < 12 || data[..4].bytestr() != 'RIFF' || data[8..12].bytestr() != 'WAVE' {
		return error('not a WAV file')
	}
	mut offset := i64(12)
	mut rate := 0
	mut channels := 0
	mut bits := 0
	for offset + 8 <= data.len {
		at := int(offset)
		kind := data[at..at + 4].bytestr()
		mut size := i64(wav_unsigned(data, at + 4, 4))
		body := at + 8
		if kind == 'fmt ' {
			channels = int(wav_unsigned(data, body + 2, 2))
			rate = int(wav_unsigned(data, body + 4, 4))
			bits = int(wav_unsigned(data, body + 14, 2))
		} else if kind == 'data' {
			if size == 0 || i64(body) + size > data.len { size = data.len - body }
			if bits != 16 { return error('unexpected ' + bits.str() + '-bit WAV') }
			if channels <= 0 || rate < 200 { return error('invalid WAV rate or channels') }
			frame := 2 * channels
			length := int(size - size % frame)
			mut samples := []int{cap: length / frame}
			for index := 0; index < length; index += frame {
				samples << int(i16(wav_unsigned(data, body + index, 2)))
			}
			return Wav{rate, channels, samples}
		}
		offset = i64(body) + size + (size & 1)
	}
	return error('WAV has no data chunk')
}

pub fn window_frequency(segment []int, rate int) f64 {
	mut first := f64(0)
	mut last := f64(0)
	mut count := 0
	for index in 0 .. if segment.len > 0 { segment.len - 1 } else { 0 } {
		a := segment[index]
		b := segment[index + 1]
		if a < 0 && b >= 0 {
			crossing := index + f64(a) / (a - b)
			if count == 0 { first = crossing }
			last = crossing
			count++
		}
	}
	return if count < 2 { f64(0) } else { (count - 1) * f64(rate) / (last - first) }
}

struct ToneRun {
	label int
mut:
	count int
}

pub fn check_recording(wav Wav) []string {
	println('==> Recorded ' + (f64(wav.samples.len) / wav.rate).str() + ' s at ' + wav.rate.str() + ' Hz, ' + wav.channels.str() + ' channels')
	quiet := wav.rate / 200
	mut first := -1
	mut last := -1
	mut dropouts := 0
	for start := 0; start + quiet <= wav.samples.len; start += quiet {
		mut peak := 0
		for sample in wav.samples[start..start + quiet] {
			if math.abs(sample) > peak { peak = math.abs(sample) }
		}
		if peak > 1000 {
			if first < 0 {
				first = start
			} else if last >= 0 && start - last > quiet {
				dropouts++
			}
			last = start
		}
	}
	if first < 0 { return ['the recording is silent'] }
	mut problems := []string{}
	if dropouts > 0 { problems << dropouts.str() + ' dropouts inside the sound' }
	window := wav.rate / 40
	mut runs := []ToneRun{}
	for start := first; start + window <= last + quiet; start += window {
		hz := window_frequency(wav.samples[start..start + window], wav.rate)
		mut label := 0
		for frequency in [440, 660, 880] {
			if math.abs(hz - frequency) < frequency * 0.03 {
				label = frequency
				break
			}
		}
		if runs.len > 0 && runs.last().label == label {
			runs[runs.len - 1].count++
		} else {
			runs << ToneRun{label, 1}
		}
	}
	mut tones := []ToneRun{}
	mut stray := 0
	for run in runs {
		if run.label > 0 {
			tones << run
			println('    ' + run.label.str() + ' Hz for ' + (f64(run.count * window) / wav.rate).str() + ' s')
		} else {
			stray += run.count
		}
	}
	if stray > 3 { problems << stray.str() + ' windows matched no tone' }
	if tones.map(it.label) != [440, 660, 880] {
		problems << 'heard unexpected tone order: ' + tones.map(it.label).str()
	} else {
		lengths := [f64(2), 0.45, 0.5]
		slacks := [f64(0.06), 0.25, 0.06]
		for index, tone in tones {
			length := f64(tone.count * window) / wav.rate
			if math.abs(length - lengths[index]) > slacks[index] {
				problems << tone.label.str() + ' Hz lasted ' + length.str() + ' s, expected ' + lengths[index].str()
			}
		}
	}
	return problems
}

pub fn sound_markers() []string {
	return ['virtio-snd: stream 0', 'SOUND TEST PASS: OSS parameters',
		'SOUND TEST PASS: the device has one owner at a time',
		'SOUND TEST PASS: handled signals do not interrupt writes',
		'SOUND TEST PASS: writes are paced by playback',
		'SOUND TEST PASS: a blocked writer can be killed', 'SOUND TEST PASS: reopened at another rate',
		'VINIX SOUND TEST: GUEST DONE']
}

fn sound(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--initramfs', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
		hosttest.Option{ name: '--timeout', value: true },
		hosttest.Option{ name: '--root', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true }, hosttest.Option{ name: '--no-build' },
		hosttest.Option{ name: '--build-fixture' }, hosttest.Option{ name: '--build-only' }], [],
		'Usage: run_vm --init ELF --initramfs TAR --state-dir DIR [--timeout 300] [--root DIR] [--build-only]')!
	build := options.has('--build-fixture')
	if !build { required(options, ['--init', '--initramfs', '--state-dir'])! }
	seconds := if build { env_timeout(options, 300)! } else { positive(options, '--timeout', 300)! }
	state := state_dir(options, 'vinix-sound-')!
	defer { if !options.has('--state-dir') && os.getenv('VINIX_SOUND_KEEP') != '1' {
		private_cleanup(state, options)
	} }
	runner := resolve(options.value('--root', os.getenv_opt('VINIX_SOUND_ROOT') or { root() }))!
	init := if build { state + '/init' } else { resolve(options.value('--init', ''))! }
	if build {
		run([...compiler('aarch64'), '-static', '-O2', '-fno-stack-protector', '-Wall', '-Wextra',
			'-Werror', root() + '/tests/sound/test.c', '-o', init])!
	}
	archive := if build {
		archive_root('', state, ['root', 'sbin'])!
	} else {
		resolve(options.value('--initramfs', ''))!
	}
	kernel := snapshot(state, options.value('--kernel-dir', os.getenv_opt('VINIX_KERNEL_DIR') or { runner + '/kernel' }), 'aarch64')!
	configured := guesthost.serial_arm_launch(init, archive, state, kernel, runner, 2048, '')!
	mut argv := configured.command.clone()
	argv << ['-audiodev', 'wav,id=vinix-audio,path=' + state + '/sound.wav', '-device',
		'virtio-sound-device,audiodev=vinix-audio,streams=1']
	receipt(state, guesthost.Launch{argv, configured.env}, kernel, init, archive, seconds)!
	if options.has('--build-only') {
		println('Prepared sound: ' + state)
		return 0
	}
	println('==> Starting AArch64 QEMU sound boot')
	failures := ['VINIX SOUND TEST: FAIL', 'SOUND TEST FAIL line', 'FATAL EXCEPTION', 'KERNEL PANIC']
	result := guesthost.boot_session(argv, configured.env, state, guesthost.SessionPolicy{ pass: 'VINIX SOUND TEST: GUEST DONE', failures: failures, settle: 10, lookback: 65536, monitor_at_marker: true }, seconds, true)!
	mut problems := []string{}
	for marker in sound_markers() {
		if !result.text.contains(marker) { problems << 'missing guest result: ' + marker }
	}
	for marker in failures {
		if result.text.contains(marker) { problems << 'guest failure: ' + marker }
	}
	if problems.len == 0 {
		bytes := os.read_bytes(state + '/sound.wav') or { return error('cannot read the recording: ' + err.msg()) }
		wav := read_wav(bytes) or { return error('cannot read the recording: ' + err.msg()) }
		problems = check_recording(wav)
	}
	for problem in problems { eprintln('ERROR: ' + problem) }
	if problems.len > 0 { return 1 }
	println('==> AArch64 QEMU sound regression passed')
	return 0
}
