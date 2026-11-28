module virtio_net

fn test_probe_is_only_transitional_net_with_legacy_io() {
	assert legacy_pci_net(0x1af4, 0x1000, 0, 0)
	assert !legacy_pci_net(0x1af4, 0x1041, 1, 0)
	assert !legacy_pci_net(0x1af4, 0x1001, 0, 0)
	assert !legacy_pci_net(0xffff, 0xffff, 0xff, 0xff)
	assert !legacy_pci_net(0x1af4, 0x1000, 1, 0)
	assert !legacy_pci_net(0x1af4, 0x1000, 0, 1)
	assert legacy_io_bar(0xc000, 32, false)
	assert legacy_io_bar(0xffe0, 32, false)
	assert !legacy_io_bar(0, 32, false)
	assert !legacy_io_bar(0xc000, 32, true)
	assert !legacy_io_bar(0xc000, 16, false)
	assert !legacy_io_bar(0xfff0, 32, false)
	assert !legacy_io_bar(0x10000, 32, false)
}

fn test_pci_uses_entire_advertised_ring_or_refuses_it() {
	assert queue_size(256, true) == 256
	assert queue_size(1024, true) == 1024
	assert queue_size(2048, true) == 0
	assert queue_size(32768, true) == 0
	assert queue_size(0, true) == 0
	assert queue_size(255, true) == 0
	assert queue_size(65536, true) == 0
	assert queue_size(256, false) == 64
	assert queue_size(32, false) == 32
	assert queue_size(0, false) == 0
	assert queue_size(63, false) == 0
}

fn test_ring_layout_and_legacy_pfn_boundary() {
	assert used_offset(64) == 4096
	assert used_offset(256) == 8192
	assert used_offset(1024) == 20480
	assert ring_bytes(256) == 10246
	assert legacy_dma_ring(4096, ring_bytes(256), 4096)
	assert !legacy_dma_ring(0, 4096, 4096)
	assert !legacy_dma_ring(4097, 4096, 4096)
	assert legacy_dma_ring(u64(1) << 32, 4096, 4096)
	assert legacy_dma_ring((u64(1) << 44) - 4096, 4096, 4096)
	assert !legacy_dma_ring(u64(1) << 44, 4096, 4096)
	assert !legacy_dma_ring((u64(1) << 44) - 4096, 4097, 4096)
	assert !legacy_dma_ring(4096, 0, 4096)
}

fn test_mmio_pfn_uses_negotiated_16k_pages() {
	assert legacy_pfn(0x80000000, 16384) == 0x20000
	assert legacy_pfn(0x80000000, 4096) == 0x80000
	assert legacy_dma_ring(16384, ring_bytes(64), 16384)
	assert !legacy_dma_ring(4096, ring_bytes(64), 16384)
	assert legacy_dma_ring(u64(1) << 44, 4096, 16384)
	assert legacy_dma_ring((u64(1) << 46) - 16384, 16384, 16384)
	assert !legacy_dma_ring(u64(1) << 46, 16384, 16384)
	assert !legacy_dma_ring(16384, 4096, 0)
}

fn test_completion_wrap_bounds_and_rx_validation() {
	assert completion_count(0, 256, 256) == 256
	assert completion_count(65534, 2, 256) == 4
	assert completion_count(0, 257, 256) == 0
	assert completion_count(10, 9, 256) == 0
	assert valid_rx(255, 256, 24)
	assert valid_rx(0, 256, 2048)
	assert !valid_rx(256, 256, 64)
	assert !valid_rx(0x10000, 256, 64)
	assert !valid_rx(0xffffffff, 256, 64)
	assert !valid_rx(1, 256, 23)
	assert !valid_rx(1, 256, 2049)
}
