// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// drivers-sleep: a sound card and an IDE disk through every kind of sleep.
//
// The machine has an HD Audio controller with an output codec, whose sound
// QEMU records, and an IDE controller with a disk on it. A thread of this
// program plays a square wave the whole time, at a height the main thread
// changes after each sleep, so that the recording holds a height only if the
// card played after the sleep that height stands for:
//
//	6000    before any sleep
//	12000   after a rehearsal, which suspends and resumes every device
//	18000   after a suspend to idle
//	24000   after a suspend to RAM, which the machine must offer: both
//	        drivers used to keep every machine that has them from one
//
// The tone is playing when the machine goes down each time: the driver has to
// stop a running stream and start it again, and a program blocked on a full
// buffer has to be let go on. The controller checks the recording, and the
// disk's bytes, once the machine has ended.
//
// The disk is written before each sleep and read back after it, and written
// again; `write_pattern` reads back what it wrote.
@[has_globals]
module main

import os
import sync.stdatomic

#include <sys/ioctl.h>

fn C.ioctl(fd i32, request u64, args ...voidptr) i32

const sound_device = '/dev/dsp'
const ide_disk = '/dev/ata0'

// OSS: sample format, channels and rate, and "play out what is queued".
const dsp_setfmt = u64(0xc0045005)
const dsp_channels = u64(0xc0045006)
const dsp_speed = u64(0xc0045002)
const dsp_sync = u64(0x5001)
const format_s16_le = i32(0x10)

const tone_rate = 48000
// A tenth of a second of tone at a time, and a hundred cycles a second.
const tone_frames = tone_rate / 10
const tone_half_period = tone_rate / 200

__global (
	tone_level  = u64(0)
	tone_stop   = u64(0)
	tone_chunks = u64(0)
	tone_failed = u64(0)
)

// Plays the tone until told to stop. Paced a little faster than the card
// plays, so that the card never runs dry and a change of height is heard
// within a few tenths of a second.
fn play_tone(fd int) {
	mut samples := []i16{len: tone_frames * 2}
	mut frame := 0
	for stdatomic.load_u64(&tone_stop) == 0 {
		level := i16(stdatomic.load_u64(&tone_level))
		for i in 0 .. tone_frames {
			value := if (frame / tone_half_period) % 2 == 0 { level } else { -level }
			samples[2 * i] = value
			samples[2 * i + 1] = value
			frame++
		}
		if C.write(fd, samples.data, usize(samples.len * 2)) != samples.len * 2 {
			stdatomic.add_u64(&tone_failed, 1)
		}
		stdatomic.add_u64(&tone_chunks, 1)
		sleep_ms(90)
	}
}

// Sets the height and lets it play for a second and a half. The thread must
// go on handing chunks to the card: one stuck in a write to a stream that
// never started again does not.
fn tone_at(mut t Test, level u64, what string) {
	stdatomic.store_u64(&tone_level, level)
	before := stdatomic.load_u64(&tone_chunks)
	sleep_ms(1500)
	played := stdatomic.load_u64(&tone_chunks) - before
	t.check(played >= 8, '${what}: the player handed over ${played} chunks in a second and a half')
	t.check(stdatomic.load_u64(&tone_failed) == 0, '${what}: ${stdatomic.load_u64(&tone_failed)} writes to the sound card failed')
}

// The 64 KiB written at `megabyte` MiB with `seed` must still be there.
fn disk_still_has(mut t Test, disk string, megabyte int, seed u8, what string) {
	fd := C.open(&char(disk.str), C.O_RDONLY)
	if !t.check(fd >= 0, '${what}: ${disk} cannot be opened') {
		return
	}
	defer {
		C.close(fd)
	}
	expected := pattern_bytes(seed, 65536)
	mut found := []u8{len: 65536}
	count := C.pread(fd, found.data, usize(found.len), i64(megabyte) << 20)
	t.check(count == found.len && found == expected, '${what}: the disk no longer holds what was written at ${megabyte} MiB')
}

fn disk_write(mut t Test, disk string, megabyte int, seed u8, what string) {
	write_pattern(disk, i64(megabyte) << 20, seed, 65536) or {
		t.check(false, '${what}: writing the disk at ${megabyte} MiB: ${err.msg()}')
	}
}

