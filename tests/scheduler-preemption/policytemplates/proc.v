
module proc
pub const rank_deadline = 200
pub struct SchedParams { pub mut: urgency int dl_abs_deadline u64 }
pub fn (s &SchedParams) rank() int { return s.urgency }
pub struct Thread { pub mut: sched SchedParams affinity_mask u64 }
pub fn effective_sched_rank(t &Thread) int { return t.sched.rank() }
