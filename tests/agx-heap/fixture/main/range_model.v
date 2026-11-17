module main

import gpu.agx.alloc

struct ModelReservation {
 va u64
 size u64
mut:
 in_use bool = true
}

struct ModelHole {
 start u64
 end u64
}

struct HeapRangeModel {
 start u64
 end u64
mut:
 records []ModelReservation
 holes []ModelHole // Oldest first, independently of VA order
}

fn new_range_model(start u64, end u64) HeapRangeModel {
 mut model := HeapRangeModel{start: start, end: end, records: []ModelReservation{cap: 16}}
 model.records.flags |= .noslices
 model.holes.flags |= .noslices
 if start < end { model.holes << ModelHole{start, end} }
 return model
}

// Enumerate aligned candidate addresses, independently of the production
// sorted-record walk. Infer each candidate's containing hole by pairwise
// interval comparisons. A chronological hole list models DRM MM's equal-size
// tree order without the production recency ranks.
fn (model &HeapRangeModel) slot(size u64, alignment u64) (bool, u64, u64) {
 valid, initial, rounded := heap_bounds_model(model.start, model.end, size, alignment)
 if !valid { return false, 0, 0 }
 step := if alignment < alloc.gpu_page_size { alloc.gpu_page_size } else { alignment }
 mut candidate := initial
 mut found := false
 mut best := u64(0)
 mut best_span := ~u64(0)
 mut best_age := -1
 for candidate <= model.end && rounded <= model.end - candidate {
  mut left := model.start
  mut right := model.end
  mut fits := true
  for record in model.records {
   if record.va + record.size <= candidate {
    if record.va + record.size > left { left = record.va + record.size }
   } else if record.va >= candidate + rounded {
    if record.va < right { right = record.va }
   } else { fits = false; break }
  }
  mut age := -1
  for index, hole in model.holes { if hole.start == left && hole.end == right { age = index } }
  if fits { assert age >= 0, 'independent containing interval must be a tracked hole' }
  if fits && (!found || right - left < best_span || (right - left == best_span && age > best_age)) {
   found = true; best = candidate; best_span = right - left; best_age = age
  }
  if candidate > ~u64(0) - step { break }
  candidate += step
 }
 return found, best, rounded
}

fn (mut model HeapRangeModel) reserve(size u64, alignment u64) (u64, u64) {
 mut valid, mut address, mut rounded := model.slot(size, alignment)
 if !valid {
  model.collect()
  valid, address, rounded = model.slot(size, alignment)
 }
 assert valid, 'range model reservation must fit'
 mut selected := -1
 for index, hole in model.holes { if address >= hole.start && address + rounded <= hole.end { selected = index; break } }
 assert selected >= 0
 hole := model.holes[selected]
 model.holes.delete(selected)
 if hole.start < address { model.holes << ModelHole{hole.start, address} }
 if address + rounded < hole.end { model.holes << ModelHole{address + rounded, hole.end} }
 model.records << ModelReservation{va: address, size: rounded}
 return address, rounded
}

fn (mut model HeapRangeModel) release(address u64) {
 for mut record in model.records { if record.va == address { record.in_use = false; return } }
}

fn (mut model HeapRangeModel) collect() {
 // Match the production collector's descending-VA removal stream, while
 // reservations stay in creation order in this independent model.
 for {
  mut selected := -1
  mut highest := u64(0)
  for index, record in model.records {
   if !record.in_use && (selected < 0 || record.va > highest) { selected = index; highest = record.va }
  }
  if selected < 0 { break }
  record := model.records[selected]
  mut left := model.start
  mut right := model.end
  for other in model.records {
   if other.va + other.size <= record.va && other.va + other.size > left { left = other.va + other.size }
   if other.va >= record.va + record.size && other.va < right { right = other.va }
  }
  mut index := model.holes.len - 1
  for index >= 0 {
   hole := model.holes[index]
   if hole.end == record.va || hole.start == record.va + record.size { model.holes.delete(index) }
   index--
  }
  model.records.delete(selected)
  model.holes << ModelHole{left, right}
 }
}

fn (model &HeapRangeModel) top() u64 {
 mut top := model.start
 for record in model.records { if record.va + record.size > top { top = record.va + record.size } }
 return top
}

fn record_at(heap &alloc.HeapAllocator, address u64) &alloc.Allocation {
 for record in heap.allocations { if record.va == address { return record } }
 panic('missing allocation record')
}

fn (model &HeapRangeModel) hole_rank(start u64, end u64) u64 {
 if start == end { return 0 }
 for index, hole in model.holes { if hole.start == start && hole.end == end { return u64(index + 1) } }
 panic('missing chronological model hole')
}

fn check_model_hole_orders(heap &alloc.HeapAllocator, model &HeapRangeModel) {
 $if agx_heap_history_invariants ? {
  assert heap.hole_count == u64(model.holes.len) && heap.hole_count <= u64(heap.allocations.len) + 1,
   'hole ranks must remain bounded by current holes'
  first := if heap.allocations.len == 0 { heap.end } else { heap.allocations[0].va }
  assert heap.head_hole_order == model.hole_rank(heap.start, first), 'head rank must match chronological hole history'
  for index, record in heap.allocations {
   end := if index + 1 == heap.allocations.len { heap.end } else { heap.allocations[index + 1].va }
   assert record.hole_order == model.hole_rank(record.va + record.size, end),
    'following rank must match chronological hole history'
  }
 }
}

fn reserve_checked(mut heap alloc.HeapAllocator, mut model HeapRangeModel, size u64, alignment u64) u64 {
 expected, rounded := model.reserve(size, alignment)
 address := heap.alloc(size, alignment) or { panic('production range reservation must fit') }
 assert address == expected && heap.top == model.top(), 'GPU range placement must match candidate-enumeration model'
 assert record_at(heap, address).size == rounded && heap.allocations.len == model.records.len
 check_model_hole_orders(heap, model)
 mut previous_end := heap.start
 for record in heap.allocations {
  assert record.va >= previous_end && record.size <= heap.end - record.va,
   'GPU allocation records must remain sorted and nonoverlapping'
  previous_end = record.va + record.size
 }
 return address
}
