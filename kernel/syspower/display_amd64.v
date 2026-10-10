// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The screen across a suspend to RAM.
//
// The kernel has no graphics driver on a PC. It draws on the framebuffer
// firmware set up and the boot loader handed over, and firmware does not set
// it up a second time when the machine wakes from S3: the display adapter
// comes back in whatever mode power-on leaves it in, which is not the one the
// framebuffer was laid out for, and what was on the screen is gone. A machine
// that woke like that would be running and dark, with nothing to say so.
//
// So deep sleep is only offered where the kernel can put the picture back
// itself, and there is one adapter it knows how to do that for: the one
// QEMU's "std" VGA and bochs-display have (PCI 1234:1111), whose mode is a
// handful of registers of the Bochs display interface. They are read out
// before the sleep and written back after it; the picture itself is put away
// and put back by the sleep sequence, as for any sleep (term/sleep.v), once
// there is a mode to show it in again.
//
// Everywhere else display_survives_deep() says no, and /sys/power/mem_sleep
// lists only s2idle -- unless the machine has no framebuffer at all, where
// there is nothing to lose, or the kernel command line has
// vinix.deep_sleep=force, for a machine that is run without a screen or whose
// firmware is known to restore the mode itself.
@[has_globals]
module syspower

import devcore
import memory
import pci
import term
import x86.kio
import x86.wake

const bochs_vendor = u16(0x1234)
const bochs_device = u16(0x1111)
const display_class = u8(0x03)

// The Bochs display interface: an index and a data port, or the same
// registers sixteen bits apart in the adapter's second memory range, where
// the VGA ports are mapped as well.
const dispi_index_port = u16(0x1ce)
const dispi_data_port = u16(0x1cf)
const dispi_mmio_offset = u64(0x500)
const vga_mmio_offset = u64(0x400)
const vga_attribute_port = u16(0x3c0)
const vga_status_port = u16(0x3da)
// Written to the attribute controller's index: the picture is shown.
const vga_palette_source = u8(0x20)

const dispi_id = 0
const dispi_xres = 1
const dispi_yres = 2
const dispi_bpp = 3
const dispi_enable = 4
const dispi_bank = 5
const dispi_virt_width = 6
const dispi_virt_height = 7
const dispi_x_offset = 8
const dispi_y_offset = 9
const dispi_registers = 10

const dispi_enabled = u16(0x01)
const dispi_keep_memory = u16(0x80)

// Page attribute bits: PWT and PCD together select the uncached PAT entry.
const display_pte_write_through = u64(1) << 3
const display_pte_cache_disable = u64(1) << 4

struct DisplayState {
mut:
	decided   bool
	restorable bool
	adapter   &pci.PCIDevice = unsafe { nil }
	// The adapter's register range, mapped, or 0 when it has none and the
	// legacy ports are used.
	mmio u64
	// The mode as read before the sleep.
	saved     bool
	registers [dispi_registers]u16
	// How often the picture has been brought back, how often the adapter
	// was found to have lost its mode, and how often it would not take it
	// back.
	restores  u64
	found_off u64
	failures  u64
}

__global (
	syspower_display DisplayState
)

fn dispi_read(index int) u16 {
	if syspower_display.mmio != 0 {
		return kio.mmin[u16](unsafe { &u16(syspower_display.mmio + dispi_mmio_offset + u64(index) * 2) })
	}
	kio.port_out[u16](dispi_index_port, u16(index))
	return kio.port_in[u16](dispi_data_port)
}

fn dispi_write(index int, value u16) {
	if syspower_display.mmio != 0 {
		kio.mmout[u16](unsafe { &u16(syspower_display.mmio + dispi_mmio_offset + u64(index) * 2) }, value)
		return
	}
	kio.port_out[u16](dispi_index_port, u16(index))
	kio.port_out[u16](dispi_data_port, value)
}

// Show the picture: the VGA side of the adapter blanks the screen until its
// attribute controller is told a palette is in place.
fn vga_unblank() {
	if syspower_display.mmio != 0 {
		base := syspower_display.mmio + vga_mmio_offset
		kio.mmin[u8](unsafe { &u8(base + u64(vga_status_port - vga_attribute_port)) })
		kio.mmout[u8](unsafe { &u8(base) }, vga_palette_source)
		return
	}
	kio.port_in[u8](vga_status_port)
	kio.port_out[u8](vga_attribute_port, vga_palette_source)
}

fn display_map_registers(phys u64, length u64) u64 {
	hhdm := memory.get_hhdm_offset()
	if phys + length <= u64(0x100000000) {
		// The direct map covers the first 4 GiB, device memory included.
		return phys + hhdm
	}
	flags := memory.pte_present | memory.pte_writable | memory.pte_noexec | display_pte_write_through | display_pte_cache_disable
	for page := phys & ~u64(0xfff); page < phys + length; page += 0x1000 {
		kernel_pagemap.map_page(page + hhdm, page, flags) or { return 0 }
	}
	return phys + hhdm
}

