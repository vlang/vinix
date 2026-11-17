module main

import gpu.agx.alloc

struct ModelReservation {
 va u64
 size u64
mut:
 in_use bool = true
}

struct HeapRangeModel {
 start u64
 end u64
mut:
 records []ModelReservation
}

fn new_range_model(start u64, end u64) HeapRangeModel {
 mut model := HeapRangeModel{start: start, end: end, records: []ModelReservation{cap: 16}}
 model.records.flags |= .noslices
 return model
}

// Enumerate aligned candidate addresses, independently of the production
// sorted-record walk. Infer each candidate's containing hole by pairwise
// interval comparisons, then rank the complete hole and lowest address.
fn (model &HeapRangeModel) slot(size u64, alignment u64) (bool, u64, u64) {
 valid, initial, rounded := heap_bounds_model(model.start, model.end, size, alignment)
 if !valid { return false, 0, 0 }
 step := if alignment < alloc.gpu_page_size { alloc.gpu_page_size } else { alignment }
 mut candidate := initial
 mut found := false
 mut best := u64(0)
 mut best_span := ~u64(0)
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
  if fits && (!found || right - left < best_span) {
   found = true; best = candidate; best_span = right - left
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
 model.records << ModelReservation{va: address, size: rounded}
 return address, rounded
}

fn (mut model HeapRangeModel) release(address u64) {
 for mut record in model.records { if record.va == address { record.in_use = false; return } }
}

fn (mut model HeapRangeModel) collect() {
 mut index := model.records.len - 1
 for index >= 0 { if !model.records[index].in_use { model.records.delete(index) }; index-- }
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

fn reserve_checked(mut heap alloc.HeapAllocator, mut model HeapRangeModel, size u64, alignment u64) u64 {
 expected, rounded := model.reserve(size, alignment)
 address := heap.alloc(size, alignment) or { panic('production range reservation must fit') }
 assert address == expected && heap.top == model.top(), 'GPU range placement must match candidate-enumeration model'
 assert record_at(heap, address).size == rounded && heap.allocations.len == model.records.len
 mut previous_end := heap.start
 for record in heap.allocations {
  assert record.va >= previous_end && record.size <= heap.end - record.va,
   'GPU allocation records must remain sorted and nonoverlapping'
  previous_end = record.va + record.size
 }
 return address
}
