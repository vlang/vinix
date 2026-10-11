@[has_globals]
module kbudget
__global (pub host_budget_live i64 pub host_budget_deny bool)
pub struct Charge { pub: bytes u64 }
pub enum Kind { file }
pub fn reserve(bytes u64) ?Charge { if host_budget_deny { return none }; host_budget_live += i64(bytes); return Charge{bytes:bytes} }
pub fn release(charge Charge) { host_budget_live -= i64(charge.bytes) }
