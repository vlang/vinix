module main

import lib.stubs
// unused, but needed for C function stubs
import memory
import term
import acpi
import uacpi
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
import dev.hda
import dev.random
import dev.mouse
import syscall.table
import socket
import time
import x86.hpet
import limine

#include <symbols.h>

@[_linker_section: '.requests']
@[cinit]
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
	hda.initialize()

	$if !prod {
		ata.initialise()
		nvme.initialise()
		ahci.initialise()
	}

	userland.start_program(false, vfs_root, '/sbin/init', ['/sbin/init'], [], '/dev/console',
		'/dev/console', '/dev/console') or { panic('Could not start init process') }

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

	x2apic_mode = smp_req.response.flags & 1 != 0

	// Init terminal
	term.initialise()
	serial.early_initialise()

	// a dummy call to avoid V warning about an unused `stubs` module
	_ := stubs.toupper(0)

	memory.vmm_init()

	// ACPI init
	acpi.initialise()
	hpet.initialise()

	pci.initialise()

	mut uacpi_status := uacpi.UACPIStatus.ok

	uacpi_status = C.uacpi_initialize(0)
	if uacpi_status != uacpi.UACPIStatus.ok {
		panic('uacpi_initialize(): ${C.uacpi_status_to_string(uacpi_status)}')
	}

	uacpi_status = C.uacpi_namespace_load()
	if uacpi_status != uacpi.UACPIStatus.ok {
		panic('uacpi_namespace_load(): ${C.uacpi_status_to_string(uacpi_status)}')
	}

	uacpi_status = C.uacpi_set_interrupt_model(uacpi.InterruptModel.ioapic)
	if uacpi_status != uacpi.UACPIStatus.ok {
		panic('uacpi_interrupt_model(): ${C.uacpi_status_to_string(uacpi_status)}')
	}

	uacpi_status = C.uacpi_namespace_initialize()
	if uacpi_status != uacpi.UACPIStatus.ok {
		panic('uacpi_namespace_initialize(): ${C.uacpi_status_to_string(uacpi_status)}')
	}

	smp.initialise()

	time.initialise()

	sched.initialise()

	spawn kmain_thread()

	sched.await()
}