// The adapter whose first memory range the framebuffer lies in, if it is one
// this file can program.
fn find_display_adapter(framebuffer u64, length u64) &pci.PCIDevice {
	for i := 0; i < devcore.device_count(); i++ {
		dev := devcore.device_at(i)
		if dev == unsafe { nil } || dev.bus != .pci || dev.pci == unsafe { nil } {
			continue
		}
		if dev.class != display_class || !dev.is_pci(bochs_vendor, bochs_device) {
			continue
		}
		if !dev.pci.is_bar_present(0) {
			continue
		}
		bar := dev.pci.get_bar(0)
		if bar.is_mmio && framebuffer >= bar.base && framebuffer + length <= bar.base + bar.size {
			return dev.pci
		}
	}
	return unsafe { nil }
}

// Whether what is on the screen can be brought back after a suspend to RAM:
// there is no screen, or it is on an adapter whose mode the kernel can set.
// Worked out once; the framebuffer and the PCI devices are those of the boot.
fn display_survives_deep() bool {
	mut display := &syspower_display
	if display.decided {
		return display.restorable
	}
	display.decided = true
	framebuffer, length := term.framebuffer_phys_span()
	if length == 0 {
		// No framebuffer: nothing is drawn, and nothing can go dark.
		display.restorable = true
		return true
	}
	adapter := find_display_adapter(framebuffer, length)
	if adapter == unsafe { nil } {
		return false
	}
	display.adapter = adapter
	if adapter.is_bar_present(2) {
		registers := adapter.get_bar(2)
		if registers.is_mmio && registers.size >= 0x600 {
			display.mmio = display_map_registers(registers.base, registers.size)
		}
	}
	// Versions 0xb0c0 to 0xb0c5 of the interface; anything else is not it.
	id := dispi_read(dispi_id)
	if id & 0xfff0 != 0xb0c0 || dispi_read(dispi_enable) & dispi_enabled == 0 {
		display.adapter = unsafe { nil }
		display.mmio = 0
		return false
	}
	display.restorable = true
	return true
}

// Read out the mode. Before the sleep, with the adapter still powered. What
// is on the screen has been put away already, by the sleep sequence itself
// (term/sleep.v), and is put back by it once the mode is.
fn display_save() {
	mut display := &syspower_display
	display.saved = false
	if display.adapter == unsafe { nil } {
		return
	}
	for index in 0 .. dispi_registers {
		display.registers[index] = dispi_read(index)
	}
	display.saved = true
}

// Set the mode again. After the sleep, once the adapter's configuration
// space has been restored and its registers answer, and before the sleep
// sequence copies the picture back into the framebuffer.
fn display_restore() {
	mut display := &syspower_display
	if display.adapter == unsafe { nil } || !display.saved {
		return
	}
	display.saved = false
	saved := display.registers
	// How the adapter came back: with the mode gone, when it lost power.
	if dispi_read(dispi_enable) & dispi_enabled == 0 {
		display.found_off++
	}
	// The size may only change while the interface is off, and switching it
	// on sets the virtual size and the offsets to defaults, so those go in
	// again afterwards.
	dispi_write(dispi_enable, 0)
	dispi_write(dispi_bank, 0)
	dispi_write(dispi_bpp, saved[dispi_bpp])
	dispi_write(dispi_xres, saved[dispi_xres])
	dispi_write(dispi_yres, saved[dispi_yres])
	dispi_write(dispi_virt_width, saved[dispi_virt_width])
	dispi_write(dispi_virt_height, saved[dispi_virt_height])
	dispi_write(dispi_enable, saved[dispi_enable] | dispi_keep_memory)
	dispi_write(dispi_virt_width, saved[dispi_virt_width])
	dispi_write(dispi_virt_height, saved[dispi_virt_height])
	dispi_write(dispi_x_offset, saved[dispi_x_offset])
	dispi_write(dispi_y_offset, saved[dispi_y_offset])
	vga_unblank()

	took := dispi_read(dispi_xres) == saved[dispi_xres] && dispi_read(dispi_yres) == saved[dispi_yres]
		&& dispi_read(dispi_bpp) == saved[dispi_bpp]
		&& dispi_read(dispi_virt_width) == saved[dispi_virt_width]
		&& dispi_read(dispi_enable) & dispi_enabled != 0
	wake.trace('display mode taken', if took { u64(1) } else { u64(0) })
	display.restores++
	if !took {
		display.failures++
		C.kprintf(c'syspower: the display did not take its mode back: %llux%llu at %llu bits wanted, %llux%llu at %llu read\n',
			u64(saved[dispi_xres]), u64(saved[dispi_yres]), u64(saved[dispi_bpp]), u64(dispi_read(dispi_xres)),
			u64(dispi_read(dispi_yres)), u64(dispi_read(dispi_bpp)))
		return
	}
	if !screen_dark {
		// The picture was not put away -- there was no memory for it -- and
		// what the adapter's memory holds after a loss of power is anybody's
		// guess. The console at least can draw itself again; a program that
		// draws on the screen itself has to do the same.
		term.display_hotplug(true)
	}
}

// The sleep did not happen: the mode was never lost, and is not written.
fn display_discard() {
	syspower_display.saved = false
}
