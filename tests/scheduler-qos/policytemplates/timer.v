
struct TimeSpec { mut: tv_sec i64 tv_nsec i64 }
fn (mut t TimeSpec) sub(other TimeSpec) bool {
 if other.tv_nsec > t.tv_nsec { t.tv_sec--; t.tv_nsec += 1000000000 }
 t.tv_nsec -= other.tv_nsec
 t.tv_sec -= other.tv_sec
 return t.tv_sec < 0 || (t.tv_sec == 0 && t.tv_nsec == 0)
}
struct Timer { mut: when TimeSpec index int = -1 fired bool deadline_ns u64 absolute_realtime bool slack_ns u64 }
const clock_type_realtime = 0
__global (timers_lock klock.Lock armed_timers []&Timer fake_now u64 = 1000000000 fake_wall TimeSpec
 deadline_hooks [8]fn () u64 deadline_hooks_len int wake_requests int)
fn monotonic_ns() u64 { return fake_now }
fn clock_now(_ int) ?TimeSpec { return fake_wall }
fn deadline_changed() { wake_requests++ }
