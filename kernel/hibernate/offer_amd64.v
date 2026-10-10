// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Whether an image can be kept at all, and what there is to say about the
// last one: for /sys/power.
module hibernate

import block.fence
import devcore
import lib

// Why hibernation is not offered, or '' when it is: a device was named, was
// found when the disks came up, and is this system's to write to.
pub fn unavailable_reason() string {
	if device_name().len == 0 {
		return 'no device was named for the image (vinix.hibernate=)'
	}
	if !hib_boot_looked {
		return 'the device named for the image was never looked for'
	}
	if hib_device == unsafe { nil } || !hib_device_ours {
		return hib_device_problem
	}
	if hib_waiting.len != 0 {
		return 'an image is still waiting on a device, and this boot did not go back into it'
	}
	return ''
}

fn line(mut text lib.Text, name string, value u64) {
	text.add(name)
	text.add(': ')
	text.add_unsigned(value)
	text.add_byte(`\n`)
}

// What /sys/power/hibernate says after its first line.
pub fn report(mut text lib.Text) {
	text.add('device: ')
	text.add(if device_name().len == 0 { 'none' } else { device_name() })
	text.add_byte(`\n`)
	line(mut text, 'device bytes', hib_device_bytes)
	text.add('boot: ')
	if !hib_boot_looked {
		text.add('no device to look at')
	} else if !hib_boot_found {
		text.add('no image')
	} else if hib_boot_verdict.len == 0 {
		text.add('no image')
	} else {
		text.add('image not resumed: ')
		text.add(hib_boot_verdict)
	}
	text.add_byte(`\n`)
	text.add('waiting: ')
	text.add(if hib_waiting.len == 0 { 'none' } else { hib_waiting })
	text.add_byte(`\n`)
	line(mut text, 'images written', hib_sequence)
	line(mut text, 'resumes', hib_resumes)
	line(mut text, 'image pages', hib_last_pages)
	line(mut text, 'image bytes', hib_last_bytes)
	line(mut text, 'copy ms', hib_last_copy_ns / devcore.millisecond)
	line(mut text, 'write ms', hib_last_write_ns / devcore.millisecond)
	line(mut text, 'load ms', hib_loader.load_time / devcore.millisecond)
	line(mut text, 'loader uptime ms', hib_loader.loader_uptime / devcore.millisecond)
	line(mut text, 'pages read in place', hib_loader.direct)
	line(mut text, 'pages moved into place', hib_loader.relocated)
	line(mut text, 'writes before the image was looked for', hib_loader.writes_before)
	held, refused := fence.held()
	line(mut text, 'writes held', held)
	line(mut text, 'writes refused', refused)
	line(mut text, 'disk writes since boot', fence.writes())
}
