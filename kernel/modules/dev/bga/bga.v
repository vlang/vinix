module bga

import pci
import klock
import x86.kio
import dev.fbdev
import dev.fbdev.api

const (
	bga_driver = api.FramebufferDriver{'bga', bga_init, voidptr(0)}
)

const (
	bga_vendor_id = 0x1234
	bga_device_id = 0x1111

	bga_class = 0x03
	bga_prog_if = 0x00

	bga_subclass_vga_compat = 0x00
	bga_subclass_no_vga_compat = 0x80
)

const (
	bga_vga_offset = 0x400
)

const (
	bga_vbe_offset = 0x500

	vbe_dispi_id = 0x00
	vbe_dispi_xres = 0x01
	vbe_dispi_yres = 0x02
	vbe_dispi_bpp = 0x03
	vbe_dispi_en = 0x04
	vbe_dispi_bank = 0x05

	vbe_dispi_disabled = 0x00
	vbe_dispi_enabled = 0x01
	vbe_dispi_noclearmem = 0x80
)

struct BGADisplay {
mut:
	is_vga_compat bool
	width int
	height int
	bpp int
	fb voidptr
	bar2 voidptr

	/* Only applicable if it's VGA compatible */
	is_vga_mode bool
	is_vga_text_mode bool

	bga_lock klock.Lock
}

fn (dev BGADisplay) vbe_read(index u8) u16 {
	return kio.mmin<u16>(&u16(usize(dev.bar2) + bga_vbe_offset + (index << 1)))
}

fn (dev BGADisplay) vbe_write(index u8, value u16) {
	kio.mmout<u16>(&u16(usize(dev.bar2) + bga_vbe_offset + (index << 1)), value)
}

// TODO: Sanity check for resolutions
fn (mut dev BGADisplay) hires(width int, height int, bpp int, noclearmem bool) {
	dev.bga_lock.acquire()
	flags := u16(if noclearmem { vbe_dispi_noclearmem } else { 0 })
	dev.vbe_write(vbe_dispi_en, vbe_dispi_disabled | flags)
	dev.vbe_write(vbe_dispi_xres, u16(width))
	dev.vbe_write(vbe_dispi_yres, u16(height))
	dev.vbe_write(vbe_dispi_bpp, u16(bpp))
	dev.vbe_write(vbe_dispi_en, vbe_dispi_enabled | flags)

	dev.width = width
	dev.height = height
	dev.bpp = bpp

	if dev.is_vga_compat == true {
		dev.is_vga_mode = false
	}

	dev.bga_lock.release()
}

fn (mut dev BGADisplay) initialise(pci_device &pci.PCIDevice) int {
	dev.is_vga_compat = if pci_device.subclass == bga_subclass_vga_compat { true } else { false }

	if dev.is_vga_compat == true {
		print('bga: found vga compatible display\n')
	} else {
		print('bga: found non-vga compatible display\n')
	}

	if pci_device.is_bar_present(0) == false || pci_device.is_bar_present(2) == false {
		print('bga: unable to locate BAR0/BAR2\n')
		return -1
	}

	dev.fb = voidptr(pci_device.get_bar(0).base + higher_half)
	dev.bar2 = voidptr(pci_device.get_bar(2).base + higher_half)

	if dev.is_vga_compat == true && dev.vbe_read(vbe_dispi_en) == vbe_dispi_disabled {
		// Assume VGA text mode 3
		dev.width = 720
		dev.height = 400
		dev.bpp = 4
		dev.is_vga_mode = true
		dev.is_vga_text_mode = true
	} else if dev.vbe_read(vbe_dispi_en) == vbe_dispi_disabled {
		// This is a non-VGA capable BGA display which hasn't been enabled, set some default mode
		dev.hires(1024, 768, 32, false)
	} else {
		// VBE is already enabled on this monitor
		dev.width = dev.vbe_read(vbe_dispi_xres)
		dev.height = dev.vbe_read(vbe_dispi_yres)
		dev.bpp = dev.vbe_read(vbe_dispi_bpp)
	}

	return 0
}

pub fn bga_init() {
	for device in scanned_devices {
		if device.vendor_id == bga_vendor_id && device.device_id == bga_device_id {
			if device.class == bga_class && device.prog_if == bga_prog_if {
				mut bga_device := &BGADisplay{}
				bga_device.initialise(device)
			}
		}
	}
}

pub fn initialise() {
	// Register this driver into fbdev
	fbdev.register_driver(bga_driver)
}
