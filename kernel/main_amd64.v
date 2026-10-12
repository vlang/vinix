@[has_globals]
module main

import memory
import term
import lib.stubs
import acpi
import uacpi
import acpisync
import x86.gdt
import x86.idt
import x86.isr
import x86.smp
import x86.wake
import initramfs
import numa
import fs
import sched
import proc
import stat
import dev.console
import userland
import syspower
import x86.acpihp
import x86.acpipm
import x86.acpiec
import pipe
import futex
import pci
import devcore
import fwload
import cpuidle
import cpufreq
import dma
import dev.ata
import dev.fbdev
import dev.fbdev.simple
import dev.nvme
import dev.serial
import dev.streams
import dev.ahci
import dev.e1000
import dev.rtl8169
import dev.ath10k
import dev.hda
import dev.random
import dev.mouse
import dev.xhci
import dev.procdev
import dev.pty
import dev.tty
import syscall.table
import sysdisk
import hibernate
import block.verity
import socket
import socket.inet
import thermal
import time
import x86.hpet
import x86.hypervisor
import limine
import linuxkpi
import security

// The scheduler's device poll: hand what the network card received to the IP
// stack, then run the stack's timers -- DHCP, ARP, TCP retransmission.
fn poll_network() {
	e1000.poll()
	rtl8169.poll()
	ath10k.poll()
	inet.poll()
}

