module pci

__global (
	scanned_devices []&PCIDevice
)

const max_function = 8

const max_device = 32

const max_bus = 256

pub fn initialise() {
	print('pci: Building device scan\n')
	mut root_bus := PCIDevice{}
	configc := root_bus.read[u32](0xc)

	if (configc & 0x800000) == 0 {
		check_bus(0, -1)
	} else {
		for function := u8(0); function < max_function; function++ {
			host_bridge := PCIDevice{
				bus:      0
				slot:     0
				function: function
				parent:   0
			}
			config0 := host_bridge.read[u32](0)
			if config0 == 0xffffffff {
				continue
			}

			check_bus(function, -1)
		}
	}
}

fn check_bus(bus u8, parent i64) {
	for dev := u8(0); dev < max_device; dev++ {
		for func := u8(0); func < max_function; func++ {
			check_function(bus, dev, func, parent)
		}
	}
}

fn check_function(bus u8, slot u8, function u8, parent i64) {
	mut device := &PCIDevice{
		bus:      bus
		slot:     slot
		function: function
		parent:   parent
	}
	device.read_info()
	if device.device_id == 0xffff && device.vendor_id == 0xffff {
		return
	}

	// Handle PCI to PCI bridges, and we are done.
	if device.class == 0x6 && device.subclass == 0x4 {
		config := device.read[u32](0x18)
		check_bus(u8(config >> 8), 1)
	} else {
		scanned_devices << device

		status := device.read[u16](0x6)

		if (status & (1 << 4)) != 0 { // parse capabilities list
			mut off := device.read[u8](0x34)

			for off > 0 {
				id := device.read[u8](off)

				match id {
					0x5 {
						device.msi_support = true
						device.msi_offset = off
					}
					0x11 {
						device.msix_support = true
						device.msix_offset = off

						message_control := device.read[u16](off + 2)

						device.msix_table_size = message_control & 0x7FF
						device.msix_table_bitmap.initialise(device.msix_table_size)
					}
					else {}
				}

				off = device.read[u8](off + 1)
			}
		}

		print('pci: Found [${device.bus:x}:${device.slot:x}:${device.function:x}:${device.parent:x}]\n')
	}
}

pub fn get_device_by_vendor(vendor_id u16, device_id u16, index u32) ?&PCIDevice {
	mut count := 0
	for device in scanned_devices {
		if device.vendor_id == vendor_id && device.device_id == device_id {
			if count == index {
				return unsafe { device }
			} else {
				count += 1
			}
		}
	}
	return none
}

pub fn get_device_by_coordinates(bus u8, slot u8, function u8, index u32) ?&PCIDevice {
	mut count := 0
	for device in scanned_devices {
		if device.bus == bus && device.slot == slot && device.function == function {
			if count == index {
				return unsafe { device }
			} else {
				count += 1
			}
		}
	}
	return none
}

pub fn get_device_by_class(class u8, subclass u8, progif u8, index u32) ?&PCIDevice {
	mut count := 0
	for device in scanned_devices {
		if device.class == class && device.subclass == subclass && device.prog_if == progif {
			if count == index {
				return unsafe { device }
			} else {
				count += 1
			}
		}
	}
	return none
}
