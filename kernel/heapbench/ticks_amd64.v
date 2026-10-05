module heapbench

fn ticks() u64 {
 mut low := u32(0)
 mut high := u32(0)
 asm volatile amd64 {
  lfence
  rdtsc
  lfence
  ; =a (low)
    =d (high)
  ;
  ; memory
 }
 return u64(low) | (u64(high) << 32)
}
