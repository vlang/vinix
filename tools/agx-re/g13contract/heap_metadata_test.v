module g13contract

import g13layout

fn test_heap_metadata_requires_released_ownership_and_reader_serialization() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_metadata_local(source)!
 for token in ['h.allocations.delete(idx)', 'unsafe { free(a) }', 'if !a.in_use && a.release_order == 1 { break }',
  'pub fn (mut h HeapAllocator) used()', 'pub fn (mut h HeapAllocator) available()', '} @[freed]'] {
  if _ := check_heap_metadata_local(source.replace(token, '')) { assert false, token }
 }
 if _ := check_heap_metadata_local(source.replace('h.allocations.delete(idx)', 'unsafe { free(a) }\nh.allocations.delete(idx)')) { assert false }
 if _ := check_heap_metadata_local(source.replace('if !h.keep_garbage { h.collect_garbage_locked(1) }',
  'unsafe { free(a) }\nif !h.keep_garbage { h.collect_garbage_locked(1) }')) { assert false }
}
