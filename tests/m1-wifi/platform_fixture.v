module m1core
fn C.vinix_m1_test_clock_us() u64
fn C.vinix_m1_test_delay(u32)
fn C.vinix_m1_test_barrier()
fn C.vinix_m1_test_cache_sync(voidptr, usize, i32)
fn m1_clock_us() u64 { return C.vinix_m1_test_clock_us() }
fn m1_delay(us u32) { C.vinix_m1_test_delay(us) }
fn m1_barrier() { C.vinix_m1_test_barrier() }
fn m1_cache_sync(p voidptr, n usize, direction i32) { C.vinix_m1_test_cache_sync(p,n,direction) }
