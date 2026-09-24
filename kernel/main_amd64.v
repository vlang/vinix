@[has_globals]
module main

import memory
import term
import lib.stubs
import acpi
import uacpi
import x86.gdt
import x86.idt
import x86.isr
import x86.smp
import initramfs
import numa
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
import dev.e1000
import dev.hda
import dev.random
import dev.mouse
import dev.procdev
import dev.pty
import syscall.table
import socket
import socket.inet
import time
import event
import event.eventstruct
import x86.hpet
import x86.hypervisor
import limine

// The scheduler's device poll: hand what the network card received to the IP
// stack, then run the stack's timers -- DHCP, ARP, TCP retransmission.
fn poll_network() {
	e1000.poll()
	inet.poll()
}

// DHCP finishes inside the scheduler's poll, which is no place to write a file.
// This thread writes /etc/resolv.conf for it, retrying until the root it lands
// on exists.
fn resolver_thread() {
	for {
		mut events := []&eventstruct.Event{}
		mut interval := time.new_timer(time.TimeSpec{
			tv_sec:  1
			tv_nsec: 0
		})
		events << &interval.event
		event.await(mut events, true) or {}
		interval.disarm()
		unsafe { free(interval) }
		unsafe { events.free() }
		inet.publish_resolver()
	}
}

fn kmain_thread() {
	term.framebuffer_init()

	table.init_syscall_table()
	table.init_linux_syscall_table()
	table.init_pipe_usercopy_syscalls()
	table.init_mmap_aslr_syscalls()
	table.init_security_syscalls()
	socket.initialise()
	if e1000.initialise() {
		sched.set_device_poll_callback(voidptr(poll_network))
		sched.new_kernel_thread(voidptr(resolver_thread), unsafe { nil }, true)
	}
	pipe.initialise()
	futex.initialise()
	fs.initialise()

	fs.mount(vfs_root, '', '/', 'tmpfs') or {}
	fs.create(vfs_root, '/dev', 0o644 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/dev', 'devtmpfs') or {}
	hypervisor.initialise()

	initramfs.initialise()

	// The CPU and memory-node topology, at the paths Linux userspace reads it
	// from. Mounted after the initramfs has been unpacked so the mount point is
	// not one of the directories that unpack creates.
	fs.create(vfs_root, '/sys', 0o555 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/sys', 'sysfs') or {}

	streams.initialise()
	random.initialise()
	procdev.initialise()
	pty.initialise()
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

fn kmain() {
	// Before anything that returns: see c/stack_protector.c.
	C.vinix_stack_guard_init()
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

	// The machine's memory topology, read after ACPI has located the tables that
	// describe it and before smp hands out the logical CPU numbers its nodes are
	// matched against.
	numa.initialise()

	smp.initialise()

	// Every logical CPU now exists, so each can be told which node it sits on.
	numa.attach_cpus()

	time.initialise()

	sched.initialise()

	spawn kmain_thread()

	sched.await()
}
