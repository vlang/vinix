@[has_globals]
module mmu

import gpu.agx.pgtable
import gpu.agx.vm as agxvm
import klock
import memory

pub const uat_num_contexts = 64
pub const uat_unknown_page = agxvm.user_end

pub struct UatManager {
pub mut:
	contexts [uat_num_contexts]&UatContext
	ias u32 = 39
	oas u32 = 40
	lock klock.Lock
}

pub fn (manager &UatManager) unbind_context(context &UatContext) {
	assert context.active && voidptr(manager.contexts[context.id]) == voidptr(context)
}

pub fn run_checks() {
	for granule in [u64(0x4000), 0x1000]! {
		memory.set_page_size(granule)
		check_contexts()
	}
	println('AGX VM allocator: 400 native contexts and 2400 shared/private allocations across 16 KiB and 4 KiB PMM granules; one zeroed UAT page of dummy backing per context, alignment, map failures and final release passed')
}

fn check_contexts() {
	mut manager := UatManager{}
	for index in 0 .. uat_num_contexts { manager.contexts[index] = unsafe { nil } }
	base := u64(0x100000000)
	for cycle in 0 .. 200 {
		start := base + u64(cycle % 2) * 0x4000
		end := start + agxvm.kernel_min_size + u64(cycle % 5) * 0x4000
		window := agxvm.driver_window(start, end) or { panic('window') }
		mut context := manager.create_context(start, end) or { panic('context') }
		assert context.id == 1 && context.active && context.identity != 0
		assert context.kernel_start == window.start && context.kernel_end == window.end
		assert context.driver_gpu.start == window.start && context.driver_gpu.end == window.midpoint
		assert context.driver_private.start == window.midpoint && context.driver_private.end == window.end
		assert context.pgtable.last_address == uat_unknown_page && context.pgtable.last_size == 0x4000
		assert context.pgtable.last_protection == pgtable.gpu_prot_gpu_shared_rw
		assert context.dummy_phys != 0 && context.pgtable.last_physical == context.dummy_phys
		assert memory.backing_size(context.dummy_phys) == 0x4000, 'dummy mapping must own exactly one UAT page'
		assert memory.active() == 1
		for offset in 0 .. int(pgtable.uat_pgsz) {
			assert unsafe { (&u8(context.dummy_phys))[offset] } == 0
		}
		for private in [false, true]! {
			for alignment in [u64(0x4000), 0x8000, 0x10000]! {
				requested := u64(cycle % 3) * 0x4000 + 1
				buffer := if alignment == 0x4000 {
					context.alloc_driver_buffer(requested, private) or { panic('default buffer') }
				} else {
					context.alloc_driver_buffer_aligned(requested, private, alignment) or { panic('aligned buffer') }
				}
				actual := if alignment < 0x8000 { u64(0x8000) } else { alignment }
				assert buffer.va % actual == 0 && buffer.size == (requested + actual - 1) / actual * actual
				assert buffer.private == private && context.pgtable.last_size == buffer.size
				assert buffer.protection == if private { pgtable.gpu_prot_fw_gpu_cached_rw } else { pgtable.gpu_prot_gpu_shared_rw }
				assert buffer.va >= if private { window.midpoint } else { window.start }
				assert buffer.va + buffer.size <= if private { window.end } else { window.midpoint }
				assert (if private { context.driver_private.last_alignment } else { context.driver_gpu.last_alignment }) == actual
				context.release_driver_buffer(buffer)
				assert memory.active() == 1 && context.driver_buffers.len == 0
			}
		}
		calls := memory.calls()
		for size in [u64(0), ~u64(0), ~u64(0) - 0x5000]! {
			if _ := context.alloc_driver_buffer(size, false) { panic('invalid/overflowing size') }
		}
		for alignment in [u64(0), 0x2000, 0x6000]! {
			if _ := context.alloc_driver_buffer_aligned(1, false, alignment) { panic('invalid alignment') }
		}
		if _ := context.alloc_driver_buffer_aligned(~u64(0) - 0x9000, false, 0x10000) { panic('strong alignment overflow') }
		assert memory.calls() == calls
		memory.fail_next()
		if _ := context.alloc_driver_buffer(1, false) { panic('physical OOM') }
		for private in [false, true]! {
			if private { context.driver_private.reject_next = true } else { context.driver_gpu.reject_next = true }
			if _ := context.alloc_driver_buffer(1, private) { panic('VA OOM') }
			context.pgtable.reject_next = true
			if _ := context.alloc_driver_buffer(1, private) { panic('map failure') }
			assert memory.active() == 1 && context.driver_buffers.len == 0
		}
		context.active = false
		if _ := context.alloc_driver_buffer(1, false) { panic('inactive VM') }
		context.active = true
		manager.destroy_context(context)
		assert !context.active && context.dummy_phys == 0 && manager.contexts[1] == unsafe { nil }
		// Production retains context metadata after destroy. Fixture cleanup is
		// safe after this final synchronous call; all buffers were released.
		unsafe { context.driver_buffers.free(); free(context) }
		assert memory.active() == 0 && pgtable.active() == 0
	}
	for failure in 0 .. 3 {
		match failure { 0 { pgtable.fail_new() } 1 { memory.fail_next() } else { pgtable.fail_dummy() } }
		if _ := manager.create_context(base, base + agxvm.kernel_min_size) { panic('constructor failure') }
		assert memory.active() == 0 && pgtable.active() == 0 && manager.contexts[1] == unsafe { nil }
	}
	before := pgtable.calls()
	if _ := manager.create_context(base + 1, base + agxvm.kernel_min_size) { panic('invalid window') }
	assert pgtable.calls() == before
}
