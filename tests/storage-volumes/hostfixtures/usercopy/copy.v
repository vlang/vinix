module usercopy
pub fn copy_from_user(to voidptr, from u64, bytes u64) bool { if from==0 { return false }; unsafe { C.memcpy(to,voidptr(from),bytes) }; return true }
pub fn copy_to_user(to u64, from voidptr, bytes u64) bool { if to==0 { return false }; unsafe { C.memcpy(voidptr(to),from,bytes) }; return true }
