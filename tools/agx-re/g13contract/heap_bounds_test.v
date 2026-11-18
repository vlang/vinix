module g13contract

import g13layout

fn test_heap_bounds_require_checked_alignment_and_identical_post_gc_validation() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_bounds_local(source)!
 for token in ['value > ~u64(0) - mask', 'address > end || size > end - address',
  'size == 0 || (align != 0 && (align & (align - 1)) != 0)',
  'checked_heap_align_up(size, actual_align) or { return -22, 0 }'] {
  if _ := check_heap_bounds_local(source.replace(token, 'false')) { assert false, token }
 }
 token := '\n\t\th.find_address_locked(h.end, aligned_size, actual_align) or {'
 assert source.count(token) == 1
 if _ := check_heap_bounds_local(source.replace(token, token.replace('h.end', '~u64(0)'))) { assert false }
}
