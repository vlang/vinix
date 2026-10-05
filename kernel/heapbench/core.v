// Shared opt-in allocator workload. The same generated V source is compiled
// with GCC for Vinix and XNU; only the native ABI header selects the platform.
@[translated]
module heapbench

#include "heap_benchmark_v.h"
fn C.vkb_alloc(usize) voidptr
fn C.vkb_free(voidptr)
fn C.vkb_log(&char, ...voidptr) i32

// Relaxed byte operations preserve every volatile payload access while
// introducing no hardware barriers or hidden allocations on either target.
@[c: '__atomic_load_n']
fn C.vkb_load8(&u8, i32) u8
@[c: '__atomic_store_n']
fn C.vkb_store8(&u8, u8, i32)

struct Measurement {
mut:
 ticks u64
 checksum u64
 expected u64
}
struct Failure {
mut:
 reason &char
 iteration u64
 size usize
 offset usize
 value u8
}

const sizes = [usize(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]!

fn zeroed(pointer voidptr, size usize, failure &Failure) i32 {
 unsafe {
  bytes := &u8(pointer)
  for offset := usize(0); offset < size; offset++ {
   value := C.vkb_load8(bytes + offset, 0)
   if value != 0 {
    failure.reason = c'nonzero_allocation'
    failure.size = size
    failure.offset = offset
    failure.value = value
    return -1
   }
  }
  return 0
 }
}

fn hot(measurement &Measurement, failure &Failure, validate_zero bool) i32 {
 unsafe {
  start := ticks()
  for i := u64(0); i < 100000; i++ {
   pointer := C.vkb_alloc(64)
   if usize(pointer) == 0 {
    failure.reason = c'allocation_failed'
    failure.iteration = i
    failure.size = 64
    return -1
   }
   if validate_zero && zeroed(pointer, 64, failure) != 0 {
    failure.iteration = i
    C.vkb_free(pointer)
    return -1
   }
   bytes := &u8(pointer)
   first := u8(i)
   last := u8(i ^ 0x5a)
   C.vkb_store8(bytes, first, 0)
   C.vkb_store8(bytes + 63, last, 0)
   measurement.checksum += u64(C.vkb_load8(bytes, 0)) + C.vkb_load8(bytes + 63, 0)
   measurement.expected += u64(first) + last
   C.vkb_free(pointer)
  }
  end := ticks()
  if end <= start { failure.reason = c'nonmonotonic_tsc'; return -1 }
  measurement.ticks = end - start
  return 0
 }
}

fn big(measurement &Measurement, failure &Failure, validate_zero bool) i32 {
 unsafe {
  start := ticks()
  for i := u64(0); i < 128; i++ {
   pointer := C.vkb_alloc(262144)
   if usize(pointer) == 0 {
    failure.reason = c'allocation_failed'
    failure.iteration = i
    failure.size = 262144
    return -1
   }
   if validate_zero && zeroed(pointer, 262144, failure) != 0 {
    failure.iteration = i
    C.vkb_free(pointer)
    return -1
   }
   bytes := &u8(pointer)
   first := u8(i)
   last := u8(i ^ 0x5a)
   C.vkb_store8(bytes, first, 0)
   C.vkb_store8(bytes + 262143, last, 0)
   measurement.checksum += u64(C.vkb_load8(bytes, 0)) + C.vkb_load8(bytes + 262143, 0)
   measurement.expected += u64(first) + last
   C.vkb_free(pointer)
  }
  end := ticks()
  if end <= start { failure.reason = c'nonmonotonic_tsc'; return -1 }
  measurement.ticks = end - start
  return 0
 }
}

fn free_live(objects &voidptr) {
 unsafe {
  for i := usize(0); i < 256; i++ {
   if usize(objects[i]) != 0 { C.vkb_free(objects[i]); objects[i] = nil }
  }
 }
}

fn batch(measurement &Measurement, failure &Failure, validate_zero bool) i32 {
 unsafe {
  mut objects := [256]voidptr{}
  start := ticks()
  for round := u64(0); round < 48; round++ {
   for i := usize(0); i < 256; i++ {
    iteration := round * 256 + u64(i)
    size := sizes[iteration % 14]
    pointer := C.vkb_alloc(size)
    if usize(pointer) == 0 {
     failure.reason = c'allocation_failed'
     failure.iteration = iteration
     failure.size = size
     free_live(&objects[0])
     return -1
    }
    objects[i] = pointer
    if validate_zero && zeroed(pointer, size, failure) != 0 {
     failure.iteration = iteration
     free_live(&objects[0])
     return -1
    }
    bytes := &u8(pointer)
    C.vkb_store8(bytes, u8(i), 0)
    C.vkb_store8(bytes + size - 1, u8(round), 0)
   }
   for i := usize(0); i < 256; i++ {
    index := (i * 73 + usize(round) * 19) & 255
    size := sizes[(round * 256 + u64(index)) % 14]
    bytes := &u8(objects[index])
    measurement.checksum += u64(C.vkb_load8(bytes, 0)) + C.vkb_load8(bytes + size - 1, 0)
    measurement.expected += u64(u8(index)) + u8(round)
    C.vkb_free(objects[index])
    objects[index] = nil
   }
  }
  end := ticks()
  if end <= start { failure.reason = c'nonmonotonic_tsc'; return -1 }
  measurement.ticks = end - start
  return 0
 }
}

fn sort(values &u64) {
 unsafe {
  for i := usize(1); i < 5; i++ {
   value := values[i]
   mut position := i
   for position != 0 && values[position - 1] > value { values[position] = values[position - 1]; position-- }
   values[position] = value
  }
 }
}

fn phase(name &char, pairs u64, run fn (&Measurement, &Failure, bool) i32, total_checksum &u64) i32 {
 unsafe {
  mut samples := [5]u64{}
  mut phase_checksum := u64(0)
  for sample := u32(0); sample <= 5; sample++ {
   mut measurement := Measurement{}
   mut failure := Failure{reason: c'unknown'}
   if run(&measurement, &failure, sample == 0) != 0 {
    C.vkb_log(c'KALLOC-ERROR platform=%s phase=%s sample=%llu reason=%s iteration=%llu size=%llu offset=%llu value=%llu\n',
     C.VKB_PLATFORM, name, u64(sample), failure.reason, failure.iteration, u64(failure.size), u64(failure.offset), u64(failure.value))
    return -1
   }
   if measurement.checksum != measurement.expected || (sample != 0 && measurement.checksum != phase_checksum) {
    C.vkb_log(c'KALLOC-ERROR platform=%s phase=%s sample=%llu reason=payload_checksum checksum=%llu expected=%llu\n',
     C.VKB_PLATFORM, name, u64(sample), measurement.checksum, measurement.expected)
    return -1
   }
   phase_checksum = measurement.checksum
   if sample == 0 { continue }
   samples[sample - 1] = measurement.ticks
   C.vkb_log(c'KALLOC-SAMPLE platform=%s phase=%s sample=%llu pairs=%llu ticks=%llu ticks_per_pair=%llu checksum=%llu\n',
    C.VKB_PLATFORM, name, u64(sample), pairs, measurement.ticks, measurement.ticks / pairs, measurement.checksum)
  }
  sort(&samples[0])
  C.vkb_log(c'KALLOC-RESULT platform=%s phase=%s pairs=%llu samples=%llu warmup_pairs=%llu median_ticks=%llu min_ticks=%llu max_ticks=%llu median_ticks_per_pair=%llu checksum=%llu\n',
   C.VKB_PLATFORM, name, pairs, u64(5), pairs, samples[2], samples[0], samples[4], samples[2] / pairs, phase_checksum)
  *total_checksum += phase_checksum
  return 0
 }
}

@[export: 'alloc_kernel_bench']
pub fn run() i32 {
 unsafe {
  mut checksum := u64(0)
  // IOLog truncates at 256 bytes; keep three separate metadata records.
  C.vkb_log(c'KALLOC-META schema=3 platform=%s timer=x86-tsc samples=%llu hot_pairs=%llu batch_rounds=%llu batch_width=%llu big_pairs=%llu big_bytes=%llu operation=alloc_free_pair\n',
   C.VKB_PLATFORM, u64(5), u64(100000), u64(48), u64(256), u64(128), u64(262144))
  C.vkb_log(c'KALLOC-VALIDATION platform=%s sizes=16,32,48,64,96,128,192,256,384,512,768,1024,1536,2048 zero_validation=warmup_every_requested_byte payload_validation=endpoints timed_zero_validation=0\n', C.VKB_PLATFORM)
  C.vkb_log(c'KALLOC-COMPILER platform=%s compiler=%s compiler_major=%llu compiler_minor=%llu compiler_patch=%llu\n',
   C.VKB_PLATFORM, C.VKB_COMPILER, u64(C.VKB_COMPILER_MAJOR), u64(C.VKB_COMPILER_MINOR), u64(C.VKB_COMPILER_PATCH))
  if phase(c'hot64', 100000, hot, &checksum) != 0 || phase(c'mixed256', 12288, batch, &checksum) != 0 || phase(c'big262144', 128, big, &checksum) != 0 { return 1 }
  C.vkb_log(c'KALLOC-DONE platform=%s phases=3 checksum=%llu\n', C.VKB_PLATFORM, checksum)
  return 0
 }
}

@[export: 'kmod_alloc_start']
pub fn kmod_start(kmod_info voidptr, data voidptr) i32 { _ = kmod_info; _ = data; return if run() == 0 { 0 } else { 5 } }
@[export: 'kmod_alloc_stop']
pub fn kmod_stop(kmod_info voidptr, data voidptr) i32 { _ = kmod_info; _ = data; return 0 }
