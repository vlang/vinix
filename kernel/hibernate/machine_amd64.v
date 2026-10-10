// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What this machine is, as far as a kernel that wakes up in it has to care.
//
// A kernel entered from an image goes on with everything it knew: where the
// boot loader put it and what the boot loader told it, the tables firmware
// described the machine in, the processors it had started, the framebuffer
// it draws on. None of that is asked again. So before an image is entered,
// the machine it was taken on is compared with the machine it would wake in,
// item by item (format.v has the list and the reasons a difference is given
// by), and it is the same code, in the same kernel, that describes both.
//
// Every item is read from where the kernel itself reads it: the boot
// loader's answers, firmware's tables, CPUID. What the boot loader answers
// is in memory the image carries along, so the description is taken when
// the image is, not kept from boot.
module hibernate

import acpi
import limine
import memory
import x86.cpu
import x86.wake

fn C.text_start()
fn C.rodata_end()
fn C.data_end()

// FADT: where the DSDT's address is, in its two widths, and the FACS's.
const fadt_firmware_ctrl = u64(36)
const fadt_dsdt = u64(40)
const fadt_x_firmware_ctrl = u64(132)
const fadt_x_dsdt = u64(140)

// "BGRT" and "FPDT", as the first four bytes of a table read.
const acpi_bgrt = u32(0x54524742)
const acpi_fpdt = u32(0x54445046)

// The types of the boot loader's memory map that are memory the kernel has.
fn is_ram(kind u64) bool {
	return kind == u64(limine.limine_memmap_usable)
		|| kind == u64(limine.limine_memmap_bootloader_reclaimable)
		|| kind == u64(limine.limine_memmap_kernel_and_modules)
}

// How many entries the memory map has, and entry `index` of it.
fn map_entries() u64 {
	if memmap_req.response == unsafe { nil } {
		return 0
	}
	return memmap_req.response.entry_count
}

fn map_entry(index u64) (u64, u64, u64) {
	entries := memmap_req.response.entries
	return unsafe { entries[index].base }, unsafe { entries[index].length }, unsafe { entries[index].@type }
}

// One past the last byte of memory the kernel has.
fn ram_top() u64 {
	mut top := u64(0)
	for index in u64(0) .. map_entries() {
		base, length, kind := map_entry(index)
		if is_ram(kind) && base + length > top {
			top = base + length
		}
	}
	return top
}

fn table_digest(sum u64, table voidptr) u64 {
	if table == unsafe { nil } {
		return mix(sum, 0)
	}
	length := u64(unsafe { *&u32(u64(table) + 4) })
	signature := unsafe { *&u32(table) }
	mut next := mix(sum, u64(table))
	next = mix(next, length)
	next = mix(next, u64(signature))
	// Two tables describe the boot and not the machine, and differ from one
	// start of the same machine to the next: where firmware left its logo,
	// and how long it took to start. The kernel reads neither. They are
	// told apart by where they are and how long, not by what they say.
	if signature == acpi_bgrt || signature == acpi_fpdt {
		return next
	}
	// A table longer than this is not a table; its address and what it
	// claims are enough to tell it from another.
	if length >= 36 && length <= 16 * 1024 * 1024 {
		next = sum_bytes(next, unsafe { &u8(table) }, length)
	}
	return next
}

// Every table the root names, by address, length, name and contents, and the
// two the FADT names: the DSDT likewise, and the FACS -- which firmware and
// the kernel both write to -- by address alone. The kernel inside an image
// has pointers into these tables and runs their methods where they lie.
fn acpi_digest() u64 {
	mut sum := mix(image_magic, u64(acpi.table_count()))
	for index in 0 .. acpi.table_count() {
		sum = table_digest(sum, acpi.table_at(index))
	}
	mut fadt := unsafe { nil }
	for index in 0 .. acpi.table_count() {
		table := acpi.table_at(index)
		// "FACP".
		if table != unsafe { nil } && unsafe { *&u32(table) } == u32(0x50434146) {
			fadt = table
			break
		}
	}
	if fadt != unsafe { nil } {
		length := unsafe { *&u32(u64(fadt) + 4) }
		mut dsdt := u64(unsafe { *&u32(u64(fadt) + fadt_dsdt) })
		mut facs := u64(unsafe { *&u32(u64(fadt) + fadt_firmware_ctrl) })
		if length >= 148 {
			wide := unsafe { *&u64(u64(fadt) + fadt_x_dsdt) }
			if wide != 0 {
				dsdt = wide
			}
			if facs == 0 {
				facs = unsafe { *&u64(u64(fadt) + fadt_x_firmware_ctrl) }
			}
		}
		sum = mix(sum, facs)
		sum = table_digest(sum, if dsdt == 0 { unsafe { nil } } else { voidptr(dsdt + higher_half) })
	}
	return sum
}

