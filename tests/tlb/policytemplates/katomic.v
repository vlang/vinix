module katomic
pub fn load[T](p &T) T { return *p }
pub fn store[T](mut p T, value T) { unsafe { C.memcpy(voidptr(p), &value, sizeof(T)) } }
pub fn dec[T](mut p T) bool { unsafe { *p -= 1 }; return *p != 0 }
