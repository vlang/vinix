// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

fn check_heap_pressure_local(source string, manager string) ! {
	require(source.contains('gc_on_pressure bool = true'), 'Legacy pressure policy stays the default')!
	constructor := section(source, 'pub fn new_heap_with_explicit_gc(', '\n}\n', 'Explicit heap GC policy')!
	require_order(constructor, ['mut heap := new_heap(name, start, end)', 'heap.gc_on_pressure = false', 'return heap'], 'Explicit heaps disable pressure GC at construction')!
	allocate := section(source, 'pub fn (mut h HeapAllocator) alloc(', '// Release the allocation', 'Pressure policy')!
	require_order(allocate, ['h.find_address_locked(h.end, aligned_size, actual_align) or {',
		'if !h.gc_on_pressure { return none }', 'h.gc_locked()',
		'h.find_address_locked(h.end, aligned_size, actual_align)'], 'Exhaustion cannot bypass explicit collection')!
	for class in ['g13_private', 'g13_gpu_readonly'] {
		require(manager.contains(class + ': alloc.new_heap_with_explicit_gc('), 'Both firmware-private classes require explicit GC')!
	}
	require(manager.count('alloc.new_heap_with_explicit_gc(') == 2, 'Only the two firmware-private classes change pressure policy')!
}

fn check_heap_pressure_reference(source string) ! {
	allocate := section(source, 'fn alloc(&mut self, size: usize, align: usize) -> Result<HeapAllocation>', 'fn garbage(&self)', 'Asahi heap allocation failure')!
	require_order(allocate, ['let ret = self.alloc_inner(size, align)', 'if ret.is_err()', 'ret'], 'Asahi returns placement failure to the caller')!
	require(!allocate.contains('collect_garbage('), 'Asahi allocation does not collect pending ranges on pressure')!
}
