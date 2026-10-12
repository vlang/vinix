// SPDX-License-Identifier: GPL-2.0-or-later
module rtl8169

const desc_owned = u32(1) << 31
const desc_end = u32(1) << 30
const desc_first = u32(1) << 29
const desc_last = u32(1) << 28
const rx_error = u32(1) << 21
const descriptors = u32(64)
const buffer_bytes = u64(2048)

// PCI 10ec:8168 covers many incompatible generations. Do not drive a new
// revision with an old revision's analog/PHY setup merely because its PCI ID
// matches. Linux r8169's XID is TxConfig[30:20], masked with 0x7cf.
fn chip_version(tx_config u32) int {
	xid := (tx_config >> 20) & 0x7cf
	return match xid {
		0x4c0 { 40 }
		0x509 { 42 }
		else { 0 }
	}
}

fn ring_end(index u32) u32 {
	return if index == descriptors - 1 { desc_end } else { u32(0) }
}

fn received_length(status u32) u64 {
	length := u64(status & 0x3fff)
	// CRC is present in Realtek RX buffers. Scatter receive is disabled:
	// reject partial, oversized and malformed frames before passing to lwIP.
	if status & (desc_owned | rx_error) != 0
		|| status & (desc_first | desc_last) != (desc_first | desc_last)
		|| length < 18 || length > buffer_bytes {
		return 0
	}
	return length - 4
}
