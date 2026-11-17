module g13contract

import g13layout

fn test_g13_release_policy_and_default_retention() {
 root := g13layout.repo_root()
 allocator := read(root + '/kernel/gpu/agx/alloc/alloc.v')!
 manager := read(root + '/kernel/gpu/agx/gpu/gpu.v')!
 check_heap_release_policy_local(allocator, manager)!
 for token in ['keep_garbage bool = true', 'heap.keep_garbage = keep_garbage',
  'if !h.keep_garbage { h.collect_garbage_locked(1) }'] {
  if _ := check_heap_release_policy_local(allocator.replace(token, 'false'), manager) { assert false, token }
 }
 for class in ['g13-shared', 'g13-readonly'] {
  start := manager.index("alloc.new_heap_with_garbage('" + class + "'") or { panic(class) }
  end := manager.index_after(', false)', start) or { panic(class) }
  changed := manager[..end] + manager[end..].replace_once(', false)', ', true)')
  if _ := check_heap_release_policy_local(allocator, changed) { assert false, class }
 }
}
