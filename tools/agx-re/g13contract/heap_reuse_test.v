module g13contract

import g13layout

fn test_best_fit_owns_ordered_ranges_and_preserves_the_high_frontier() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_bounds_local(source)!
 for token in ['span < best_span', 'cursor = record.va + record.size',
  'if va + aligned_size > h.top', 'h.allocations[index] = h.allocations[index - 1]',
  'h.allocations[index] = a'] {
  if _ := check_heap_bounds_local(source.replace(token, 'false')) { assert false, token }
 }
}
