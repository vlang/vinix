module alloc

struct Allocation {
mut:
	address u64
	size u64
	live bool
}

pub struct HeapAllocator {
pub mut:
	start u64
	end u64
	top u64
	last_alignment u64
	reject_next bool
	allocations []Allocation
}

pub fn new_heap(_name string, start u64, end u64) HeapAllocator {
	assert start < end && start % 0x8000 == 0 && end % 0x8000 == 0
	return HeapAllocator{ start: start, end: end, top: start }
}

pub fn (mut heap HeapAllocator) alloc(size u64, alignment u64) ?u64 {
	heap.last_alignment = alignment
	if heap.reject_next { heap.reject_next = false; return none }
	address := (heap.top + alignment - 1) & ~(alignment - 1)
	if address > heap.end || size > heap.end - address { return none }
	if heap.allocations.len == 0 {
		heap.allocations = []Allocation{len: 16}
	}
	for index in 0 .. heap.allocations.len {
		if !heap.allocations[index].live {
			heap.allocations[index] = Allocation{ address: address, size: size, live: true }
			heap.top = address + size
			return address
		}
	}
	return none
}

pub fn (mut heap HeapAllocator) release(address u64) {
	for index in 0 .. heap.allocations.len {
		if heap.allocations[index].live && heap.allocations[index].address == address {
			heap.allocations[index].live = false
			return
		}
	}
	assert false, 'release of unknown GPU VA'
}

pub fn (mut heap HeapAllocator) gc() {
	mut top := heap.start
	for record in heap.allocations {
		if record.live && record.address + record.size > top { top = record.address + record.size }
	}
	heap.top = top
}
