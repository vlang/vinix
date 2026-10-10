
module main
const rlim_infinity = u64(-1)
struct RLimit { mut: cur u64 max u64 }
struct CPUIntervalTimer { mut: deadline_ns u64 interval_ns u64 }
struct Process {
mut:
    cpu_timers [2]CPUIntervalTimer
    cpu_user_ns u64
    cpu_time_ns u64
    cpu_limit RLimit = RLimit{cur: rlim_infinity, max: rlim_infinity}
    cpu_xcpu_next_second u64
    cpu_kill_sent bool
}
