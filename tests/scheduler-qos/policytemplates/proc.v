@[has_globals]
module proc
import katomic
import klock
import errno
const max_priority_donations = 2048
const max_priority_chain = 64
struct PriorityDonation { mut: waiter &Thread = unsafe { nil } owner &Thread = unsafe { nil } }
__global (priority_lock klock.Lock priority_donations [max_priority_donations]PriorityDonation priority_donation_count u64)
pub struct SchedParams { pub mut: urgency int util_min u32 util_max u32 = 1024 }
pub fn (s &SchedParams) rank() int { return s.urgency }
pub struct Thread { pub mut: tid int sched SchedParams pi_rank int pins int affinity_mask u64 = 15 }
pub fn pin_thread(t &Thread) { unsafe { (&Thread(t)).pins++ } }
pub fn unpin_thread(t &Thread) { unsafe { (&Thread(t)).pins-- }; assert t.pins >= 0 }
