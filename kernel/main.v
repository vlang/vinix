module main

import lib
import memory
import stivale2
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
import kprint
import pipe
import futex
import pci

fn C._vinit(argc int, argv voidptr)

fn kmain_thread(stivale2_struct &stivale2.Struct) {
	pipe.initialise()
	futex.initialise()
	fs.initialise()
	pci.initialise()

	fs.mount(vfs_root, '', '/', 'tmpfs') or {}
	fs.create(vfs_root, '/dev', 0o644 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/dev', 'devtmpfs') or {}

	modules_tag := unsafe { &stivale2.ModulesTag(stivale2.get_tag(stivale2_struct, stivale2.modules_id)) }
	if modules_tag == 0 {
		panic('Stivale2 modules tag missing')
	}

	initramfs.init(modules_tag)

	console.initialise()

	userland.start_program(false, vfs_root, '/usr/bin/bash', ['/usr/bin/bash'],
							['HOME=/root',
							'TERM=linux',
							'PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'],
							'/dev/console', '/dev/console', '/dev/console') or {
		panic('Could not start init process')
	}

	sched.dequeue_and_die()
}

pub fn main() {
	kmain(voidptr(0))
}

pub fn kmain(stivale2_struct &stivale2.Struct) {
	// Initialize the earliest arch structures.
	gdt.initialise()
	idt.initialise()
	isr.initialise()

	// Init terminal
	stivale2.terminal_init(stivale2_struct)

	// We're alive
	kprint.kprint(c'Welcome to Vinix\n\n')

	// Initialize the memory allocator.
	memmap_tag := unsafe { &stivale2.MemmapTag(stivale2.get_tag(stivale2_struct, stivale2.memmap_id)) }
	if memmap_tag == 0 {
		lib.kpanic(c'Stivale2 memmap tag missing')
	}

	memory.pmm_init(memmap_tag)
	memory.vmm_init(memmap_tag)

	// Call Vinit to initialise the runtime
	C._vinit(0, 0)

	// ACPI init
	rsdp_tag := unsafe { &stivale2.RSDPTag(stivale2.get_tag(stivale2_struct, stivale2.rsdp_id)) }
	if rsdp_tag == 0 {
		panic('Stivale2 RSDP tag missing')
	}

	acpi.init(&acpi.RSDP(rsdp_tag.rsdp))

	smp_tag := unsafe { &stivale2.SMPTag(stivale2.get_tag(stivale2_struct, stivale2.smp_id)) }
	if smp_tag == 0 {
		panic('Stivale2 SMP tag missing')
	}

	smp.initialise(smp_tag)

	sched.initialise()

	go kmain_thread(stivale2_struct)

	sched.await()
}
