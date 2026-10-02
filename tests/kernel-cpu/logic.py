#!/usr/bin/env python3
"""Exercise production timer/limit arithmetic with synthetic CPU counters."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
source = (root / "kernel/proc/cpu_account.v").read_text()


def function(name):
    begin = source.index(f"fn {name}(")
    brace = source.index("{", begin)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[begin:end] + "\n"


program = """
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
"""
for name in ("expire_cpu_timer", "cpu_signals_locked", "cpu_timer_value"):
    program += function(name)
program += """
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
"""
with tempfile.TemporaryDirectory(prefix="vinix-cpu-logic-") as directory:
    path = Path(directory) / "cpu.v"
    path.write_text(program)
    subprocess.run([os.environ.get("V", "v"), "run", str(path)], check=True)
