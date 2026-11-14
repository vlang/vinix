@[has_globals]
module gpu

import gpu.agx.fw
import gpu.agx.hw
import gpu.agx.mmu
import memory

#include <stdio.h>
#define kprintf printf

fn C.kprintf(format &char, ...) i32

struct SharedBuffer {
mut:
	phys u64
	size u64
}

fn (buffer &SharedBuffer) cpu_address() voidptr { return voidptr(buffer.phys) }

struct G13RenderBufferResources {
mut:
	initialized   bool            = true
	context       &mmu.UatContext = unsafe { nil }
	info          SharedBuffer
	page_list     &mmu.UatBuffer = unsafe { nil }
	block_list    &mmu.UatBuffer = unsafe { nil }
	block_control SharedBuffer
	blocks        []&mmu.UatBuffer
}

struct GpuManager {
mut:
	hw_config     hw.HwConfig
	flushes       int
	fail_flush_at int = -1
}

__global observed_control &fw.G13BufferBlockControl = unsafe { nil }
__global observed_pages &u32 = unsafe { nil }
__global observed_blocks &u32 = unsafe { nil }
__global expected_count u32

fn unpublished() {
	assert observed_control.total == expected_count && observed_control.wptr == expected_count
	for i := expected_count * 4; i < 64; i++ {
		assert unsafe { observed_pages[i] } == 0xdeadbeef
	}
	for i := expected_count * 2; i < 32; i++ {
		assert unsafe { observed_blocks[i] } == 0xdeadbeef
	}
}

fn (mut mgr GpuManager) flush_g13_uat_range(slot u32, address u64, size u64) bool {
	assert slot == 1 && address % 0x8000 == 0 && size == 0x20000
	unpublished()
	index := mgr.flushes
	mgr.flushes++
	return index != mgr.fail_flush_at
}

fn check_growth(abi hw.FirmwareAbi, fail_alloc int, fail_flush int, metadata_fail bool, active bool) {
	mut pages := [64]u32{init: 0xdeadbeef}
	mut blocks := [32]u32{init: 0xdeadbeef}
	mut info := [256]u8{}
	mut control := fw.G13BufferBlockControl{}
	mut context := mmu.UatContext{ fail_at: fail_alloc, check: unpublished }
	mut page_buffer := mmu.UatBuffer{ phys: unsafe { u64(&pages) }, size: sizeof(pages) }
	mut block_buffer := mmu.UatBuffer{ phys: unsafe { u64(&blocks) }, size: sizeof(blocks) }
	mut buffer := G13RenderBufferResources{
		context:       &context
		info:          SharedBuffer{ phys: unsafe { u64(&info) }, size: sizeof(info) }
		page_list:     &page_buffer
		block_list:    &block_buffer
		block_control: SharedBuffer{ phys: unsafe { u64(&control) }, size: sizeof(control) }
	}
	assert fw.update_g13_buffer_info_counts(unsafe { &info[0] }, abi, 0, 0, 0)
	observed_control = &control
	observed_pages = unsafe { &pages[0] }
	observed_blocks = unsafe { &blocks[0] }
	expected_count = 0
	mut mgr := GpuManager{ hw_config: hw.HwConfig{ firmware_abi: abi }, fail_flush_at: fail_flush }
	memory.fail_next(metadata_fail)
	result := mgr.ensure_g13_tvb_blocks(mut buffer, 8, active)
	memory.fail_next(false)
	if fail_alloc >= 0 || fail_flush >= 0 || metadata_fail {
		assert !result
		unpublished()
		assert buffer.blocks.len == 0 && context.allocated == context.released
		assert info.all(it == 0)
		return
	}
	assert result && buffer.blocks.len == 8 && control.total == 8 && control.wptr == 8
	assert context.allocated == 8 && context.released == 0
	for i in 0 .. 8 {
		page := u32(buffer.blocks[i].va >> 15)
		assert blocks[i * 2] == page && blocks[i * 2 + 1] == 0xdeadbeef
		for j in 0 .. 4 {
			assert pages[i * 4 + j] == page + u32(j)
		}
	}
	if active {
		// Apart from BlockControl, firmware-owned Info must stay byte exact.
		assert info.all(it == 0)
	} else {
		mut expected := [256]u8{}
		assert fw.update_g13_buffer_info_counts(unsafe { &expected[0] }, abi, 32, 8, 31)
		assert info == expected
	}
	// A second extension must retain the committed prefix on failure.
	expected_count = 8
	before := info
	memory.fail_next(true)
	assert !mgr.ensure_g13_tvb_blocks(mut buffer, 12, active)
	memory.fail_next(false)
	assert buffer.blocks.len == 8 && info == before
	context.fail_at = context.allocated + 2
	assert !mgr.ensure_g13_tvb_blocks(mut buffer, 12, active)
	unpublished()
	assert buffer.blocks.len == 8 && context.released == 2
	assert info == before
	for i in 0 .. 8 {
		assert blocks[i * 2] == u32(buffer.blocks[i].va >> 15)
	}
	context.fail_at = -1
	assert mgr.ensure_g13_tvb_blocks(mut buffer, 12, active)
	assert buffer.blocks.len == 12 && control.total == 12 && control.wptr == 12
	assert !mgr.ensure_g13_tvb_blocks(mut buffer, 17, active), 'page table capacity must be checked before allocation'
	for block in buffer.blocks { context.release_driver_buffer(block) }
	assert context.released == context.allocated
	unsafe { buffer.blocks.free() }
}

pub fn run_checks() {
	for abi in [hw.FirmwareAbi.v12_3, .v13_5_partial] {
		for fail in 0 .. 8 {
			check_growth(abi, fail, -1, false, false)
			check_growth(abi, -1, fail, false, false)
		}
		check_growth(abi, -1, -1, true, false)
		check_growth(abi, -1, -1, false, false)
		check_growth(abi, -1, -1, false, true)
	}
	println('AGX TVB growth: both ABIs, every allocation/flush failure, atomic extension and firmware-owned counters passed')
}
