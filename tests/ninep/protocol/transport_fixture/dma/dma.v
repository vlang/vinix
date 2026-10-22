module dma

pub struct Buffer {
pub:
	virt  u64
	bus   u64
	bytes u64
}
