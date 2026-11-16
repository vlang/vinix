module g13contract

import g13layout

fn test_heap_gc_visits_released_records_below_live_owners() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_metadata_local(source)!
 for replacement in ['if !a.in_use && a.va + a.size == h.top {',
  'if a.in_use { break }\n\t\tif !a.in_use {', 'if true {'] {
  if _ := check_heap_metadata_local(source.replace('if !a.in_use {', replacement)) { assert false, replacement }
 }
 if _ := check_heap_metadata_local(source.replace('idx--', 'idx -= 2')) { assert false }
}
