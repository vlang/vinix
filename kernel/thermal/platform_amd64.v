// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the architecture itself brings to thermal management: on x86-64, the
// temperature sensors and energy counters inside the processor.
//
// /sys/class/thermal/x86_probe says what was looked for and what was found,
// for the machine on which nothing shows up. Its first lines read, each time
// the file is read, a register every CPU has and two that none has, through
// msr.read_safe(): the proof that asking after a register that is not there
// costs an answer and not the machine. Two, because QEMU's emulated CPU
// answers 0 for an index it has never heard of where a real one faults; a
// reserved index in the x2APIC's range faults on both.
module thermal

import fs
import lib
import x86.msr

// IA32_APIC_BASE, which every CPU this kernel runs on has.
const msr_apic_base = u32(0x1b)

// An index no vendor has assigned.
const msr_unassigned = u32(0x12345678)

// 0x800 to 0x8ff are the x2APIC's registers, and 0x804 is none of them: #GP
// in x2APIC mode because it is reserved, and outside it because the whole
// range is.
const msr_x2apic_reserved = u32(0x804)

fn platform_start() {
	fs.sysfs_attribute('class/thermal/x86_probe', 0o444, show_x86_probe, unsafe { nil },
		unsafe { nil })
}

// Whether the polling thread has anything of the platform's to look after.
fn platform_polls() bool {
	return false
}

fn platform_poll() {
}

// The power the processor package drew over the last polling interval, in
// milliwatts. None when no counter says.
pub fn package_power_mw() ?u64 {
	return none
}

fn show_msr(mut text lib.Text, index u32) {
	text.add('rdmsr 0x')
	text.add_radix(u64(index), 16, 8)
	text.add(': ')
	if value := msr.read_safe(index) {
		text.add('0x')
		text.add_radix(value, 16, 16)
	} else {
		text.add('fault')
	}
	text.add_byte(`\n`)
}

fn show_x86_probe(_ voidptr, mut text lib.Text) {
	show_msr(mut text, msr_apic_base)
	show_msr(mut text, msr_unassigned)
	show_msr(mut text, msr_x2apic_reserved)
	$if thermal_selftest ? {
		// A write to a register that is not there: only where it is asked for.
		text.add('wrmsr 0x')
		text.add_radix(u64(msr_x2apic_reserved), 16, 8)
		text.add(if msr.write_safe(msr_x2apic_reserved, 0) { ': written\n' } else { ': fault\n' })
	}
}
