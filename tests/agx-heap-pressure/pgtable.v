module pgtable

pub const uat_pgsz = u64(16384)
pub const uat_pg_mask = uat_pgsz - 1

pub fn is_cached_noncoherent(_ u64) bool { return false }
