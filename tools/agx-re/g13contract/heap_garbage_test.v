module g13contract

import g13layout

fn test_heap_garbage_bounds_fifo_and_accounting() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_metadata_local(source)!
 for token in ['count < h.garbage_count', 'a.release_order == 1', 'h.garbage_count++',
  'h.garbage_count--', 'a.release_order = h.garbage_count', 'h.garbage_bytes += a.size',
  'h.garbage_bytes -= a.size', 'pending.release_order--', 'h.collect_garbage_locked(count)',
  'return h.garbage_count, h.garbage_bytes'] {
  changed := source.replace(token, 'false')
  assert changed != source
  if _ := check_heap_metadata_local(changed) { assert false, token }
 }
}
