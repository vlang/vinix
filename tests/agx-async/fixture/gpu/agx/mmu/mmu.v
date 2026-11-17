module mmu

pub struct UatContext {
pub mut:
	id u32 = 1
	inflight u64
	detached bool
}
