// SPDX-License-Identifier: GPL-2.0-or-later
// Signed native payload. Every check remains active in production builds.
module main

import json2
import math
import os
import tools.packages.audiopcm
import tools.packages.appsdk

#include <fcntl.h>
#include <unistd.h>

fn C.getuid() int
fn C.geteuid() int
fn C.getgid() i32
fn C.getgroups(int, &u32) int
fn C.getpid() int
fn C.open(&char, int, ...int) int
fn C.close(int) int
fn C.usleep(u32) int

struct Ready {
	pid        int
	worker     int
	socket     string
	device     u64
	inode      u64
	generation u64
	manifest   string
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn mark(name string, text string) ! {
	os.write_file(os.getenv('HOME') + '/' + name, text)!
}

fn gate(name string) ! {
	for _ in 0 .. 600 {
		text := os.read_file(os.getenv('HOME') + '/' + name) or { '' }
		if text == 'go\n' { return }
		C.usleep(100_000)
	}
	return error('private control gate timed out: ${name}')
}

fn announce(run string) ! {
	value := Ready{
		pid:        C.getpid()
		worker:     os.getenv('VINIX_AUDIO_WORKER').int()
		socket:     os.getenv('VINIX_AUDIO_SOCKET')
		device:     os.getenv('VINIX_AUDIO_DEVICE').u64()
		inode:      os.getenv('VINIX_AUDIO_INODE').u64()
		generation: os.getenv('VINIX_AUDIO_GENERATION').u64()
		manifest:   os.getenv('VINIX_AUDIO_MANIFEST')
	}
	mark(run + '.ready', json2.encode(value))!
}

fn tone(mut client audiopcm.Client, frequency int) ! {
	mut bytes := []u8{len: 4096}
	mut frame := 0
	for frame < 48000 {
		frames := if 48000 - frame < 1024 { 48000 - frame } else { 1024 }
		for index in 0 .. frames {
			sample := i16(math.sin(2 * math.pi * f64(frequency) * f64(frame + index) / 48000) * 12000)
			bits := u16(sample)
			for channel in 0 .. 2 {
				bytes[index * 4 + channel * 2] = u8(bits)
				bytes[index * 4 + channel * 2 + 1] = u8(bits >> 8)
			}
		}
		client.write(bytes[..frames * 4])!
		frame += frames
	}
	client.drain()!
}

fn refused() ! {
	mut client := audiopcm.connect() or { return }
	client.close()
	return error('unauthorized or unavailable audio connection succeeded')
}

fn check() ! {
	require(os.args.len >= 3, 'tone payload needs mode and run identifier')!
	mode := os.args[1]
	run := os.args[2]
	require(run.len > 0 && run.bytes().all(it >= `a` && it <= `z`), 'invalid run identifier')!
	mut context := appsdk.load()!
	defer { context.close() }
	require(C.getuid() == 1000 && C.geteuid() == 1000 && C.getgid() == 1000, 'isolated payload identity changed')!
	require(C.getgroups(0, unsafe { nil }) == 0, 'isolated payload retained supplementary groups')!
	require(context.id in ['tone', 'noaudio'] && context.version == '1.0.0' && context.kind == 'native'
		&& context.repository == 'audio-fixture' && context.sequence == 1 && context.public_key.len == 64
		&& context.generation > 0 && context.data_directory == os.getenv('HOME'), 'signed application context changed')!
	require(context.permissions == if context.id == 'tone' { ['audio'] } else { []string{} }, 'unexpected signed permission set')!
	fd := C.open(c'/dev/dsp', C.O_WRONLY)
	if fd >= 0 {
		C.close(fd)
		return error('isolated payload opened /dev/dsp directly')
	}
	println('AUDIO PAYLOAD ${run} uid=1000 groups=0 signed-context direct-device-refused PASS')
	if mode == 'refuse' {
		require(context.id == 'noaudio' && os.getenv('VINIX_AUDIO_SOCKET') == '', 'missing audio permission retained endpoint')!
		refused()!
	} else if mode == 'forged' {
		require(context.id == 'tone', 'forged control needs signed audio grant')!
		os.setenv('VINIX_AUDIO_INODE', (os.getenv('VINIX_AUDIO_INODE').u64() + 1).str(), true)
		refused()!
	} else if mode in ['service', 'changed'] {
		announce(run)!
		gate(run + '.go')!
		refused()!
	} else {
		mut client := audiopcm.connect()!
		defer { client.close() }
		if mode == 'sequence' {
			for index, frequency in [440, 660, 880] {
				if index != 0 { C.usleep(1_500_000) }
				tone(mut client, frequency)!
			}
		} else if mode in ['tone', 'hold'] {
			require(os.args.len == 4 && os.args[3].int() in [440, 660, 880], 'unsupported tone')!
			tone(mut client, os.args[3].int())!
			if mode == 'hold' {
				announce(run)!
				gate(run + '.go')!
			}
		} else if mode == 'seat' {
			tone(mut client, 440)!
			announce(run)!
			gate(run + '.inactive')!
			// The held connection must reject its first frame after a real seat change.
			mut rejected := false
			mut inactive := []u8{len: 4096}
			for frame in 0 .. 1024 {
				bits := u16(i16(math.sin(2 * math.pi * 660 * f64(frame) / 48000) * 12000))
				for channel in 0 .. 2 {
					inactive[frame * 4 + channel * 2] = u8(bits)
					inactive[frame * 4 + channel * 2 + 1] = u8(bits >> 8)
				}
			}
			client.write(inactive) or { rejected = true }
			require(rejected, 'inactive seat accepted a PCM chunk')!
			mark(run + '.inactive-refused', 'PASS\n')!
			gate(run + '.active')!
			mut resumed := audiopcm.connect()!
			defer { resumed.close() }
			tone(mut resumed, 880)!
		} else {
			return error('unsupported mode: ${mode}')
		}
	}
	mark(run + '.done', 'PASS\n')!
	println('AUDIO PAYLOAD ${run} ${mode} PASS')
}

fn main() {
	check() or {
		eprintln('AUDIO PAYLOAD FAIL: ${err}')
		exit(89)
	}
}
