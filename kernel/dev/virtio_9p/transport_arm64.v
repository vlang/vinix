// SPDX-License-Identifier: GPL-2.0-or-later
// QEMU virt legacy MMIO v1 only. Modern MMIO v2 is explicitly rejected.
module virtio_9p

import aarch64.cpu
import aarch64.kio
import dma
import memory

fn (ch &Channel) rd(offset u64) u32 { return kio.mmin32(unsafe { &u32(ch.base + offset) }) }

fn (ch &Channel) wr(offset u64, value u32) { kio.mmout32(unsafe { &u32(ch.base + offset) }, value) }

fn (ch &Channel) barrier() { cpu.dmb_sy() }

fn (ch &Channel) read16(address u64) u16 { return kio.mmin[u16](unsafe { &u16(address) }) }

fn (ch &Channel) read32(address u64) u32 { return kio.mmin32(unsafe { &u32(address) }) }

fn (ch &Channel) page_size() u64 { return memory.page_size }

fn (mut ch Channel) alloc_dma(bytes u64) ?dma.Buffer {
	pages := (bytes + memory.page_size - 1) / memory.page_size
	phys := u64(memory.pmm_alloc_fallible(pages))
	if phys == 0 { return none }
	return dma.Buffer{ virt: phys + memory.get_hhdm_offset(), bus: phys, bytes: bytes }
}

fn (mut ch Channel) free_dma(buffer dma.Buffer) {
	if buffer.bus != 0 {
		memory.pmm_free(voidptr(buffer.bus), (buffer.bytes + memory.page_size - 1) / memory.page_size)
	}
}

fn (ch &Channel) set_status(value u8) { ch.wr(0x070, value) }

fn (ch &Channel) features() u32 {
	ch.wr(0x014, 0)
	return ch.rd(0x010)
}

fn (ch &Channel) accept(value u32) {
	ch.wr(0x024, 0)
	ch.wr(0x020, value)
	ch.wr(0x028, u32(memory.page_size))
}

fn (ch &Channel) notify() { ch.wr(0x050, 0) }

fn (ch &Channel) ack() { ch.wr(0x064, ch.rd(0x060)) }

fn (ch &Channel) queue_max() u32 { return ch.rd(0x034) }

fn (ch &Channel) install(address u64) {
	ch.wr(0x030, 0)
	ch.wr(0x038, ch.size)
	ch.wr(0x03c, 4096)
	ch.wr(0x040, u32(address / memory.page_size))
}

fn (ch &Channel) reset() bool {
	if ch.base == 0 { return true }
	ch.wr(0x070, 0)
	for _ in 0 .. 10000 { if ch.rd(0x070) == 0 { return true } }
	return false
}

fn (ch &Channel) disable() {}

fn (mut ch Channel) locate(tag string) bool {
	for slot in 0 .. 32 {
		base := memory.map_mmio(0x0a000000 + u64(slot) * 0x200, 0x200)
		if base == 0 { continue }
		if transport_claimed(0, base) { continue }
		ch.base = base
		if ch.rd(0) != 0x74726976 || ch.rd(4) != 1 || ch.rd(8) != 9 {
			ch.base = 0
			continue
		}
		if ch.features() & 1 == 0 {
			ch.base = 0
			continue
		}
		length := ch.read16(base + 0x100)
		if int(length) != tag.len || length > 254 {
			ch.base = 0
			continue
		}
		mut good := true
		for i in 0 .. int(length) {
			if kio.mmin[u8](unsafe { &u8(base + 0x102 + u64(i)) }) != tag[i] {
				good = false
				break
			}
		}
		if good {
			ch.wr(0x030, 0)
			return true
		}
		ch.base = 0
	}
	return false
}
