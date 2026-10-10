
module katomic
pub fn load[T](here &T) T { return *here }
pub fn store[T](mut here T, value T) {
    unsafe { C.memcpy(voidptr(here), &value, sizeof(T)) }
}
pub fn cas[T](mut here T, previous T, value T) bool {
    if unsafe { C.memcmp(voidptr(here), &previous, sizeof(T)) } != 0 { return false }
    unsafe { C.memcpy(voidptr(here), &value, sizeof(T)) }
    return true
}
