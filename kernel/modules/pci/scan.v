module pci

__global (
	scanned_devices []&PCIDevice
)

const max_function = 8
const max_device = 32
const max_bus = 256

pub fn initialise() {
	scanned_devices = []&PCIDevice{}

	print('pci: Building device scan')
	mut root_bus := PCIDevice{}
	configc  := root_bus.read<u32>(0xc)

    if (configc & 0x800000) == 0 {
        check_bus(0, -1)
    } else {
        for function := byte(0); function < max_function; function++ {
            host_bridge := PCIDevice{
				bus: 0,
				slot: 0,
				function: function,
				parent: 0
			}
            config0 := host_bridge.read<u32>(0)
            if config0 == 0xffffffff {
                continue
            }

            check_bus(function, -1)
        }
    }
}

fn check_bus(bus byte, parent i64) {
    for dev := byte(0); dev < max_device; dev++ {
        for func := byte(0); func < max_function; func++ {
            check_function(bus, dev, func, parent)
        }
    }
}

fn check_function(bus byte, slot byte, function byte, parent i64) {
    mut device := &PCIDevice{
		bus: bus,
		slot: slot,
		function: function,
		parent: parent
	}
	device.read_info()
	if device.device_id == 0xffff && device.vendor_id == 0xffff {
		return
	}
	scanned_devices << device
	print('pci: Found [${device.bus:x}:${device.slot:x}:${device.function:x}:${device.parent:x}]\n')
	// TODO: Support bridges.
}

pub fn get_device_by_vendor(vendor_id u16, device_id u16) ?&PCIDevice {
	for device in scanned_devices {
		if device.vendor_id == vendor_id && device.device_id == device_id {
			return unsafe { device }
		}
	}
	return none
}

pub fn get_device_by_coordinates(bus byte, slot byte, function byte) ?&PCIDevice {
	for device in scanned_devices {
		if device.bus == bus
		&& device.slot == slot
		&& device.function == function {
			return unsafe { device }
		}
	}
	return none
}
