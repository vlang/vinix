module g13contract

import g13layout

fn test_heap_gc_visits_released_records_below_live_owners() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_metadata_local(source)!
 for replacement in ['if !a.in_use && a.release_order == 1 && a.va + a.size == h.top { break }',
  'if a.in_use { return }\n\t\tif !a.in_use && a.release_order == 1 { break }', 'if true { break }'] {
  if _ := check_heap_metadata_local(source.replace('if !a.in_use && a.release_order == 1 { break }', replacement)) { assert false, replacement }
 }
 if _ := check_heap_metadata_local(source.replace('idx++', 'idx += 2')) { assert false }
}
