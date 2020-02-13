module libtinyalloc

// V port of tinyalloc https://github.com/thi-ng/tinyalloc
struct Block {
mut:
	addr voidptr
	next &Block
	size u64
}

struct Heap {
mut:
	free &Block // first free block
	used   &Block // first used block
	fresh  &Block // first available block
	top    u64 // top free address
}

pub struct TinyAlloc {
mut:
	heap         Heap
	limit        voidptr
	split_thresh u64
	alignment    u64
	max_blocks   u64
}

pub fn new_alloc(base voidptr, limit voidptr, heap_blocks u64, split_thresh u64, alignment u64) &TinyAlloc {
	mut alloc := &TinyAlloc(base)
	alloc.limit = limit
	alloc.split_thresh = split_thresh
	alloc.alignment = alignment
	alloc.max_blocks = heap_blocks

	alloc.heap.free = &Block(0)
	alloc.heap.used = &Block(0)
	alloc.heap.fresh = &Block(voidptr(u64(&alloc.heap) + sizeof(Heap) + sizeof(Block)))
	alloc.heap.top = u64(alloc.heap.fresh) + heap_blocks * sizeof(Block)
	
	mut block := alloc.heap.fresh
	mut i := alloc.max_blocks - 1
	for i-- != 0 {
		block.next = &Block(voidptr(u64(block) + sizeof(Block)))
		block++
	}
	block.next = &Block(0)

	return alloc
}

pub fn (alloc mut TinyAlloc) free(addr voidptr) bool {
	mut block := alloc.heap.used
	mut prev := &Block(0)
	for block != &Block(0) {
		if (addr == block.addr) {
			if (prev != &Block(0)) {
				prev.next = block.next
			} else {
				alloc.heap.used = block.next
			}

			alloc.insert_block(block)
			alloc.compact()

			return true
		}
		prev = block
		block = block.next
	}

	return false
}

pub fn (alloc mut TinyAlloc) alloc(size u64) voidptr {
	block := alloc.alloc_block(size)
	if (block != &Block(0)) {
		return block.addr
	}

	return voidptr(0)
}

pub fn (alloc mut TinyAlloc) free_blocks_count() int {
	return count_blocks(alloc.heap.free)
}

pub fn (alloc mut TinyAlloc) used_blocks_count() int {
	return count_blocks(alloc.heap.free)
}

pub fn (alloc mut TinyAlloc) fresh_blocks_count() int {
	return count_blocks(alloc.heap.free)
}

fn (alloc mut TinyAlloc) alloc_block(size u64) &Block {
	mut ptr := alloc.heap.free
	mut prev := &Block(0)
	top := alloc.heap.top
	num := u64((size + alloc.alignment - 1) & -(alloc.alignment))

	for ptr != &Block(0) {
		is_top := ((u64(ptr.addr) + ptr.size) >= top) && (u64(ptr.addr) + num <= alloc.limit)
		if is_top || ptr.size >= num {
			if prev != &Block(0) {
				prev.next = ptr.next
			} else {
				alloc.heap.free = ptr.next
			}

			ptr.next = alloc.heap.used
			alloc.heap.used = ptr

			if is_top {
				// resize top block
				ptr.size = num
				alloc.heap.top = u64(ptr.addr) + num
			} else if alloc.heap.fresh != &Block(0) {
				excess := ptr.size - num
				if excess >= alloc.split_thresh {
					ptr.size = num
					
					mut split := alloc.heap.fresh
					alloc.heap.fresh = split.next

					split.addr = voidptr(u64(ptr.addr) + num)
					split.size = excess
					alloc.insert_block(split)
					alloc.compact()
				}
			}

			return ptr
		}

		prev = ptr
		ptr = ptr.next
	}

	// no matching free blocks
	new_top := top + num
	if alloc.heap.fresh != &Block(0) && new_top <= u64(alloc.limit) {
		ptr = alloc.heap.fresh
		alloc.heap.fresh = ptr.next
		ptr.addr = voidptr(top)
		ptr.next = alloc.heap.used
		ptr.size = num
		alloc.heap.used = ptr
		alloc.heap.top = new_top
		return ptr
	}

	return &Block(0)
}

fn (alloc mut TinyAlloc) insert_block(block_ &Block) {
	mut block := block_
	mut ptr := alloc.heap.free
	mut prev := &Block(0)
	for ptr != &Block(0) {
		if u64(block.addr) <= u64(ptr.addr) {
			// insert
			break
		}
		prev = ptr
		ptr = ptr.next
	}
	if prev != &Block(0) {
		// new tail if ptr = null
		prev.next = block
	}
	else {
		// new head
		alloc.heap.free = block
	}
	block.next = ptr
}

fn (alloc mut TinyAlloc) release_blocks(scan_ &Block, to &Block) {
	mut scan := scan_
	mut scan_next := &Block(0)
	for scan != to {
		scan_next = scan.next
		scan.next = alloc.heap.fresh
		alloc.heap.fresh = scan
		scan.addr = voidptr(0)
		scan.size = u64(0)
		scan = scan_next
	}
}

fn (alloc mut TinyAlloc) compact() {
	mut ptr := alloc.heap.free
	mut prev := &Block(0)
	mut scan := &Block(0)
	for ptr != &Block(0) {
		prev = ptr
		scan = ptr.next
		for scan != &Block(0) && voidptr(u64(prev.addr) + prev.size) == scan.addr {
			prev = scan
			scan = scan.next
		}
		if prev != ptr {
			new_size := u64(prev.addr) - u64(ptr.addr) + prev.size
			ptr.size = new_size
			next := prev.next
			alloc.release_blocks(ptr.next, prev.next)
			ptr.next = next
		}
		ptr = ptr.next
	}
}

[inline]
fn count_blocks(start &Block) int {
	mut num := 0
	mut ptr := start

	for ptr != &Block(0) {
		num++
		ptr = ptr.next
	}

	return num
}