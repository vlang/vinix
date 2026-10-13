@[has_globals]
module memory
__global (pub live int pub left int = -1 pub check_zero_size u64 pub check_zero_ptr voidptr pub check_zero_frees int pub check_zero_failed bool)
pub fn user_address_limit() u64 { return 0 }
pub fn malloc_packed_fallible(size u64) voidptr {
 if left==0 { return unsafe { nil } }; if left>0 { left-- }
 p:=unsafe { C.malloc(size) }; if p!=unsafe { nil } { live++; if check_zero_size != 0 && size == check_zero_size { check_zero_ptr = p } }; return p
}
pub fn calloc(size u64, count u64) voidptr { p:=malloc_packed_fallible(size*count); if p!=unsafe { nil } { unsafe { C.memset(p,0,size*count) } }; return p }
pub fn free(p voidptr) { if p!=unsafe { nil } { if p == check_zero_ptr && check_zero_size != 0 { unsafe { for i in 0 .. check_zero_size { if (&u8(p))[i] != 0 { check_zero_failed = true } } }; check_zero_ptr = unsafe { nil }; check_zero_frees++ }; live--; unsafe { C.free(p) } } }