fn bound_devices(driver string) int {
	entries := list_dir('/sys/bus/pci/drivers/${driver}') or { return 0 }
	return entries.filter(os.is_link('/sys/bus/pci/drivers/${driver}/${it}')).len
}

// How many sleeps the device bound to `driver` has spent in D3hot, as /sys
// gives it: a device with no power management capability spends none there.
fn sleeps_in_d3(driver string) string {
	entries := list_dir('/sys/bus/pci/drivers/${driver}') or { return '?' }
	for entry in entries {
		if os.is_link('/sys/bus/pci/drivers/${driver}/${entry}') {
			return read_word('/sys/bus/pci/drivers/${driver}/${entry}/power/d3_count')
		}
	}
	return '?'
}

fn scenario_drivers_sleep(mut t Test) {
	t.check(bound_devices('hda') == 1, '${bound_devices('hda')} devices are bound to hda, not one')
	t.check(bound_devices('ata') == 1, '${bound_devices('ata')} devices are bound to ata, not one')
	disk_write(mut t, ide_disk, 1, 0x21, 'before any sleep')

	fd := C.open(&char(sound_device.str), C.O_WRONLY)
	if !t.check(fd >= 0, '${sound_device} cannot be opened') {
		return
	}
	mut format := format_s16_le
	mut channels := i32(2)
	mut rate := i32(tone_rate)
	t.check(C.ioctl(fd, dsp_setfmt, voidptr(&format)) == 0 && format == format_s16_le, 'the card does not take 16-bit samples')
	t.check(C.ioctl(fd, dsp_channels, voidptr(&channels)) == 0 && channels == 2, 'the card does not take two channels')
	t.check(C.ioctl(fd, dsp_speed, voidptr(&rate)) == 0 && rate == tone_rate, 'the card does not take ${tone_rate} frames a second (it said ${rate})')

	stdatomic.store_u64(&tone_level, 6000)
	spawn play_tone(fd)
	tone_at(mut t, 6000, 'before any sleep')

	// A rehearsal: every driver's suspend and resume, with the tone playing.
	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', '1000') or { t.check(false, 'pm_test_delay_ms: ${err.msg()}') }
	mut took := sleep_now(mut t, 'freeze')
	t.check(stat_word('success') == '1', 'the rehearsal failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}"')
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err.msg()}') }
	tone_at(mut t, 12000, 'after the rehearsal')
	disk_still_has(mut t, ide_disk, 1, 0x21, 'after the rehearsal')
	disk_write(mut t, ide_disk, 2, 0x42, 'after the rehearsal')
	t.info('rehearsal: ${took} ms')

	// A suspend to idle, ended by the alarm.
	write_text('/sys/class/rtc/rtc0/wakealarm', '+2') or { t.check(false, 'wakealarm: ${err.msg()}') }
	took = sleep_now(mut t, 'freeze')
	t.check(stat_word('success') == '2' && stat_word('last_wake') == 'alarm', 'the suspend to idle: ${stat_word('success')} successes, woken by ${stat_word('last_wake')}')
	tone_at(mut t, 18000, 'after the suspend to idle')
	disk_still_has(mut t, ide_disk, 2, 0x42, 'after the suspend to idle')
	disk_write(mut t, ide_disk, 3, 0x63, 'after the suspend to idle')
	t.info('suspend to idle: ${took} ms')

	// A suspend to RAM: the controllers lose their power, and the machine
	// must be willing, which it was not while either driver could not bring
	// its device back.
	offered := read_word('/sys/power/mem_sleep')
	if !t.check(offered.contains('deep'), 'mem_sleep does not offer deep: "${offered}" (${read_word('/sys/power/deep_sleep').all_before('\n')})') {
		return
	}
	write_text('/sys/power/mem_sleep', 'deep') or { t.check(false, 'selecting deep: ${err.msg()}') }
	write_text('/sys/class/rtc/rtc0/wakealarm', '+4') or { t.check(false, 'wakealarm: ${err.msg()}') }
	took = sleep_now(mut t, 'mem')
	t.check(stat_word('success') == '3', 'the suspend to RAM failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}", ${stat_word('last_failed_reason')}')
	t.check(stat_word('last_depth') == 'deep', 'the last sleep was "${stat_word('last_depth')}", not deep')
	tone_at(mut t, 24000, 'after the suspend to RAM')
	disk_still_has(mut t, ide_disk, 3, 0x63, 'after the suspend to RAM')
	disk_write(mut t, ide_disk, 4, 0x7c, 'after the suspend to RAM')
	t.info('suspend to RAM: ${took} ms')
	t.check(stat_word('fail') == '0', '${stat_word('fail')} sleeps failed')

	// Let the last of the tone out before the card is closed.
	stdatomic.store_u64(&tone_stop, 1)
	sleep_ms(300)
	C.ioctl(fd, dsp_sync, unsafe { nil })
	C.close(fd)
	t.info('${stdatomic.load_u64(&tone_chunks)} tenths of a second of tone handed to the card')
	t.info('sleeps spent in D3hot: the sound card ${sleeps_in_d3('hda')}, the IDE controller ${sleeps_in_d3('ata')}, the SATA controller ${sleeps_in_d3('ahci')}, the network card ${sleeps_in_d3('e1000')} (? where the machine has none)')
}

