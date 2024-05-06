// main.v: Main functions and entrypoints of the kernel.
// Code is governed by the GPL-2.0 license.
// Copyright (C) 2021-2022 The Vinix authors.

module main

import lib.stubs
// unused, but needed for C function stubs
import memory
import term
import acpi
import x86.gdt
import x86.idt
import x86.isr
import x86.smp
import initramfs
import fs
import sched
import stat
import dev.console
import userland
import pipe
import futex
import pci
import dev.ata
import dev.fbdev
import dev.fbdev.simple
import dev.nvme
import dev.serial
import dev.streams
import dev.ahci
import dev.random
import dev.mouse
import syscall.table
import socket
import time
import limine

@[cinit]
@[_linker_section: '.requests']
__global (
	volatile limine_base_revision = limine.LimineBaseRevision{
		revision: 2
	}
)

fn C._vinit(argc int, argv voidptr)

fn kmain_thread() {
	term.framebuffer_init()

	table.init_syscall_table()
	socket.initialise()
	pipe.initialise()
	futex.initialise()
	fs.initialise()
	pci.initialise()

	fs.mount(vfs_root, '', '/', 'tmpfs') or {}
	fs.create(vfs_root, '/dev', 0o644 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/dev', 'devtmpfs') or {}

	initramfs.initialise()

	streams.initialise()
	random.initialise()
	fbdev.initialise()
	fbdev.register_driver(simple.get_driver())
	console.initialise()
	serial.initialise()
	mouse.initialise()

	$if !prod {
		ata.initialise()
		nvme.initialise()
		ahci.initialise()
	}

	userland.start_program(false, vfs_root, '/sbin/init', ['/sbin/init'], [],
	'/dev/console', '/dev/console', '/dev/console') or { panic('Could not start init process') }

	sched.dequeue_and_die()
}

pub fn main() {
	kmain()
}

pub fn kmain() {
	// Ensure the base revision is supported.
	if limine_base_revision.revision != 0 {
		for {}
	}

	// Initialize the memory allocator.
	memory.pmm_init()

	// Call Vinit to initialise the runtime
	C._vinit(0, 0)

	// Initialize the earliest arch structures.
	gdt.initialise()
	idt.initialise()
	isr.initialise()

	// Init terminal
	term.initialise()
	serial.early_initialise()

	// We're alive
	println('Welcome to Vinix\n')

	// a dummy call to avoid V warning about an unused `stubs` module
	_ := stubs.toupper(0)

	memory.vmm_init()

	// ACPI init
	acpi.initialise()

	smp.initialise()

	time.initialise()

	sched.initialise()

	spawn kmain_thread()

	sched.await()
}
