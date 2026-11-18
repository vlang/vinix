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
	va u64
	size u64
}

fn (buffer &SharedBuffer) cpu_address() voidptr { return voidptr(buffer.phys) }

struct G13TailPointerCache {
mut:
	references u32
}

struct G13QueueResources {
mut:
	render_buffer G13RenderBufferResources
}

struct Allocator {}
fn (mut allocator Allocator) gc() {}

struct GpuManager {
mut:
	hw_config     hw.HwConfig
	flushes       int
	fail_flush_at int = -1
	shared_allocations int
	shared_releases int
	fail_shared_at int = -1
	g13_tvb_slots [127]bool
	g13_private Allocator
	g13_shared Allocator
}

fn (mut mgr GpuManager) alloc_g13_shared_buffer(size u64) ?SharedBuffer {
	if mgr.shared_allocations == mgr.fail_shared_at { return none }
	mgr.shared_allocations++
	storage := unsafe { C.malloc(size + 1) }
	assert storage != unsafe { nil }
	unsafe { C.memset(storage, 0xa5, size + 1) }
	return SharedBuffer{phys: u64(storage), va: 0x500000 + u64(mgr.shared_allocations) * 0x4000, size: size}
}

fn (mut mgr GpuManager) alloc_g13_buffer_with_protection(size u64, protection u64) ?SharedBuffer {
	assert protection == 1
	return mgr.alloc_g13_shared_buffer(size)
}

fn (mut mgr GpuManager) free_shared_buffer(mut buffer SharedBuffer) {
	if buffer.phys == 0 { return }
	unsafe { C.free(voidptr(buffer.phys)) }
	buffer = SharedBuffer{}
	mgr.shared_releases++
}

fn (mut mgr GpuManager) release_g13_tpc_locked(mut context mmu.UatContext, cache &G13TailPointerCache) {
	assert cache == unsafe { nil }, 'no scene exists during queue initialization'
}

__global observed_control &fw.G13BufferBlockControl = unsafe { nil }
__global observed_pages &u32 = unsafe { nil }
__global observed_blocks &u32 = unsafe { nil }
__global expected_count u32
__global uat_mgr = unsafe { &mmu.UatManager(nil) }

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
	index := mgr.flushes
	mgr.flushes++
	return index != mgr.fail_flush_at
}

fn check_growth(abi hw.FirmwareAbi, fail_alloc int, fail_map int, metadata_fail bool, active bool) {
	mut pages := [64]u32{init: 0xdeadbeef}
	mut blocks := [32]u32{init: 0xdeadbeef}
	mut info := [256]u8{}
	mut control := fw.G13BufferBlockControl{}
	mut context := mmu.UatContext{ fail_at: fail_alloc, fail_map_at: fail_map, check: unpublished }
	mut page_buffer := mmu.UatBuffer{ phys: unsafe { u64(&pages) }, size: sizeof(pages) }
	mut block_buffer := mmu.UatBuffer{ phys: unsafe { u64(&blocks) }, size: sizeof(blocks) }
	mut buffer := G13RenderBufferResources{
		initialized: true
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
	mut mgr := GpuManager{ hw_config: hw.HwConfig{ firmware_abi: abi }, fail_flush_at: 0 }
	memory.fail_next(metadata_fail)
	result := mgr.ensure_g13_tvb_blocks(mut buffer, 8, active)
	memory.fail_next(false)
	assert mgr.flushes == 0, 'GPU-only TVB growth must not request a firmware flush'
	if fail_alloc >= 0 || fail_map >= 0 || metadata_fail {
		assert !result
		assert context.map_failures == if fail_map >= 0 { 1 } else { 0 }
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
	context.fail_map_at = context.allocated + 2
	assert !mgr.ensure_g13_tvb_blocks(mut buffer, 12, active)
	unpublished()
	assert buffer.blocks.len == 8 && context.released == 3 && context.map_failures == 1
	assert info == before
	for i in 0 .. 8 {
		assert blocks[i * 2] == u32(buffer.blocks[i].va >> 15)
	}
	context.fail_map_at = -1
	assert mgr.ensure_g13_tvb_blocks(mut buffer, 12, active)
	assert buffer.blocks.len == 12 && control.total == 12 && control.wptr == 12
	assert mgr.flushes == 0
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
			check_growth(abi, -1, fail, false, true)
		}
		check_growth(abi, -1, -1, true, false)
		check_growth(abi, -1, -1, false, false)
		check_growth(abi, -1, -1, false, true)
		for fail in 0 .. 10 {
			check_initialization(abi, fail, -1, -1, false, true)
			check_initialization(abi, -1, -1, fail, false, true)
		}
		for fail in 0 .. 5 { check_initialization(abi, -1, fail, -1, false, true) }
		check_initialization(abi, -1, -1, -1, true, true)
		check_initialization(abi, -1, -1, -1, false, true)
		check_initialization(abi, -1, -1, -1, false, false)
	}
	println('AGX TVB growth: both ABIs, every allocation and mapping failure, atomic extension and firmware-owned counters passed')
	println('AGX initial TVB: eight blocks before any scene, bound and dormant VMs grow without firmware flushes and unwind all failures')
	check_teardown_after_first_bind()
}