fn processor_digest() (u64, u64) {
	response := smp_req.response
	if response == unsafe { nil } {
		return 0, 0
	}
	mut sum := mix(image_magic, u64(response.bsp_lapic_id))
	for index in u64(0) .. response.cpu_count {
		sum = mix(sum, u64(unsafe { response.cpus[index].lapic_id }))
	}
	// What the processor is and can do, less what differs from one
	// processor of a machine to the next (the APIC number in leaf 1) and
	// what moves as features are switched on (the sizes in leaf 13).
	_, a0, b0, c0, d0 := cpu.cpuid(0, 0)
	_, a1, _, c1, d1 := cpu.cpuid(1, 0)
	_, _, b7, c7, d7 := cpu.cpuid(7, 0)
	_, a13, _, c13, d13 := cpu.cpuid(13, 0)
	_, _, _, ce, de := cpu.cpuid(0x80000001, 0)
	_, a8, _, _, _ := cpu.cpuid(0x80000008, 0)
	for value in [a0, b0, c0, d0, a1, c1 & ~(u32(1) << 27), d1, b7, c7, d7, a13, c13, d13, ce, de,
		a8]! {
		sum = mix(sum, u64(value))
	}
	return response.cpu_count, sum
}

fn framebuffer_digest() (u64, u64) {
	response := fb_req.response
	if response == unsafe { nil } || response.framebuffer_count == 0 {
		return 0, mix(image_magic, 0)
	}
	mut sum := mix(image_magic, response.framebuffer_count)
	mut first := u64(0)
	for index in u64(0) .. response.framebuffer_count {
		fb := unsafe { response.framebuffers[index] }
		if index == 0 {
			first = u64(fb.address)
		}
		sum = mix(sum, u64(fb.address))
		sum = mix(sum, fb.width)
		sum = mix(sum, fb.height)
		sum = mix(sum, fb.pitch)
		sum = mix(sum, u64(fb.bpp) | (u64(fb.memory_model) << 16))
		sum = mix(sum, u64(fb.red_mask_size) | (u64(fb.red_mask_shift) << 8) | (u64(fb.green_mask_size) << 16) | (u64(fb.green_mask_shift) << 24) | (u64(fb.blue_mask_size) << 32) | (u64(fb.blue_mask_shift) << 40))
	}
	return first, sum
}

fn command_line_digest() u64 {
	file := limine.kernel_file()
	if file == unsafe { nil } || file.cmdline == unsafe { nil } {
		return mix(image_magic, 0)
	}
	text := unsafe { &u8(file.cmdline) }
	mut length := u64(0)
	for unsafe { text[length] } != 0 {
		length++
	}
	return sum_bytes(image_magic, text, length)
}

// The machine as it is now. Not cheap -- the kernel's code is read through --
// and not allocating.
fn this_machine() Machine {
	mut machine := Machine{}
	if kaddr_req.response != unsafe { nil } {
		machine.kernel_virtual = kaddr_req.response.virtual_base
		machine.kernel_physical = kaddr_req.response.physical_base
	}
	// To the end of what the kernel's own page table maps of it.
	machine.kernel_bytes = (u64(voidptr(C.data_end)) - machine.kernel_virtual + page_size - 1) / page_size * page_size
	text := u64(voidptr(C.text_start))
	machine.kernel_digest = sum_bytes(image_magic, unsafe { &u8(text) }, u64(voidptr(C.rodata_end)) - text)
	machine.direct_map = higher_half
	machine.paging_levels = if la57 { u64(5) } else { u64(4) }

	// Memory as runs: an entry that starts where the one before it ended
	// carries the run on, whichever of the three kinds each is.
	mut fixed := image_magic
	mut memory_sum := image_magic
	mut run_base := u64(0)
	mut run_end := u64(0)
	for index in u64(0) .. map_entries() {
		base, length, kind := map_entry(index)
		if !is_ram(kind) {
			fixed = mix(mix(mix(fixed, base), length), kind)
			continue
		}
		if run_end != 0 && base == run_end {
			run_end = base + length
			continue
		}
		if run_end != 0 {
			memory_sum = mix(mix(memory_sum, run_base), run_end)
		}
		run_base = base
		run_end = base + length
	}
	if run_end != 0 {
		memory_sum = mix(mix(memory_sum, run_base), run_end)
	}
	machine.map_fixed = fixed
	machine.map_memory = memory_sum
	machine.memory_top = ram_top()

	machine.acpi_root = acpi.root_address()
	machine.acpi_tables = acpi_digest()
	machine.framebuffer, machine.framebuffer_layout = framebuffer_digest()
	machine.processors, machine.processor_digest = processor_digest()
	machine.command_line = command_line_digest()
	machine.low_base, machine.low_pages = memory.low_pages()
	wake.trace('machine: kernel at', machine.kernel_physical)
	wake.trace('machine: kernel mapped at', machine.kernel_virtual)
	wake.trace('machine: kernel bytes', machine.kernel_bytes)
	wake.trace('machine: kernel digest', machine.kernel_digest)
	wake.trace('machine: direct map', machine.direct_map)
	wake.trace('machine: memory', machine.map_memory)
	wake.trace('machine: firmware regions', machine.map_fixed)
	wake.trace('machine: acpi root', machine.acpi_root)
	wake.trace('machine: acpi tables', machine.acpi_tables)
	wake.trace('machine: framebuffer', machine.framebuffer)
	wake.trace('machine: framebuffer layout', machine.framebuffer_layout)
	wake.trace('machine: processors', machine.processor_digest)
	wake.trace('machine: command line', machine.command_line)
	wake.trace('machine: low pages', machine.low_base)
	return machine
}
