module rtl8169

import devcore
import dma
import socket.inet

fn setup(version int) {
	assert dma.live == 0
	regs = [256]u8{}
	phy = [32768]u16{}
	mac = [32768]u16{}
	ephy = [32]u16{}
	eri = [256]u32{}
	fail_port = 0xffff
	stuck_reset = false
	dma.allocated = 0
	dma.fail_at = -1
	inet.attached = false
	inet.accept_attach = true
	inet.received = 0
	phy_writes = 0
	regs[0] = 2
	regs[5] = 1
	regs[0xd3] = 0x82 // firmware OOB receiver, FIFO ready
	regs[0x6c] = 2
	regs[0x54] = 0x86 // inherited L2/L3 and jumbo enable; preserve other bits
	raw_write32(0x40, if version == 40 { u32(0x4c000000) } else { u32(0x50900000) })
}

fn test_identifies_silicon_instead_of_claiming_all_8168_cards() {
	assert chip_version(0x4c000000) == 40
	assert chip_version(0x50900000) == 42
	assert chip_version(0x50900700) == 42
	assert chip_version(0x54100000) == 0
	assert chip_version(0xffffffff) == 0
}

fn test_rx_rejects_errors_fragments_and_invalid_dma_lengths() {
	good := desc_first | desc_last | u32(64)
	assert received_length(good) == 60
	for status in [good | desc_owned, good | rx_error, desc_first | u32(64), desc_last | u32(64),
		desc_first | desc_last | u32(17), desc_first | desc_last | u32(2049)] {
		assert received_length(status) == 0
	}
}

fn test_both_revisions_boot_transmit_receive_wrap_reset_and_remove() {
	for version in [40, 42] {
		setup(version)
		mut dev := devcore.Device{}
		assert card_probe(mut dev)
		assert rtl_ready && inet.attached && rtl_version == version
		assert dev.pci.command & 4 != 0
		assert regs[0xd3] & 0x80 == 0
		assert regs[0x54] == 0x80
		assert ephy[0x0c] == 0x0820
		assert read32(0) == 2 && read16(4) == 0x100
		if version == 40 { assert eri[0x1a8 / 4] & 0xfc000000 == 0xfc000000 }
		assert phy_writes > 80 // actual bundled microcode executed
		assert phy[0xa400 / 2] == 0x1200
		assert read32(0x20) == u32(rtl_tx_ring.bus)
		assert read32(0xe4) == u32(rtl_rx_ring.bus)
		assert rtl_rx_ring.bus != rtl_rx_ring.virt
		mut frame := [60]u8{}
		for i in 0 .. 14 { frame[i] = u8(i + 1) }
		for i := u32(0); i < descriptors; i++ {
			assert send(unsafe { &frame[0] }, 14) == 0
			assert descriptor_status(rtl_tx_ring.virt + u64(i) * 16) == desc_owned | desc_first | desc_last | ring_end(i) | 60
			unsafe {
				assert *&u8(rtl_tx_buffers.virt + u64(i) * buffer_bytes + 13) == 14
				assert *&u8(rtl_tx_buffers.virt + u64(i) * buffer_bytes + 59) == 0
			}
		}
		assert send(unsafe { &frame[0] }, 60) == -1
		set_descriptor_status(rtl_tx_ring.virt, desc_first | desc_last | 60)
		assert send(unsafe { &frame[0] }, 60) == 0 // ring wraps after completion
		for index := u32(0); index < descriptors; index++ {
			set_descriptor_status(rtl_rx_ring.virt + u64(index) * 16, desc_first | desc_last | ring_end(index) | 64)
		}
		poll()
		assert inet.received == int(descriptors) && inet.last_length == 60
		assert rtl_rx_next == 0
		assert descriptor_status(rtl_rx_ring.virt + u64(descriptors - 1) * 16) == desc_owned | desc_end | u32(buffer_bytes)
		assert card_suspend(mut dev)
		assert send(unsafe { &frame[0] }, 60) == -1
		assert dev.pci.command & 4 == 0
		assert card_resume(mut dev)
		assert card_reset(mut dev)
		card_remove(mut dev)
		assert dma.live == 0 && !rtl_ready && !inet.attached
		poll() // no access to freed rings
	}
}

fn test_failed_probe_releases_dma_and_stops_bus_mastering() {
	for allocation in 0 .. 4 {
		setup(42)
		dma.fail_at = allocation
		mut dev := devcore.Device{}
		assert !card_probe(mut dev)
		assert dma.live == 0 && dev.pci.command & 4 == 0
	}
	for port in [u64(0x74), 0x80, 0xb8] {
		setup(42)
		fail_port = port
		mut dev := devcore.Device{}
		assert !card_probe(mut dev)
		assert dma.live == 0 && !rtl_ready && dev.pci.command & 4 == 0
	}
	setup(42)
	stuck_reset = true
	mut dev := devcore.Device{}
	assert !card_probe(mut dev)
	assert dma.live == 0 && dev.pci.command & 4 == 0
	setup(42)
	inet.accept_attach = false
	assert !card_probe(mut dev)
	assert dma.live == 0 && !rtl_ready && rtl_device == unsafe { nil }
}

fn test_unready_fifo_fails_without_dma_or_stack_attachment() {
	setup(42)
	regs[0xd3] = 0x80
	mut dev := devcore.Device{}
	assert !card_probe(mut dev)
	assert dma.live == 0 && !inet.attached
}

fn test_firmware_rejects_unsupported_opcodes_branches_and_unbounded_loops() {
	setup(42)
	for code in [[u32(0x60000000)]!, [u32(0x30010000)]!, [u32(0x40000002)]!, [u32(0xd0010000)]!,
		[u32(0x30000000)]!] {
		assert !apply_firmware(unsafe { &code[0] }, code.len)
	}
}
