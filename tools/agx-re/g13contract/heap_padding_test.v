module g13contract

import g13layout

fn test_heap_gc_restores_reservation_frontier_without_moving_live_prefixes() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_metadata_local(source)!
 for token in ['h.top = if idx == 0 { h.start } else {',
  'previous := h.allocations[idx - 1]', 'previous.va + previous.size'] {
  if _ := check_heap_metadata_local(source.replace(token, '')) { assert false, token }
 }
 for pair in [['idx == 0', 'idx == 1'], ['previous.va + previous.size', 'previous.va'],
  ['if !a.in_use && a.release_order == 1 { break }', 'if true { break }']] {
  if _ := check_heap_metadata_local(source.replace(pair[0], pair[1])) { assert false, pair[0] }
 }
}
