module g13contract

import g13layout

fn test_firmware_heap_pressure_requires_explicit_collection() {
	root := g13layout.repo_root()
	source := read(root + '/kernel/gpu/agx/alloc/alloc.v')!
	manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
	check_heap_pressure_local(source, manager)!
	for token in ['gc_on_pressure bool = true', 'heap.gc_on_pressure = false', 'if !h.gc_on_pressure { return none }'] {
		if _ := check_heap_pressure_local(source.replace(token, ''), manager) { assert false, token }
	}
	for class in ['g13_private', 'g13_gpu_readonly'] {
		if _ := check_heap_pressure_local(source, manager.replace(class + ': alloc.new_heap_with_explicit_gc(', class + ': alloc.new_heap(')) { assert false, class }
	}
}