// nvme-sleep: an NVMe disk through the same three sleeps. A release kernel
// does not start the NVMe driver, so this is for a kernel built with
// PROD=false. The controller is told to shut down before each sleep and set
// up again from nothing after it: what was written before must be there,
// and a new write must reach the disk.
fn scenario_nvme_sleep(mut t Test) {
	disk := '/dev/nvme0n0'
	if !t.check(bound_devices('nvme') == 1, '${bound_devices('nvme')} devices are bound to nvme, not one') {
		return
	}
	disk_write(mut t, disk, 1, 0x21, 'before any sleep')

	write_text('/sys/power/pm_test', 'devices') or { t.check(false, 'pm_test: ${err.msg()}') }
	write_text('/sys/power/pm_test_delay_ms', '500') or { t.check(false, 'pm_test_delay_ms: ${err.msg()}') }
	mut took := sleep_now(mut t, 'freeze')
	t.check(stat_word('success') == '1', 'the rehearsal failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}"')
	write_text('/sys/power/pm_test', 'none') or { t.check(false, 'pm_test: ${err.msg()}') }
	disk_still_has(mut t, disk, 1, 0x21, 'after the rehearsal')
	disk_write(mut t, disk, 2, 0x42, 'after the rehearsal')
	t.info('rehearsal: ${took} ms')

	write_text('/sys/class/rtc/rtc0/wakealarm', '+2') or { t.check(false, 'wakealarm: ${err.msg()}') }
	took = sleep_now(mut t, 'freeze')
	t.check(stat_word('success') == '2' && stat_word('last_wake') == 'alarm', 'the suspend to idle: ${stat_word('success')} successes, woken by ${stat_word('last_wake')}')
	disk_still_has(mut t, disk, 2, 0x42, 'after the suspend to idle')
	disk_write(mut t, disk, 3, 0x63, 'after the suspend to idle')
	t.info('suspend to idle: ${took} ms')

	offered := read_word('/sys/power/mem_sleep')
	if !t.check(offered.contains('deep'), 'mem_sleep does not offer deep: "${offered}" (${read_word('/sys/power/deep_sleep').all_before('\n')})') {
		return
	}
	write_text('/sys/power/mem_sleep', 'deep') or { t.check(false, 'selecting deep: ${err.msg()}') }
	write_text('/sys/class/rtc/rtc0/wakealarm', '+4') or { t.check(false, 'wakealarm: ${err.msg()}') }
	took = sleep_now(mut t, 'mem')
	t.check(stat_word('success') == '3', 'the suspend to RAM failed: step "${stat_word('last_failed_step')}", device "${stat_word('last_failed_dev')}", ${stat_word('last_failed_reason')}')
	t.check(stat_word('last_depth') == 'deep', 'the last sleep was "${stat_word('last_depth')}", not deep')
	disk_still_has(mut t, disk, 3, 0x63, 'after the suspend to RAM')
	disk_write(mut t, disk, 4, 0x7c, 'after the suspend to RAM')
	t.check(stat_word('fail') == '0', '${stat_word('fail')} sleeps failed')
	// QEMU's controller has a power management capability: it was switched
	// nearly off each time, and the checks above are of a disk that came back
	// from that.
	t.check(sleeps_in_d3('nvme') == '3', 'the NVMe controller spent ${sleeps_in_d3('nvme')} of the three sleeps in D3hot')
}
