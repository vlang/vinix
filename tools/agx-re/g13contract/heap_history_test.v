// SPDX-License-Identifier: GPL-2.0-or-later
module g13contract

import g13layout

fn test_heap_history_source_gates() {
 source := read(g13layout.repo_root() + '/kernel/gpu/agx/alloc/alloc.v')!
 check_heap_bounds_local(source) or { panic(err) }
 for pair in [
  ['span == best_span && order > best_order', 'false'],
  ['h.head_hole_order--', 'h.head_hole_order++'],
  ['record.hole_order--', 'record.hole_order++'],
  ['h.hole_count--', 'h.hole_count++'],
  ['hole_order: trailing_order', 'hole_order: leading_order'],
 ] {
  changed := source.replace(pair[0], pair[1])
  assert changed != source
  if _ := check_heap_bounds_local(changed) { assert false, pair[0] }
 }
}
