module katomic
pub fn load[T](v &T) T { return unsafe { *v } }
pub fn cas[T](mut v T, before T, after T) bool { if v!=before { return false }; v=after; return true }
pub fn inc[T](mut v T) T { old:=v; v++; return old }
pub fn dec[T](mut v T) bool { v--; remaining:=v; return remaining!=0 }
