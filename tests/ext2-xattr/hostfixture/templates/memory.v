@[has_globals]
module memory
__global live_buffers = int(0)
pub fn calloc(size u64, count u64) voidptr {
 live_buffers++
 data := unsafe { malloc(int(size * count)) }
 unsafe { C.memset(data, 0, usize(size * count)) }
 return data
}
pub fn free(data voidptr) {
 if data == unsafe { nil } { return }
 live_buffers--
 unsafe { C.free(data) }
}
pub fn outstanding() int { return live_buffers }
fn C.memset(voidptr, int, usize) voidptr
fn C.free(voidptr)
