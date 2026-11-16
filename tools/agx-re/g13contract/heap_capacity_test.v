module g13contract

import g13layout

fn test_heap_table_owns_its_buffer_before_any_growth() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_metadata_local(source)!
 token := 'heap.allocations.flags |= .noslices'
 for replacement in ['', 'heap.allocations.flags |= .nofree'] {
  if _ := check_heap_metadata_local(source.replace(token, replacement)) {
   assert false, replacement
  }
 }
 pair := token + '\n\treturn heap'
 assert source.count(pair) == 1
 if _ := check_heap_metadata_local(source.replace(pair, 'return heap\n\t' + token)) { assert false }
}