fn check_teardown_after_first_bind() {
	mut uat := mmu.UatManager{current: true}
	uat_mgr = unsafe { &uat }
	defer { uat_mgr = unsafe { nil } }
	mut mgr := GpuManager{ fail_flush_at: 0 }
	mut context := mmu.UatContext{ id: 17, bound: false }
	mut buffer := mmu.UatBuffer{ va: 0x100000, size: 0x20000, mapped: true, cache_flush_pending: true }
	// A later kernel-buffer failure can retain this graph until another
	// queue publishes the same VM. Keep its private PTE available for retry.
	assert mgr.invalidate_g13_driver_buffer(mut context, &buffer)
	assert buffer.mapped && buffer.cache_flush_pending && !buffer.uncached && mgr.flushes == 0
	context.bound = true
	assert !mgr.invalidate_g13_driver_buffer(mut context, &buffer)
	assert buffer.mapped && buffer.cache_flush_pending && buffer.uncached && mgr.flushes == 1
	assert mgr.invalidate_g13_driver_buffer(mut context, &buffer)
	assert !buffer.mapped && !buffer.cache_flush_pending && mgr.flushes == 2
	println('AGX private TVB: retained dormant PTE survives first bind and a failed flush, then releases on retry')

	buffer = mmu.UatBuffer{va: 0x100000, size: 0x20000, mapped: true, cache_flush_pending: true}
	uat.available = false
	assert !mgr.invalidate_g13_driver_buffer(mut context, &buffer)
	assert buffer.mapped && buffer.cache_flush_pending && buffer.uncached && mgr.flushes == 2
	uat.available = true
	uat.current = false
	assert mgr.invalidate_g13_driver_buffer(mut context, &buffer)
	assert !buffer.mapped && !buffer.cache_flush_pending && mgr.flushes == 2
	assert mgr.invalidate_g13_driver_buffer(mut context, &buffer)
	assert mgr.flushes == 2

	buffer = mmu.UatBuffer{va: 0x100000, size: 0x20000, mapped: true, uncached: true}
	uat.available = false
	assert mgr.invalidate_g13_driver_buffer(mut context, &buffer)
	assert !buffer.mapped && mgr.flushes == 2
	println('AGX user driver teardown: unavailable, inactive, uncached and already-unmapped buffers preserve the FwCtl contract')
}

fn tvb_record_matches(buffer &SharedBuffer, expected &[0x40]u8) bool {
	data := buffer.cpu_address()
	return buffer.size == 0x40 && unsafe { C.memcmp(data, expected, 0x40) == 0 && (&u8(data))[0x40] == 0xa5 }
}

fn check_initialization(abi hw.FirmwareAbi, fail_alloc int, fail_shared int, fail_map int, metadata_fail bool, bound bool) {
	mut config := hw.t8103_config()
	config.firmware_abi = abi
	mut mgr := GpuManager{hw_config: config, fail_shared_at: fail_shared, fail_flush_at: 0}
	mut context := mmu.UatContext{id: 17, fail_at: fail_alloc, fail_map_at: fail_map, bound: bound}
	mut resources := G13QueueResources{}
	memory.fail_next(metadata_fail)
	ok := mgr.initialize_g13_render_buffer(mut resources, &context)
	memory.fail_next(false)
	assert mgr.flushes == 0
	if fail_alloc >= 0 || fail_shared >= 0 || fail_map >= 0 || metadata_fail {
		assert !ok
		assert context.map_failures == if fail_map >= 0 { 1 } else { 0 }
		assert !resources.render_buffer.initialized && resources.render_buffer.info.phys == 0
		assert resources.render_buffer.blocks.len == 0
	} else {
		buffer := &resources.render_buffer
		assert ok && buffer.initialized && buffer.blocks.len == 8
		assert !buffer.slot_reserved && buffer.active_scenes == 0 && buffer.tail_pointer_cache == unsafe { nil }
		mut control := [0x40]u8{}
		control[0] = 8
		control[4] = 8
		mut stats := [0x40]u8{}
		stats[0x20] = 1
		empty := [0x40]u8{}
		assert tvb_record_matches(&buffer.block_control, unsafe { &control }), 'TVB initial block control bytes'
		assert tvb_record_matches(&buffer.counter, unsafe { &empty }), 'TVB initial counter bytes'
		assert tvb_record_matches(&buffer.stats, unsafe { &stats }), 'TVB initial statistics bytes'
		assert tvb_record_matches(&buffer.kernel_buffer, unsafe { &empty }), 'TVB initial kernel buffer bytes'
		assert context.allocated == 10 && mgr.shared_allocations == 5
		// The initial non-active counters agree with the block table rather
		// than waiting until the first frame to populate firmware state.
		mut expected := []u8{len: int(buffer.info.size)}
		unsafe { C.memcpy(expected.data, buffer.info.cpu_address(), buffer.info.size) }
		assert fw.update_g13_buffer_info_counts(expected.data, abi, 32, 8, 31)
		assert unsafe { C.memcmp(expected.data, buffer.info.cpu_address(), buffer.info.size) } == 0
		unsafe { expected.free() }
		mgr.free_g13_render_buffer_locked(mut resources.render_buffer)
	}
	assert context.allocated == context.released && mgr.shared_allocations == mgr.shared_releases
}
