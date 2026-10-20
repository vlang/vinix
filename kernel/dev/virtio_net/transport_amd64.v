// QEMU's default transitional virtio-net-pci (1af4:1000), legacy BAR0.
// Modern-only 1af4:1041 and MMIO BARs are deliberately left unbound.
module virtio_net

import devcore
import dma
import pci
import socket.inet
import x86.kio

__global (
	virtio_net_io_base    u16
	virtio_net_pci_device &devcore.Device
)

fn dma_barrier() {
	asm volatile amd64 {
		mfence
		; ; ; memory
	}
}

fn dma_read16(address u64) u16 {
	return kio.mmin[u16](unsafe { &u16(address) })
}

fn dma_read32(address u64) u32 {
	return kio.mmin[u32](unsafe { &u32(address) })
}

fn transport_is_pci() bool {
	return true
}

fn transport_page_size() u64 {
	return 4096
}

fn alloc_dma(bytes u64) ?dma.Buffer {
	mut dev := virtio_net_pci_device
	return dma.alloc_buffer(mut dev, bytes)
}

fn free_dma(buffer dma.Buffer) {
	if buffer.bus != 0 {
		mut dev := virtio_net_pci_device
		dma.free_buffer(mut dev, buffer)
	}
}

fn transport_reset() bool {
	kio.port_out[u8](virtio_net_io_base + 18, 0)
	for _ in 0 .. 10000 {
		if kio.port_in[u8](virtio_net_io_base + 18) == 0 { return true }
	}
	return false
}

fn transport_disable() bool {
	if virtio_net_pci_device == unsafe { nil } { return true }
	card := virtio_net_pci_device.pci
	if !card.present() { return true }
	return card.update_command(4, 1 << 10) == pci.config_ok && card.read[u16](4) & 4 == 0
}

fn transport_status(value u8) {
	kio.port_out[u8](virtio_net_io_base + 18, value)
}

fn transport_features() u32 {
	return kio.port_in[u32](virtio_net_io_base)
}

fn transport_accept(value u32) {
	kio.port_out[u32](virtio_net_io_base + 4, value)
}

// MSI-X is disabled before these accesses, so device configuration is at 20.
fn transport_mac(index u64) u8 {
	return kio.port_in[u8](virtio_net_io_base + 20 + u16(index))
}

fn transport_queue_max(index u16) u32 {
	kio.port_out[u16](virtio_net_io_base + 14, index)
	if kio.port_in[u32](virtio_net_io_base + 8) != 0 { return 0 }
	return kio.port_in[u16](virtio_net_io_base + 12)
}

fn transport_queue_install(index u16, size u16, address u64) {
	kio.port_out[u16](virtio_net_io_base + 14, index)
	// Queue size at +12 is READ ONLY on legacy PCI.
	kio.port_out[u32](virtio_net_io_base + 8, legacy_pfn(address, transport_page_size()))
	_ = size
}

fn transport_notify(index u16) {
	kio.port_out[u16](virtio_net_io_base + 16, index)
}

fn transport_ack() {
	_ = kio.port_in[u8](virtio_net_io_base + 19)
}

fn card_matches(dev &devcore.Device) bool {
	return dev.bus == .pci && dev.pci != unsafe { nil }
		&& legacy_pci_net(dev.vendor, dev.device, dev.revision, dev.pci.header_type)
}

fn card_probe(mut dev devcore.Device) bool {
	if virtio_net_pci_device != unsafe { nil } || inet.owner() != inet.driver_none { return false }
	card := dev.pci
	bdf := (u32(card.bus) << 8) | (u32(card.slot) << 3) | card.function
	caps, cap_status := pci.capabilities_read(bdf, card.header_type, pci.native_topology_read)
	if cap_status != pci.topology_ok { return false }
	command := card.read[u16](4)
	if command == 0xffff || card.update_command(7, 1 << 10) != pci.config_ok { return false }
	bar := card.get_bar(0)
	if !legacy_io_bar(bar.base, bar.size, bar.is_mmio) {
		card.write[u16](4, command)
		return false
	}
	// No IRQ handler is installed. Disable message interrupts as well as
	// INTx, and request NO_INTERRUPT in both avail rings before DRIVER_OK.
	if caps.msi_offset != 0 {
		offset := u32(caps.msi_offset) + 2
		control := card.read[u16](offset)
		if control == 0xffff || card.config_write(offset, 2, control & ~u16(1)) != pci.config_ok
			|| card.read[u16](offset) & 1 != 0 {
			card.write[u16](4, command)
			return false
		}
	}
	if caps.msix_offset != 0 {
		offset := u32(caps.msix_offset) + 2
		control := card.read[u16](offset)
		if control == 0xffff
			|| card.config_write(offset, 2, (control & ~u16(0x8000)) | 0x4000) != pci.config_ok
			|| card.read[u16](offset) & 0x8000 != 0 {
			card.write[u16](4, command)
			return false
		}
	}
	virtio_net_io_base = u16(bar.base)
	virtio_net_pci_device = unsafe { dev }
	// A previous failed reset may have left stale PFNs in the device. Keep
	// bus mastering OFF until a reset has actually cleared them. Merely
	// disabling DMA during remove is not enough if a later bind enables it.
	if card.update_command(6, 1 | (1 << 10)) != pci.config_ok
		|| card.read[u16](4) & 7 != 1 || !transport_reset() {
		transport_disable()
		virtio_net_pci_device = unsafe { nil }
		virtio_net_io_base = 0
		return false
	}
	// All DMA buffers are identity-mapped through this device's domain.
	// Queue PFN is 32 bits; refuse any allocation outside its 44-bit reach.
	dma.set_address_bits(mut dev, 44)
	if card.update_command(2, 5 | (1 << 10)) != pci.config_ok || !start() {
		stop()
		free_queues()
		virtio_net_pci_device = unsafe { nil }
		virtio_net_io_base = 0
		return false
	}
	return true
}

fn card_remove(mut dev devcore.Device) {
	stop()
	inet.detach_owned(inet.driver_virtio)
	free_queues()
	virtio_net_pci_device = unsafe { nil }
	virtio_net_io_base = 0
	_ = dev
}

fn card_shutdown(mut dev devcore.Device) {
	stop()
	_ = dev
}

pub fn initialise(hhdm u64) {
	devcore.register_driver(devcore.Driver{
		name:     'virtio-net'
		bus:      .pci
		matches:  card_matches
		probe:    card_probe
		remove:   card_remove
		shutdown: card_shutdown
	}) or {}
	_ = hhdm
}
