// SPDX-License-Identifier: GPL-2.0-or-later
// Qualification-only kernel source; record samples before printing any trace.
module main

import os

fn run() ! {
	if os.args.len != 3 { return error('Usage: selecttimeout-trace PSELECT-SOURCE FRESH-OUTPUT') }
	if os.exists(os.args[2]) { return error('Fresh output required') }
	mut source := os.read_file(os.args[1])!
	anchor := 'unsafe { *remaining = select_remaining(deadline) }'
	if source.count(anchor) != 2 { return error('Different select source layout') }
	start := source.index('fn select_finish_timeout(') or { return error('Missing finish helper') }
	end := source.index('// pselect6(nfds,') or { return error('Missing entrypoint boundary') }
	old := source[start..end]
	trace := "now := time.clock_now(time.clock_type_monotonic) or { time.TimeSpec{} }\n\tunsafe { *remaining = deadline }\n\tremaining.sub(now)\n\tif timeval && i32(proc.current_thread().syscall_x0) < 0 && select_timeout_traces < 32 {\n\t\tselect_timeout_traces++\n\t\tC.printf_benchmark(c'SELECT-TIME: deadline=%lld/%lld now=%lld/%lld left=%lld/%lld\\n', deadline.tv_sec,deadline.tv_nsec,now.tv_sec,now.tv_nsec,remaining.tv_sec,remaining.tv_nsec)\n\t}"
	source = source.replace(old,old.replace(anchor,trace))
	// Reuse memory's native printf_benchmark declaration on x86-64.
	source = source.replace('import usercopy','import usercopy\n\n__global select_timeout_traces u32')
	os.write_file(os.args[2],source)!
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