fn kmain_thread() {
	$if largepage_selftest ? { sched.selftest_largepage_smp() }
	acpisync.scheduler_ready()
	acpisync.test_native()
	term.framebuffer_init()
	linuxkpi.initialise()

	table.init_syscall_table()
	table.init_storage_syscalls()
	table.init_clock_control_syscalls()
	// cgroup.kill sends a signal, which lives above fs; hand it the entry point.
	fs.set_cgroup_signal_hook(voidptr(userland.cgroup_kill_process))
	userland.initialise_oom()
	proc.register_cpu_signal_hook(voidptr(userland.cpu_signal_process))
	proc.register_job_orphan_hook(voidptr(userland.signal_orphaned_job_group))
	// What an interrupt returning to userspace does for a thread with a signal
	// to take; the scheduler cannot import userland.
	sched.register_user_signal_hook(voidptr(userland.interrupt_return))
	table.init_pipe_usercopy_syscalls()
	table.init_mmap_aslr_syscalls()
	table.init_security_syscalls()
	socket.initialise()
	// Failure reports and removals are carried out by a thread of the core's.
	devcore.start_worker()
	// Cards that are put in and taken out while the machine runs. Firmware
	// says whether it watches the ports itself or hands them over.
	devcore.start_pci_hotplug(acpihp.initialise())
	// IOMMUs come before the first driver that does DMA: a unit that is on
	// decides what every device behind it may reach.
	dma.initialise()
	// Polled whether or not a card was found: one can arrive later, in a
	// slot, and with none the poll costs a test of a flag.
	e1000.initialise()
	rtl8169.initialise()
	$if net_carrier_selftest ? { inet.carrier_selftest() }
	sched.set_device_poll_callback(voidptr(poll_network))
	pipe.initialise()
	futex.initialise()
	fs.initialise()

	fs.mount(vfs_root, '', '/', 'tmpfs') or {}
	fs.create(vfs_root, '/dev', 0o644 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/dev', 'devtmpfs') or {}
	// /proc, as arm64 has it: /proc/self/exe, /proc/meminfo and the process
	// directories are where Linux programs look for themselves and for the
	// machine, and nothing in the amd64 image mounts it.
	fs.create(vfs_root, '/proc', 0o555 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/proc', 'procfs') or {}
	hypervisor.initialise()

	// A machine booted from an installer image (vinix.disk=auto) keeps its
	// system on a disk, so the disk drivers come up before the image is
	// unpacked, and the image goes onto the disk rather than into RAM when
	// there is one to take it. See sysdisk. IDE and SATA only: the NVMe
	// driver is not fit for a release kernel yet.
	verified_root := verity.requested()
	// A device named to keep an image of memory on is a disk too.
	image_named := hibernate.device_name().len != 0
	disk_requested := sysdisk.requested() || verified_root || image_named
	mut outcome := sysdisk.Outcome.in_memory
	if disk_requested {
		ata.initialise()
		ahci.initialise()
		// Here and nowhere later: the disks are up, and nothing on any of
		// them has been mounted, replayed or written. If the device named
		// for it holds an image of this machine, taken when it was last
		// switched off, the kernel in it is gone back into and this call
		// does not return. That kernel has its filesystems as they were;
		// had this one mounted them first, it would wake to disks that had
		// moved on without it. See hibernate/resume_amd64.v.
		hibernate.resume_at_boot()
		// Still here. If an image that could yet be gone back into is on a
		// disk all the same -- on a device this boot was not told of, or
		// one that could not be read or written -- the system's disk is not
		// mounted: this kernel would change the filesystem the image holds
		// in memory. It runs from memory instead, and says why. A verified
		// root is only read, and is mounted regardless.
		image_waiting := hibernate.look_for_images()
		if verified_root {
			verity.mount_root()
		} else if sysdisk.requested() && !image_waiting {
			outcome = sysdisk.mount_or_install()
		}
	}
	if !verified_root {
		match outcome {
			.in_memory { initramfs.initialise() }
			.booted { initramfs.initialise_overlays() }
			else {}
		}
	}

	// Shared-memory files need tmpfs's paged backing, as on arm64: a regular
	// file on devtmpfs grows as one contiguous allocation.
	fs.create(vfs_root, '/dev/shm', 0o1777 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/dev/shm', 'tmpfs') or {}
	// The mounted tmpfs root replaces the covered directory's permissions.
	if mut shm := fs.get_node(vfs_root, '/dev/shm', true) {
		shm.resource.stat.mode = stat.ifdir | 0o1777
	}

	// The CPU and memory-node topology, at the paths Linux userspace reads it
	// from. Mounted after the initramfs has been unpacked so the mount point is
	// not one of the directories that unpack creates.
	fs.create(vfs_root, '/sys', 0o555 | stat.ifdir) or {}
	fs.mount(vfs_root, '', '/sys', 'sysfs') or {}
	// Devices and drivers so far, and every change from here on.
	devcore.publish()
	dma.publish()
	syspower.publish()
	fwload.publish()
	// The idle states of this machine's CPUs, which they use from here on.
	cpuidle.publish()
	// And how fast they run.
	cpufreq.publish()
	// The processor's temperature sensors and energy counters, and the
	// thermal zones other drivers registered before /sys was there.
	thermal.publish()

	streams.initialise()
	random.initialise()
	// Firmware-backed Wi-Fi probes after the initramfs and devtmpfs exist.
	ath10k.initialise()
	procdev.initialise()
	pty.initialise()
	fbdev.initialise()
	fbdev.register_driver(simple.get_driver())
	console.initialise()
	tty.initialise()
	serial.initialise()
	mouse.initialise()
	// USB keyboards and pointers, where there is an xHCI controller: a PC
	// need not have a PS/2 port. After the two above, which it reports into.
	xhci.initialise()
	hda.initialize()

	$if !prod {
		if !disk_requested {
			ata.initialise()
			ahci.initialise()
		}
		nvme.initialise()
	}

	sched.new_kernel_thread(voidptr(maintenance_thread), unsafe { nil }, true)
	sched.new_kernel_thread(voidptr(writeback_thread), unsafe { nil }, true)

	// Firmware's events and the buttons they report. A power button asks init
	// first, which the signal code -- above syspower -- does for it.
	syspower.set_init_signal(userland.signal_init_if_handled)
	syspower.start()
	// The embedded controller's events, now that there are threads to take
	// them; and before the devices whose methods read the controller.
	acpiec.start()
	// The batteries, charger, lid and buttons firmware describes.
	acpipm.initialise()
	// Its thermal zones and fans.
	acpipm.initialise_thermal()
	acpipm.initialise_backlight()

	userland.start_program(false, vfs_root, '/sbin/init', ['/sbin/init'], [], '/dev/console',
		'/dev/console', '/dev/console') or { panic('Could not start init process') }

	sched.dequeue_and_die()
}

fn kmain() {
	// Before anything that returns: see lib/stack_protector.v.
	C.vinix_stack_guard_init()
	// Ensure the base revision is supported.
	if limine_base_revision.revision != 0 {
		for {}
	}

	// Initialize the memory allocator.
	memory.pmm_init()
	// Before anything allocates: the pages under 1 MiB that a processor
	// starts on after a suspend to RAM are the first the allocator would
	// hand out. The count is x86.wake's low_pages_wanted, which like every
	// constant is not set until the runtime is.
	memory.reserve_low_pages(8)

	// Call Vinit to initialise the runtime
	C._vinit(0, 0)

	// Initialize the earliest arch structures.
	asm volatile amd64 { cli; ; ; memory }
	gdt.initialise()
	idt.initialise()
	isr.initialise()

	x2apic_mode = smp_req.response.flags & 1 != 0

	// Init terminal
	term.initialise()
	serial.early_initialise()
	security.initialise_boot_policy()

	// a dummy call to avoid V warning about an unused `stubs` module
	_ := stubs.toupper(0)

	memory.vmm_init()
	$if hv_memory_selftest ? {
		hypervisor.memory_selftest()
	}
	// The real-mode entry a suspend to RAM comes back through, in its page.
	wake.install()

	// ACPI init
	acpi.initialise()
	hpet.initialise()
	acpisync.test_boot()

	pci.initialise()
	// What the scan found becomes devices for drivers to be offered.
	devcore.enumerate_pci()

	mut uacpi_status := uacpi.UACPIStatus.ok

	uacpi_status = C.uacpi_initialize(0)
	if uacpi_status != uacpi.UACPIStatus.ok {
		panic('uacpi_initialize(): ${C.uacpi_status_to_string(uacpi_status)}')
	}

	// An embedded controller that firmware describes in a table of its own
	// is there for the tables about to be loaded to use.
	acpiec.early()

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

	// The embedded controller the namespace describes: from here on the
	// methods that read a battery or a lid through it work.
	acpiec.discover()

	// The machine's memory topology, read after ACPI has located the tables that
	// describe it and before smp hands out the logical CPU numbers its nodes are
	// matched against.
	numa.initialise()

	smp.initialise()

	// Every logical CPU now exists, so each can be told which node it sits on.
	numa.attach_cpus()
	// And room can be made for what each loses in a suspend to RAM.
	wake.initialise()

	time.initialise()

	sched.initialise()

	spawn kmain_thread()

	sched.enter_idle()
}
