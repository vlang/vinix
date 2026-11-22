// SPDX-License-Identifier: GPL-2.0-or-later
module drm

import lib

fn size_line(size u64) string {
	mut text := lib.new_text(64)
	add_fdinfo_size(mut text, 'total', 'system', size)
	return lib.finish_text(text)
}

fn client_text(driver string, client u64, stats MemoryStats) string {
	mut text := lib.new_text(256)
	add_client_lines(mut text, driver, client)
	add_memory_stats(mut text, stats, 'system')
	return lib.finish_text(text)
}

pub fn run_checks() {
	// drm_fdinfo_print_size(): a unit only while the size divides evenly,
	// and never beyond MiB.
	assert size_line(0) == 'drm-total-system:\t0\n'
	assert size_line(1023) == 'drm-total-system:\t1023\n'
	assert size_line(1024) == 'drm-total-system:\t1 KiB\n'
	assert size_line(1536) == 'drm-total-system:\t1536\n'
	assert size_line(1025 * 1024) == 'drm-total-system:\t1025 KiB\n'
	assert size_line(u64(1) << 20) == 'drm-total-system:\t1 MiB\n'
	assert size_line(u64(3) << 30) == 'drm-total-system:\t3072 MiB\n'
	assert size_line(~u64(0)) == 'drm-total-system:\t18446744073709551615\n'

	// What Asahi prints for a G13 client: private memory that is all
	// resident, nothing shared, and no purgeable or active keys.
	asahi := client_text('asahi', 7, MemoryStats{
		private:   48 << 20
		resident:  48 << 20
		supported: memory_stats_resident
	})
	assert asahi == 'drm-driver:\tasahi\ndrm-client-id:\t7\ndrm-total-system:\t48 MiB\ndrm-shared-system:\t0\ndrm-resident-system:\t48 MiB\n'
	// Every optional key, in drm_print_memory_stats() order.
	every := client_text('virtio_gpu', 1, MemoryStats{
		shared:    4096
		private:   8192
		active:    1024
		resident:  2048
		supported: memory_stats_resident | memory_stats_purgeable | memory_stats_active
	})
	assert every == 'drm-driver:\tvirtio_gpu\ndrm-client-id:\t1\ndrm-total-system:\t12 KiB\ndrm-shared-system:\t4 KiB\ndrm-active-system:\t1 KiB\ndrm-resident-system:\t2 KiB\ndrm-purgeable-system:\t0\n'

	mut dma_buf := lib.new_text(64)
	add_dma_buf_lines(mut dma_buf, 16384, 2)
	assert lib.finish_text(dma_buf) == 'size:\t16384\ncount:\t2\nexp_name:\tdrm\n'

	println('DRM fdinfo: Linux size units, client and DMA-BUF formatting, G13 and full memory keys passed')
}
