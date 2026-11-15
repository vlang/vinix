// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_vm_geometry_local(vm string, mmu string) ! {
	exact_line(vm, 'pub const driver_page_size = u64(0x8000)', 'Vinix driver allocation granule')!
	window := section(vm, 'pub fn driver_window(', 'pub fn valid_window(', 'Vinix driver window')!
	require_order(window, ['if !valid_window(kernel_start, kernel_end) { return none }',
		'mask := driver_page_size - 1', 'start := (kernel_start + mask) & ~mask',
		'end := kernel_end & ~mask', 'if start >= end { return none }',
		'half := ((end - start) >> 1) & ~mask', 'midpoint: start + half'], 'Vinix normalized driver window')!
	create := section(mmu, 'pub fn (mut mgr UatManager) create_context(',
		'pub fn (mut mgr UatManager) destroy_context(', 'Vinix native driver window')!
	require_order(create, ['window := agxvm.driver_window(kernel_start, kernel_end)',
		'mgr.lock.acquire()', 'kernel_start: window.start', 'kernel_end: window.end',
		"gpu_alloc.new_heap('uat-user-gpu', window.start, window.midpoint)",
		"gpu_alloc.new_heap('uat-user-private', window.midpoint, window.end)"], 'Vinix native driver window')!
	allocate := section(mmu, 'pub fn (mut ctx UatContext) alloc_driver_buffer_aligned(',
		'// Convert a cached driver allocation', 'Vinix driver alignment')!
	require_order(allocate, ['actual_alignment := if alignment < agxvm.driver_page_size { agxvm.driver_page_size } else { alignment }',
		'if size > ~u64(0) - (actual_alignment - 1) { return none }',
		'aligned_size := (size + actual_alignment - 1) & ~(actual_alignment - 1)',
		'memory.pmm_alloc_aligned_fallible', 'ctx.driver_private.alloc(aligned_size, actual_alignment)',
		'ctx.driver_gpu.alloc(aligned_size, actual_alignment)'], 'Vinix minimum driver alignment with checked rounding')!
}

fn check_vm_geometry_reference(file string, buffer string, allocator string) ! {
	exact_line(buffer, 'pub(crate) const PAGE_SHIFT: usize = 15;', 'Asahi driver page shift')!
	exact_line(buffer, 'pub(crate) const PAGE_SIZE: usize = 1 << PAGE_SHIFT;', 'Asahi driver allocation granule')!
	create := section(file, '    pub(crate) fn vm_create(',
		'    /// IOCTL: vm_destroy:', 'Asahi native driver window')!
	require_order(create, ['// Validate requested kernel range', 'kernel_range.range() < VM_KERNEL_MIN_SIZE',
		'let kernel_range = align(kernel_range.start, buffer::PAGE_SIZE as u64)',
		'..align_down(kernel_range.end, buffer::PAGE_SIZE as u64)',
		'let kernel_half_size = align_down(kernel_range.range() >> 1, buffer::PAGE_SIZE as u64)',
		'let kernel_gpu_range = kernel_range.start..(kernel_range.start + kernel_half_size)',
		'let kernel_gpufw_range = kernel_gpu_range.end..kernel_range.end',
		'kernel_gpu_range,', 'buffer::PAGE_SIZE,', 'kernel_gpufw_range,', 'buffer::PAGE_SIZE,'], 'Asahi normalized driver window and minimum alignment')!
	require_order(allocator, ['fn alloc_inner(', 'let align = self.min_align.max(align)',
		'let size_aligned = (size + align - 1) & !(align - 1)'], 'Asahi heap minimum alignment')!
}
