// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module syspower

import uacpi
import x86.kio

// Nothing more to make durable on a PC: its disks are devices, and are shut
// down with the others.
fn platform_prepare() bool {
	return true
}

// ACPI's soft off.
fn platform_power_off() {
	uacpi.power_off()
}

// The reset register ACPI names, then the keyboard controller's reset line,
// which every PC and every PC emulator has, then the port chipsets since the
// PIIX answer to. A machine that ignores all three is reset by taking a fault
// it cannot handle.
fn platform_restart() {
	uacpi.reboot()
	kio.port_out[u8](0x64, 0xfe)
	kio.port_out[u8](0xcf9, 0x06)
	triple_fault()
}

struct NullTable {
	limit u16
	base  u64
}

// With no interrupt table, the breakpoint cannot be delivered, nor the fault
// that causes, nor the fault that causes: the CPU shuts down and the board
// resets it.
fn triple_fault() {
	table := NullTable{}
	asm volatile amd64 {
		cli
		lidt [table]
		int3
		; ; r (&table) as table
		; memory
	}
}

fn platform_halt() {
	for {
		asm volatile amd64 {
			cli
			hlt
		}
	}
}

fn fixed_button(event int) {
	if event == uacpi.fixed_event_power_button {
		button(.power)
	} else if event == uacpi.fixed_event_sleep_button {
		button(.sleep)
	}
}

// ACPI is where a PC's buttons are heard.
fn platform_start() {
	uacpi.on_fixed_button(fixed_button)
	uacpi.start_events()
	register_serial_ports()
}

// Suspend to RAM is ACPI's S3: deep_amd64.v.
