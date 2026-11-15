module g13contract

import g13layout
import os

fn test_vm_geometry_rejects_16k_normalization_missing_rounding_checks_and_heap_drift() {
	root := g13layout.repo_root()
	vm := os.read_file(root + '/kernel/gpu/agx/vm/vm.v')!
	mmu := os.read_file(root + '/kernel/gpu/agx/mmu/mmu.v')!
	check_vm_geometry_local(vm, mmu)!
	for token in ['driver_page_size = u64(0x8000)', 'if !valid_window(kernel_start, kernel_end) { return none }',
		'start := (kernel_start + mask) & ~mask', 'half := ((end - start) >> 1) & ~mask'] {
		if _ := check_vm_geometry_local(vm.replace(token, ''), mmu) { assert false, token }
	}
	for token in ['window := agxvm.driver_window(kernel_start, kernel_end)', 'kernel_end: window.end',
		"gpu_alloc.new_heap('uat-user-private', window.midpoint, window.end)",
		'if size > ~u64(0) - (actual_alignment - 1) { return none }',
		'ctx.driver_gpu.alloc(aligned_size, actual_alignment)'] {
		if _ := check_vm_geometry_local(vm, mmu.replace(token, '')) { assert false, token }
	}
}

fn test_reference_vm_geometry_rejects_allocator_and_page_size_drift() {
	buffer := 'pub(crate) const PAGE_SHIFT: usize = 15;\npub(crate) const PAGE_SIZE: usize = 1 << PAGE_SHIFT;\n'
	file := '    pub(crate) fn vm_create(\n// Validate requested kernel range\n' +
		'kernel_range.range() < VM_KERNEL_MIN_SIZE\n' +
		'let kernel_range = align(kernel_range.start, buffer::PAGE_SIZE as u64)\n' +
		'..align_down(kernel_range.end, buffer::PAGE_SIZE as u64);\n' +
		'let kernel_half_size = align_down(kernel_range.range() >> 1, buffer::PAGE_SIZE as u64);\n' +
		'let kernel_gpu_range = kernel_range.start..(kernel_range.start + kernel_half_size);\n' +
		'let kernel_gpufw_range = kernel_gpu_range.end..kernel_range.end;\n' +
		'kernel_gpu_range,\nbuffer::PAGE_SIZE,\nkernel_gpufw_range,\nbuffer::PAGE_SIZE,\n' +
		'    /// IOCTL: vm_destroy:'
	allocator := 'fn alloc_inner(\nlet align = self.min_align.max(align);\nlet size_aligned = (size + align - 1) & !(align - 1);'
	check_vm_geometry_reference(file, buffer, allocator)!
	if _ := check_vm_geometry_reference(file, buffer.replace('= 15', '= 14'), allocator) { assert false }
	if _ := check_vm_geometry_reference(file.replace('let kernel_half_size = align_down', ''), buffer, allocator) { assert false }
	if _ := check_vm_geometry_reference(file, buffer, allocator.replace('self.min_align.max(align)', 'align')) { assert false }
}
