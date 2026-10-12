module katomic
import policytransport
pub fn load[T](value &T) T { return policytransport.load(value) }
pub fn store[T](mut value T, item T) { policytransport.store(unsafe { &u32(value) }, u32(item)) }
