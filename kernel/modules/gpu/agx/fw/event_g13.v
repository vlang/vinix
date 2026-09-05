module fw

// G13 v12.3 notifier objects shared by all native subqueues belonging to one
// DRM queue. The linked-list head is self-linked through `next`, matching the
// reference firmware builder; `prev` remains null until firmware links it.

@[packed]
pub struct G13LinkedListHead {
pub mut:
	prev u64
	next u64
}

@[packed]
pub struct G13NotifierList {
pub mut:
	list_head G13LinkedListHead
	unk_10   u64
}

@[packed]
pub struct G13NotifierState {
pub mut:
	unk_14       u32
	unk_18       u64
	unk_20       u32
	vm_slot      u32
	has_vertex   u32
	stamp_vertex [4]u64
	has_fragment u32
	stamp_fragment [4]u64
	has_compute  u32
	stamp_compute [4]u64
	in_list      u32
	list_head    G13LinkedListHead
}

@[packed]
pub struct G13Notifier {
pub mut:
	threshold  u64
	generation u32
	cur_count  u32
	unk_10     u32
	state      G13NotifierState
}

pub fn validate_g13_event_layouts() bool {
	return sizeof(G13LinkedListHead) == 0x10 && sizeof(G13NotifierList) == 0x18
		&& sizeof(G13NotifierState) == 0x94 && sizeof(G13Notifier) == 0xa8
}
