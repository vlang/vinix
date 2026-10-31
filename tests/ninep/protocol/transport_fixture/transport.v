@[has_globals]
module virtio_9p

import dma

__global (
	fixture_mode   int
	fixture_frees  int
	fixture_resets int
)

fn (ch &Channel) barrier() {}

fn (ch &Channel) read16(address u64) u16 { return unsafe { *&u16(address) } }

fn (ch &Channel) read32(address u64) u32 { return unsafe { *&u32(address) } }

fn (ch &Channel) page_size() u64 { return 4096 }

fn (mut _ Channel) alloc_dma(bytes u64) ?dma.Buffer {
	// Aligned but real owned memory; the original allocation is kept directly
	// before the aligned address so free_dma can release exactly once.
	raw := unsafe { malloc(int(bytes + 4096)) }
	aligned := (u64(raw) + 4095 + 8) & ~u64(4095)
	unsafe { *&u64(aligned - 8) = u64(raw) }
	return dma.Buffer{ virt: aligned, bus: aligned, bytes: bytes }
}

fn (mut _ Channel) free_dma(buffer dma.Buffer) {
	if buffer.bus == 0 { return }
	fixture_frees++
	unsafe { free(voidptr(*&u64(buffer.virt - 8))) }
}

fn (ch &Channel) set_status(_ u8) {}

fn (ch &Channel) features() u32 { return 1 }

fn (ch &Channel) accept(_ u32) {}

fn (ch &Channel) notify() {
	if fixture_mode == 1 || fixture_mode == 2 { return }
	unsafe {
		*&u32(ch.used + 4 + u64(ch.consumed % ch.size) * 8) = if fixture_mode == 3 {
			u32(2)
		} else {
			u32(0)
		}
		*&u32(ch.used + 8 + u64(ch.consumed % ch.size) * 8) = if fixture_mode == 4 {
			u32(65537)
		} else {
			u32(7)
		}
		*&u16(ch.used + 2) = ch.consumed + 1
	}
}

fn (ch &Channel) ack() {}

fn (ch &Channel) queue_max() u32 { return 128 }

fn (ch &Channel) install(_ u64) {}

fn (ch &Channel) reset() bool {
	fixture_resets++
	return fixture_mode != 2
}

fn (ch &Channel) disable() {}

fn (mut ch Channel) locate(_ string) bool { return true }
