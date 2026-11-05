module devcore

pub struct Device {}

pub const second = u64(1000000000)

pub struct Deadline {}

pub fn deadline(_ u64) Deadline { return Deadline{} }

pub fn (_ Deadline) expired() bool { return true }

pub fn relax() {}
