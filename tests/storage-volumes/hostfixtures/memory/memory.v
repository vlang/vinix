@[has_globals]
module memory
__global (pub live int pub left int = -1)
pub fn user_address_limit() u64 { return 0 }
pub fn malloc_packed_fallible(size u64) voidptr {
 if left==0 { return unsafe { nil } }; if left>0 { left-- }
 p:=unsafe { C.malloc(size) }; if p!=unsafe { nil } { live++ }; return p
}
pub fn calloc(size u64, count u64) voidptr { p:=malloc_packed_fallible(size*count); if p!=unsafe { nil } { unsafe { C.memset(p,0,size*count) } }; return p }
pub fn free(p voidptr) { if p!=unsafe { nil } { live--; unsafe { C.free(p) } } }
