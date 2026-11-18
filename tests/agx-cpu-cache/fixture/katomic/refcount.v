module katomic
pub fn inc(mut value &u64) u64 { unsafe { *value = *value + 1; return *value } }
pub fn dec(mut value &u64) bool { unsafe { *value = *value - 1; return *value != 0 } }
pub fn load(value &u64) u64 { return unsafe { *value } }
