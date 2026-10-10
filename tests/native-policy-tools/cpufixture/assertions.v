
fn main() {
    mut once := CPUIntervalTimer{deadline_ns: 100}
    assert !expire_cpu_timer(mut once, 99)
    assert expire_cpu_timer(mut once, 100)
    assert once.deadline_ns == 0
    assert !expire_cpu_timer(mut once, 101)
    mut period := CPUIntervalTimer{deadline_ns: 100, interval_ns: 30}
    assert expire_cpu_timer(mut period, 195)
    assert period.deadline_ns == 220
    assert !expire_cpu_timer(mut period, 219)
    assert expire_cpu_timer(mut period, 220)
    assert period.deadline_ns == 250
    mut near_wrap := CPUIntervalTimer{deadline_ns: u64(-1)-10, interval_ns: 30}
    assert expire_cpu_timer(mut near_wrap, u64(-1)-5)
    assert near_wrap.deadline_ns == u64(-1)
    huge_value, _ := cpu_timer_value(CPUIntervalTimer{deadline_ns: u64(-1)}, 0)
    assert huge_value == u64(-1) / 1000 + 1
    one_us, _ := cpu_timer_value(CPUIntervalTimer{deadline_ns: 1}, 0)
    assert one_us == 1

    mut p := Process{cpu_limit: RLimit{cur: 1, max: 3}}
    p.cpu_time_ns = 999999999
    assert cpu_signals_locked(mut p) == 0
    p.cpu_time_ns = 1000000000
    assert cpu_signals_locked(mut p) == u64(1) << 23
    assert cpu_signals_locked(mut p) == 0
    p.cpu_time_ns = 2000000000
    assert cpu_signals_locked(mut p) == u64(1) << 23
    p.cpu_time_ns = 3000000000
    assert cpu_signals_locked(mut p) == u64(1) << 8
    assert cpu_signals_locked(mut p) == 0
    mut unlimited := Process{cpu_time_ns: u64(-1)}
    assert cpu_signals_locked(mut unlimited) == 0
    mut zero := Process{cpu_limit: RLimit{cur: 0, max: 0}}
    zero.cpu_time_ns = 999999999
    assert cpu_signals_locked(mut zero) == 0
    zero.cpu_time_ns = 1000000000
    assert cpu_signals_locked(mut zero) == u64(1) << 8
    mut separate := Process{}
    separate.cpu_timers[0] = CPUIntervalTimer{deadline_ns: 100}
    separate.cpu_timers[1] = CPUIntervalTimer{deadline_ns: 100}
    separate.cpu_time_ns = 100
    assert cpu_signals_locked(mut separate) == u64(1) << 26
    separate.cpu_user_ns = 100
    assert cpu_signals_locked(mut separate) == u64(1) << 25
    println('CPU timer/limit arithmetic: PASS')
}
