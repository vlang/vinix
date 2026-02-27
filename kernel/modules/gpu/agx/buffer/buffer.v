@[has_globals]
module buffer

// Tiled Vertex Buffer (TVB) and parameter buffer management
// The TVB holds intermediate tiling data during vertex processing.
// The parameter buffer stores per-tile vertex output and scene descriptors.
// Translates buffer.rs from the Asahi Linux GPU driver.

import klock
import lib
import memory

pub struct TvbManager {
pub mut:
	block_size  u64
	block_count u32
	base_addr   u64 // GPU VA of TVB region
	phys_addr   u64
	total_size  u64
	free_blocks []u32 // free block indices
	lock        klock.Lock
}

pub struct ParamBufferManager {
pub mut:
	base_addr    u64
	phys_addr    u64
	total_size   u64
	alloc_offset u64 // next allocation offset
	lock         klock.Lock
}

// Scene buffer for a render pass
pub struct SceneBuffer {
pub mut:
	tvb_blocks   []u32 // allocated TVB block indices
	param_offset u64   // offset into parameter buffer
	param_size   u64
	width        u32
	height       u32
	tile_w       u32
	tile_h       u32
}

// Create a new TVB manager. The TVB region is divided into fixed-size
// blocks that can be individually allocated and freed.
pub fn new_tvb_manager(base u64, phys u64, block_size u64, block_count u32) TvbManager {
	mut free := []u32{cap: int(block_count)}
	for i := u32(0); i < block_count; i++ {
		free << i
	}

	return TvbManager{
		block_size:  block_size
		block_count: block_count
		base_addr:   base
		phys_addr:   phys
		total_size:  block_size * u64(block_count)
		free_blocks: free
	}
}

// Allocate `count` contiguous TVB blocks. Returns the block indices,
// or none if not enough free blocks are available.
pub fn (mut tm TvbManager) alloc_blocks(count u32) ?[]u32 {
	tm.lock.acquire()
	defer {
		tm.lock.release()
	}

	if u32(tm.free_blocks.len) < count {
		C.printf(c'tvb: not enough free blocks (need %d, have %d)\n',
			count, tm.free_blocks.len)
		return none
	}

	mut allocated := []u32{cap: int(count)}
	for _ in 0 .. count {
		block := tm.free_blocks.last()
		tm.free_blocks.delete_last()
		allocated << block
	}

	return allocated
}

// Return blocks to the free pool.
pub fn (mut tm TvbManager) free_blocks(blocks []u32) {
	tm.lock.acquire()
	defer {
		tm.lock.release()
	}

	for b in blocks {
		if b < tm.block_count {
			tm.free_blocks << b
		}
	}
}

// Create a new parameter buffer manager for the given memory region.
// Allocations are served linearly from the base address and can be
// reset after each frame completes.
pub fn new_param_manager(base u64, phys u64, size u64) ParamBufferManager {
	return ParamBufferManager{
		base_addr:    base
		phys_addr:    phys
		total_size:   size
		alloc_offset: 0
	}
}

// Allocate space from the parameter buffer. Returns the GPU virtual
// address of the allocation, or none if the buffer is exhausted.
// Allocations are 16-byte aligned.
pub fn (mut pm ParamBufferManager) alloc(size u64) ?u64 {
	pm.lock.acquire()
	defer {
		pm.lock.release()
	}

	aligned_offset := lib.align_up(pm.alloc_offset, 16)
	if aligned_offset + size > pm.total_size {
		C.printf(c'param buffer: out of space (need 0x%llx, avail 0x%llx)\n',
			size, pm.total_size - aligned_offset)
		return none
	}

	va := pm.base_addr + aligned_offset
	pm.alloc_offset = aligned_offset + size

	return va
}

// Reset the parameter buffer allocator. Called after a frame has
// completed and all parameter data from the previous frame is no
// longer needed.
pub fn (mut pm ParamBufferManager) reset() {
	pm.lock.acquire()
	defer {
		pm.lock.release()
	}

	pm.alloc_offset = 0
}

// Create a new scene buffer descriptor for a render pass with the
// given framebuffer dimensions and tile sizes.
pub fn new_scene(width u32, height u32, tile_w u32, tile_h u32) SceneBuffer {
	return SceneBuffer{
		width:  width
		height: height
		tile_w: tile_w
		tile_h: tile_h
	}
}

// Return the total number of tiles in the scene.
pub fn (s &SceneBuffer) tile_count() u32 {
	if s.tile_w == 0 || s.tile_h == 0 {
		return 0
	}
	tiles_x := (s.width + s.tile_w - 1) / s.tile_w
	tiles_y := (s.height + s.tile_h - 1) / s.tile_h
	return tiles_x * tiles_y
}
