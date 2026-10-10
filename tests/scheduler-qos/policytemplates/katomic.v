module katomic
pub fn load[T](here &T) T { return *here }
pub fn store[T](mut here T, value T) { unsafe { C.memcpy(voidptr(here), &value, sizeof(T)) } }
